import Foundation
import Flutter
import WatchConnectivity

/// iPhone-side WatchConnectivity manager.
///
/// Owns the `WCSession` on the phone, implements the Pigeon `WatchBridgeHostApi`
/// (Dart -> Swift), and calls back into Dart via `WatchBridgeFlutterApi`
/// (Swift -> Dart).
///
/// WIRE CONTRACT (single source of truth, shared with the watch app):
/// every WCSession dictionary (message / applicationContext / userInfo) has
/// top-level keys:
///   "kind": "snapshot" | "mutation" | "resync"
///   "json": a JSON STRING payload (absent only for "resync")
/// The JSON string mirrors the Pigeon structs exactly (see below).
///
/// Transport rules:
///  - Phone->watch snapshot: updateApplicationContext + App-Group UserDefaults
///    stash + sendMessage (when reachable).
///  - Watch->phone mutation: transferUserInfo (durable) + sendMessage (fast);
///    the phone dedupes by (deviceId + seq).
///  - Phone->watch mutation: sendMessage when reachable (best effort).
///  - Watch->phone resync: sendMessage(["kind":"resync"]) -> onWatchRequestedResync.
///
/// Added to the **Runner** target. Wired up from
/// `AppDelegate.didInitializeImplicitFlutterEngine`.
final class WCSessionManager: NSObject {
  static let shared = WCSessionManager()

  /// App Group shared with the watch app for the durable snapshot stash.
  private static let appGroupId = "group.com.berkeucvet.lsWorkoutTracker"
  private static let snapshotDefaultsKey = "watch.snapshot"

  /// Top-level wire keys.
  private enum WireKey {
    static let kind = "kind"
    static let json = "json"
  }
  /// Top-level wire kinds.
  private enum WireKind {
    static let snapshot = "snapshot"
    static let mutation = "mutation"
    static let resync = "resync"
  }

  private var flutterApi: WatchBridgeFlutterApi?
  private var activated = false

  /// Latest known active session id (from the most recent pushed snapshot),
  /// surfaced to Dart when the watch (re)joins.
  private var lastSessionId: String?

  /// Dedupe ledger for inbound watch mutations, keyed by "deviceId:seq".
  /// Bounded so it cannot grow without limit over a long session.
  private var seenMutationKeys = Set<String>()
  private var seenMutationOrder = [String]()
  private let seenMutationLimit = 512
  private let dedupeLock = NSLock()

  /// Wire the Pigeon channels onto the engine's binary messenger. Called once
  /// at implicit-engine init, before any Dart UI runs.
  func bootstrap(messenger: FlutterBinaryMessenger) {
    WatchBridgeHostApiSetup.setUp(binaryMessenger: messenger, api: self)
    flutterApi = WatchBridgeFlutterApi(binaryMessenger: messenger)
    NSLog("[WCSessionManager] bootstrapped")
  }

  private var session: WCSession? {
    WCSession.isSupported() ? WCSession.default : nil
  }

  /// Hop to the main thread before touching the Flutter binary messenger —
  /// WCSession delegate callbacks arrive on a background queue.
  private func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
  }
}

// MARK: - WatchBridgeHostApi (Dart -> Swift)

extension WCSessionManager: WatchBridgeHostApi {
  func activate() throws {
    guard let session = session else {
      NSLog("[WCSessionManager] WCSession unsupported on this device")
      return
    }
    if activated { return }
    session.delegate = self
    session.activate()
    activated = true
    NSLog("[WCSessionManager] activate()")
  }

  func isPaired() throws -> Bool {
    session?.isPaired ?? false
  }

  func isReachable() throws -> Bool {
    session?.isReachable ?? false
  }

  /// Push the authoritative snapshot phone -> watch.
  /// applicationContext (latest-wins delivery) + App-Group stash (cold launch)
  /// + sendMessage (instant, when reachable).
  func pushSnapshot(snapshot: WatchSessionSnapshot) throws {
    let js = try Self.encodeSnapshotJSON(snapshot)
    lastSessionId = snapshot.sessionId

    // Durable App-Group stash so the watch can render on cold launch.
    if let defaults = UserDefaults(suiteName: Self.appGroupId) {
      defaults.set(js, forKey: Self.snapshotDefaultsKey)
    } else {
      NSLog("[WCSessionManager] WARN: App Group \(Self.appGroupId) unavailable")
    }

    guard let session = session else { return }

    let payload: [String: Any] = [WireKey.kind: WireKind.snapshot, WireKey.json: js]

    // Latest-wins background delivery.
    do {
      try session.updateApplicationContext(payload)
    } catch {
      NSLog("[WCSessionManager] updateApplicationContext error: \(error.localizedDescription)")
    }

    // Instant delivery when the watch app is foregrounded.
    if session.isReachable {
      session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
        NSLog("[WCSessionManager] snapshot sendMessage error: \(error.localizedDescription)")
      })
    }
    NSLog("[WCSessionManager] pushSnapshot session=\(snapshot.sessionId ?? "<nil>")")
  }

  /// Phone-originated mutation -> watch. Best effort: the snapshot is the
  /// reliable path, so this only fires over the fast channel when reachable.
  func sendMutation(mutation: WatchMutation) throws {
    let js = try Self.encodeMutationJSON(mutation)
    guard let session = session, session.isReachable else {
      NSLog("[WCSessionManager] sendMutation skipped (unreachable)")
      return
    }
    let payload: [String: Any] = [WireKey.kind: WireKind.mutation, WireKey.json: js]
    session.sendMessage(payload, replyHandler: nil, errorHandler: { error in
      NSLog("[WCSessionManager] mutation sendMessage error: \(error.localizedDescription)")
    })
    NSLog("[WCSessionManager] sendMutation seq=\(mutation.seq)")
  }
}

// MARK: - WCSessionDelegate

extension WCSessionManager: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith state: WCSessionActivationState,
    error: Error?
  ) {
    NSLog("[WCSessionManager] activationDidComplete: \(state.rawValue) error=\(String(describing: error))")
    let reachable = session.isReachable
    onMain { self.flutterApi?.onReachabilityChanged(reachable: reachable) { _ in } }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    NSLog("[WCSessionManager] reachabilityDidChange: \(reachable)")
    onMain {
      self.flutterApi?.onReachabilityChanged(reachable: reachable) { _ in }
      // When the watch becomes reachable, treat it as (re)joining the session
      // so the phone can light its "watch connected" indicator.
      if reachable {
        self.flutterApi?.onWatchJoinedSession(sessionId: self.lastSessionId ?? "") { _ in }
      }
    }
  }

  /// Watch -> phone, no reply expected (sendMessage fast path / resync).
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    handleIncoming(message, reply: nil)
  }

  /// Watch -> phone, reply expected.
  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    handleIncoming(message, reply: replyHandler)
  }

  /// Watch -> phone durable mutation (transferUserInfo). No reply channel.
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    handleIncoming(userInfo, reply: nil)
  }

  // iOS-only required stubs — the session can deactivate when the active watch
  // switches; reactivate so a re-paired watch keeps working.
  func sessionDidBecomeInactive(_ session: WCSession) {
    NSLog("[WCSessionManager] sessionDidBecomeInactive")
  }

  func sessionDidDeactivate(_ session: WCSession) {
    NSLog("[WCSessionManager] sessionDidDeactivate — reactivating")
    session.activate()
  }

  // MARK: Inbound dispatch

  private func handleIncoming(_ dict: [String: Any], reply: (([String: Any]) -> Void)?) {
    guard let kind = dict[WireKey.kind] as? String else {
      NSLog("[WCSessionManager] inbound dict missing 'kind': \(dict)")
      reply?(["ok": false])
      return
    }

    switch kind {
    case WireKind.mutation:
      guard let js = dict[WireKey.json] as? String,
            let mutation = Self.decodeMutationJSON(js) else {
        NSLog("[WCSessionManager] inbound mutation decode failed")
        reply?(["ok": false])
        return
      }
      // Dedupe by (deviceId + seq): the same mutation can arrive on both the
      // durable (transferUserInfo) and fast (sendMessage) channels.
      let key = "\(mutation.deviceId):\(mutation.seq)"
      if markSeen(key) {
        onMain { self.flutterApi?.onMutationReceived(mutation: mutation) { _ in } }
      } else {
        NSLog("[WCSessionManager] dropping duplicate mutation \(key)")
      }
      reply?(["ok": true])

    case WireKind.resync:
      NSLog("[WCSessionManager] watch requested resync")
      onMain { self.flutterApi?.onWatchRequestedResync { _ in } }
      reply?(["ok": true])

    case WireKind.snapshot:
      // Snapshots flow phone -> watch only; ignore if echoed back.
      NSLog("[WCSessionManager] ignoring inbound snapshot")
      reply?(["ok": true])

    default:
      NSLog("[WCSessionManager] inbound unknown kind: \(kind)")
      reply?(["ok": false])
    }
  }

  /// Records a dedupe key. Returns true if newly seen, false if a duplicate.
  private func markSeen(_ key: String) -> Bool {
    dedupeLock.lock()
    defer { dedupeLock.unlock() }
    if seenMutationKeys.contains(key) { return false }
    seenMutationKeys.insert(key)
    seenMutationOrder.append(key)
    if seenMutationOrder.count > seenMutationLimit {
      let evict = seenMutationOrder.removeFirst()
      seenMutationKeys.remove(evict)
    }
    return true
  }
}

// MARK: - JSON wire encoding / decoding (mirrors the Pigeon structs exactly)

extension WCSessionManager {

  // MARK: Snapshot (phone -> watch)

  fileprivate static func encodeSnapshotJSON(_ s: WatchSessionSnapshot) throws -> String {
    var obj: [String: Any] = [
      "schemaVersion": s.schemaVersion,
      "sessionId": s.sessionId ?? NSNull(),
      "programDayName": s.programDayName,
      "startedAtMs": s.startedAtMs,
      "unit": s.unit,
      "accentArgb": s.accentArgb,
      "accentInkArgb": s.accentInkArgb,
      "cursorExerciseIdx": s.cursorExerciseIdx,
      "restEndsAtMs": s.restEndsAtMs,
      "restDefaultSeconds": s.restDefaultSeconds,
      "barWeightKg": s.barWeightKg,
      "plateInventoryKg": s.plateInventoryKg,
    ]
    obj["queue"] = s.queue.map { exerciseToJSON($0) }
    return try serialize(obj)
  }

  private static func exerciseToJSON(_ e: WatchExercise) -> [String: Any] {
    var obj: [String: Any] = [
      "programExerciseId": e.programExerciseId,
      "exerciseId": e.exerciseId,
      "name": e.name,
      "targetSets": e.targetSets,
      "targetRepsMin": e.targetRepsMin,
      "targetRepsMax": e.targetRepsMax,
      "defaultWeightKg": e.defaultWeightKg,
      // weightStepKg null => caller falls back to the unit default.
      "weightStepKg": e.weightStepKg ?? NSNull(),
      "isOverridden": e.isOverridden,
      "skipped": e.skipped,
      "dropCount": e.dropCount,
    ]
    obj["loggedSets"] = e.loggedSets.map { setToJSON($0) }
    return obj
  }

  private static func setToJSON(_ st: WatchSet) -> [String: Any] {
    return [
      "id": st.id,
      "exerciseId": st.exerciseId,
      "reps": st.reps,
      "weightKg": st.weightKg,
      "rir": st.rir,
      "loggedAtMs": st.loggedAtMs,
      "setGroup": st.setGroup ?? NSNull(),
      "groupSeq": st.groupSeq,
    ]
  }

  // MARK: Mutation (encode for phone -> watch)

  fileprivate static func encodeMutationJSON(_ m: WatchMutation) throws -> String {
    let obj: [String: Any] = [
      "type": mutationTypeToString(m.type),
      "sessionId": m.sessionId,
      "deviceId": m.deviceId,
      "seq": m.seq,
      "timestampMs": m.timestampMs,
      "set": m.set.map { setToJSON($0) } ?? NSNull(),
      "setId": m.setId ?? NSNull(),
      "exerciseIdx": m.exerciseIdx ?? NSNull(),
      "restEndsAtMs": m.restEndsAtMs ?? NSNull(),
    ]
    return try serialize(obj)
  }

  // MARK: Mutation (decode for watch -> phone)

  fileprivate static func decodeMutationJSON(_ js: String) -> WatchMutation? {
    guard let data = js.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data, options: []),
          let obj = any as? [String: Any] else {
      return nil
    }
    guard let typeStr = obj["type"] as? String,
          let type = mutationTypeFromString(typeStr),
          let sessionId = obj["sessionId"] as? String,
          let deviceId = obj["deviceId"] as? String,
          let seq = int64(obj["seq"]),
          let timestampMs = int64(obj["timestampMs"]) else {
      return nil
    }

    let set: WatchSet? = setFromJSON(obj["set"])
    let setId: String? = string(obj["setId"])
    let exerciseIdx: Int64? = int64(obj["exerciseIdx"])
    let restEndsAtMs: Int64? = int64(obj["restEndsAtMs"])

    return WatchMutation(
      type: type,
      sessionId: sessionId,
      deviceId: deviceId,
      seq: seq,
      timestampMs: timestampMs,
      set: set,
      setId: setId,
      exerciseIdx: exerciseIdx,
      restEndsAtMs: restEndsAtMs
    )
  }

  private static func setFromJSON(_ value: Any?) -> WatchSet? {
    guard let obj = value as? [String: Any],
          let id = obj["id"] as? String,
          let reps = int64(obj["reps"]),
          let weightKg = double(obj["weightKg"]),
          let rir = int64(obj["rir"]),
          let loggedAtMs = int64(obj["loggedAtMs"]) else {
      return nil
    }
    let exerciseId = (obj["exerciseId"] as? String) ?? ""
    let setGroup = string(obj["setGroup"])
    let groupSeq = int64(obj["groupSeq"]) ?? 0
    return WatchSet(
      id: id,
      exerciseId: exerciseId,
      reps: reps,
      weightKg: weightKg,
      rir: rir,
      loggedAtMs: loggedAtMs,
      setGroup: setGroup,
      groupSeq: groupSeq
    )
  }

  // MARK: Enum <-> exact lowercase wire strings

  private static func mutationTypeToString(_ t: WatchMutationType) -> String {
    switch t {
    case .logSet: return "logSet"
    case .editSet: return "editSet"
    case .deleteSet: return "deleteSet"
    case .gotoExercise: return "gotoExercise"
    case .restSet: return "restSet"
    case .finish: return "finish"
    case .discard: return "discard"
    }
  }

  private static func mutationTypeFromString(_ s: String) -> WatchMutationType? {
    switch s {
    case "logSet": return .logSet
    case "editSet": return .editSet
    case "deleteSet": return .deleteSet
    case "gotoExercise": return .gotoExercise
    case "restSet": return .restSet
    case "finish": return .finish
    case "discard": return .discard
    default: return nil
    }
  }

  // MARK: Helpers

  private static func serialize(_ obj: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: obj, options: [])
    guard let str = String(data: data, encoding: .utf8) else {
      throw PigeonError(code: "encode_failed", message: "snapshot/mutation JSON not UTF-8", details: nil)
    }
    return str
  }

  /// Robust integer extraction (JSONSerialization yields NSNumber).
  private static func int64(_ value: Any?) -> Int64? {
    if let n = value as? NSNumber { return n.int64Value }
    if let i = value as? Int { return Int64(i) }
    if let i = value as? Int64 { return i }
    if let s = value as? String { return Int64(s) }
    return nil
  }

  private static func double(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let s = value as? String { return Double(s) }
    return nil
  }

  private static func string(_ value: Any?) -> String? {
    if value is NSNull { return nil }
    return value as? String
  }
}
