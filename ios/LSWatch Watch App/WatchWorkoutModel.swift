//
//  WatchWorkoutModel.swift
//  LSWatch Watch App
//
//  Watch-side data + connectivity + haptics core (SOW §4/§6).
//
//  Owns the watch's `WCSession`, decodes the phone's authoritative snapshot,
//  applies local optimistic mutations, sends them back to the phone over
//  WatchConnectivity, drives rest-timer + completion haptics, and holds the
//  HealthKit live-workout session through `WorkoutSessionManager`.
//
//  WIRE CONTRACT: every dictionary on the wire has top-level keys
//  "kind" ∈ {snapshot, mutation, resync} and (except for resync) a "json"
//  String payload. The Codable structs below mirror the phone's
//  WatchSessionSnapshot / WatchMutation exactly (same JSON keys).
//
//  RECONCILIATION: sets are append-only keyed by `set.id` and deduped on both
//  sides; edit/delete/goto/rest are last-writer-wins; finish/discard are
//  terminal (first wins). On snapshot receipt the snapshot is authoritative for
//  queue/cursor/rest/meta, but loggedSets are UNIONED by id with any local
//  optimistic sets not yet echoed back.
//

import Foundation
import HealthKit
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit

// MARK: - Wire models (mirror the phone's WatchSessionSnapshot / WatchMutation)

/// One logged set. `id` is the idempotency key for the append-only set log.
struct WatchSetVM: Codable, Identifiable, Equatable {
  var id: String
  /// Owning exercise — sent up so the phone attributes by identity, not cursor.
  /// Optional for back-compat with pre-drop-set snapshots.
  var exerciseId: String?
  var reps: Int
  var weightKg: Double
  var rir: Int
  // Epoch millis as Int64: watchOS device builds are arm64_32 (32-bit Int), and
  // ms-since-1970 (~1.75e12) overflows a 32-bit Int.
  var loggedAtMs: Int64
  /// Set-group primitive (drop set). NULL => singleton group keyed by `id`.
  var setGroup: String?
  /// Order within the group: 0 = top, 1..N = drops.
  var groupSeq: Int?

  /// Effective group key for distinct-group counting.
  var groupKey: String { setGroup ?? id }
}

/// One slot in the workout queue, flattened for the watch.
struct WatchExerciseVM: Codable, Identifiable, Equatable {
  var programExerciseId: String
  var exerciseId: String
  var name: String
  var targetSets: Int
  var targetRepsMin: Int
  var targetRepsMax: Int
  var defaultWeightKg: Double
  var weightStepKg: Double?
  var isOverridden: Bool
  /// Optional on the wire so a stale App-Group snapshot written by a
  /// pre-skip-feature phone build still decodes (missing => not skipped).
  var skipped: Bool?
  /// 0/absent = normal; N ≥ 1 = each working set is a drop set with N drops.
  var dropCount: Int?
  var loggedSets: [WatchSetVM]

  /// Stable identity for SwiftUI lists.
  var id: String { programExerciseId }

  /// Whether this slot was skipped for the session (phone-only mutation).
  var isSkipped: Bool { skipped ?? false }

  /// Whether this is a drop-set exercise.
  var isDropSet: Bool { (dropCount ?? 0) > 0 }

  /// Logical sets completed = distinct group keys among logged rows (a drop
  /// set's top+drops count once).
  var completedGroups: Int { Set(loggedSets.map { $0.groupKey }).count }
}

/// The full state-of-record pushed phone -> watch.
struct WatchSession: Codable, Equatable {
  var schemaVersion: Int
  var sessionId: String?
  var programDayName: String
  // Int64 for the ms epoch + ARGB ints (high bit set) — see WatchSetVM note;
  // these overflow a 32-bit Int on arm64_32 watch device builds.
  var startedAtMs: Int64
  var unit: String
  var accentArgb: Int64
  var accentInkArgb: Int64
  var cursorExerciseIdx: Int
  var restEndsAtMs: Int64
  var restDefaultSeconds: Int
  /// Empty-bar weight in kg (mirrors the phone setting). Optional on the wire so
  /// a stale App-Group snapshot from a pre-plate-feature phone build still
  /// decodes; `barKg` falls back to the standard 20 kg bar when absent.
  var barWeightKg: Double?
  /// Available plate denominations in kg (mirrors the phone setting). Optional
  /// for the same back-compat reason; `plateInventory` falls back to the
  /// canonical gym set when absent.
  var plateInventoryKg: [Double]?
  var queue: [WatchExerciseVM]

  /// Effective bar weight for plate math — the snapshot value, or the standard
  /// 20 kg Olympic bar when a stale snapshot omits it.
  var barKg: Double { barWeightKg ?? 20.0 }

  /// Effective plate inventory for plate math — the snapshot value, or the
  /// canonical gym set when a stale snapshot omits it.
  var plateInventory: [Double] {
    plateInventoryKg ?? [25, 20, 15, 10, 5, 2.5, 1.25]
  }
}

/// The kind of change one device tells the other about. Raw values are the exact
/// lowercase strings on the wire.
enum WatchMutationType: String, Codable {
  case logSet
  case editSet
  case deleteSet
  case gotoExercise
  case restSet
  case finish
  case discard
}

/// A single change event. Append-only set log + LWW for edits/cursor/rest.
struct WatchMutation: Codable {
  var type: WatchMutationType
  var sessionId: String
  var deviceId: String
  // Int64: `seq` is seeded from wall-clock ms (monotonic across launches) and
  // `timestampMs` is a ms epoch — both overflow a 32-bit Int on the watch.
  var seq: Int64
  var timestampMs: Int64
  var set: WatchSetVM?
  var setId: String?
  var exerciseIdx: Int?
  var restEndsAtMs: Int64?
}

// MARK: - Watch workout model

@Observable
final class WatchWorkoutModel: NSObject, WCSessionDelegate {
  // MARK: Observable state

  /// nil => idle (no active workout). Authoritative session projection.
  var session: WatchSession?

  /// True when the phone counterpart is currently reachable.
  var reachable: Bool = false

  /// True briefly after a watch-initiated finish: shows the "workout complete"
  /// celebration instead of the plain idle screen, until dismissed or a new
  /// session arrives.
  var justFinished: Bool = false

  // MARK: Non-observed internals

  @ObservationIgnored private let appGroupId = "group.com.berkeucvet.lsWorkoutTracker"
  @ObservationIgnored private let snapshotKey = "watch.snapshot"
  @ObservationIgnored private let deviceId = "watch"

  /// Per-device monotonic counter for mutation dedupe + ordering.
  @ObservationIgnored private var seq: Int64 = 0

  /// Set ids we optimistically applied locally but haven't yet seen echoed back
  /// in a snapshot. Used to preserve them across the snapshot MERGE.
  @ObservationIgnored private var pendingLocalSetIds: Set<String> = []

  /// Terminal-state guard: once a session is finished/discarded we ignore later
  /// events for that sessionId (first-wins).
  @ObservationIgnored private var terminatedSessionIds: Set<String> = []

  /// HealthKit live-workout wrapper. Degrades gracefully if unauthorized.
  @ObservationIgnored let workoutManager = WorkoutSessionManager()
  @ObservationIgnored private var healthKitStarted = false

  /// Fires at rest end to play the rest-over haptic.
  @ObservationIgnored private var restTimer: Timer?

  // MARK: Init

  override init() {
    super.init()

    // Seed the mutation seq from wall-clock ms so it stays MONOTONIC ACROSS app
    // launches. A plain 0-based counter would reset on relaunch and collide with
    // seqs the phone already recorded, getting post-relaunch sets dropped as
    // "duplicates" on the phone — silent set loss.
    seq = nowMs()

    // Instant cold-launch render from the App-Group stash before the live
    // session activates / a fresh snapshot arrives.
    if let json = UserDefaults(suiteName: appGroupId)?.string(forKey: snapshotKey),
       let decoded = decodeSnapshot(json) {
      session = decoded
    }

    if WCSession.isSupported() {
      let wc = WCSession.default
      wc.delegate = self
      wc.activate()
    }

    syncHealthKit()
    rescheduleRestTimer()
    requestResyncIfReachable()
  }

  deinit {
    restTimer?.invalidate()
  }

  // MARK: - Computed projections

  /// The exercise at the current cursor, or nil if out of range / idle.
  var currentExercise: WatchExerciseVM? {
    guard let session, session.queue.indices.contains(session.cursorExerciseIdx) else { return nil }
    return session.queue[session.cursorExerciseIdx]
  }

  /// 1-based index of the current exercise for display (0 when idle).
  var exerciseIndex: Int {
    guard let session, !session.queue.isEmpty else { return 0 }
    return min(max(session.cursorExerciseIdx + 1, 1), session.queue.count)
  }

  var totalExercises: Int { session?.queue.count ?? 0 }

  /// Wall-clock elapsed since the workout started.
  var elapsed: TimeInterval {
    guard let session else { return 0 }
    let started = Date(timeIntervalSince1970: TimeInterval(session.startedAtMs) / 1000)
    return max(0, Date().timeIntervalSince(started))
  }

  /// Rest end as a Date, or nil when there's no active rest (0 / already past).
  var restEndsAt: Date? {
    guard let ms = session?.restEndsAtMs, ms > 0 else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    return date > Date() ? date : nil
  }

  var unit: String { session?.unit ?? "kg" }
  var accentArgb: Int64 { session?.accentArgb ?? 0xFFFF9500 }
  var accentInkArgb: Int64 { session?.accentInkArgb ?? 0xFF000000 }

  /// Empty-bar weight (kg) for the offline plate breakdown — mirrors the phone
  /// setting; falls back to the standard 20 kg bar when idle / pre-feature.
  var barKg: Double { session?.barKg ?? 20.0 }

  /// Plate inventory (kg) for the offline plate breakdown — mirrors the phone
  /// setting; falls back to the canonical gym set when idle / pre-feature.
  var plateInventory: [Double] {
    session?.plateInventory ?? [25, 20, 15, 10, 5, 2.5, 1.25]
  }

  // MARK: - Mutation senders (optimistic local apply, then send to phone)

  /// Log a set on the current exercise: append locally (deduped by id), advance
  /// the cursor when the target is met, play success haptic, auto-start rest.
  func logSet(reps: Int, weightKg: Double, rir: Int) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId),
          session.queue.indices.contains(session.cursorExerciseIdx) else { return }

    let set = WatchSetVM(
      id: UUID().uuidString,
      exerciseId: session.queue[session.cursorExerciseIdx].exerciseId,
      reps: reps,
      weightKg: weightKg,
      rir: rir,
      loggedAtMs: nowMs(),
      setGroup: nil,
      groupSeq: 0
    )

    // Append (dedupe by id) to the current exercise.
    var exercise = session.queue[session.cursorExerciseIdx]
    if !exercise.loggedSets.contains(where: { $0.id == set.id }) {
      exercise.loggedSets.append(set)
    }
    session.queue[session.cursorExerciseIdx] = exercise
    pendingLocalSetIds.insert(set.id)

    // Advance cursor when the target set count is met (in DISTINCT groups) and
    // there's a next non-skipped slot. Skipped slots are walked past (they stay
    // in the queue so indices line up with the phone).
    let targetMet = exercise.completedGroups >= exercise.targetSets
    var advancedTo: Int?
    if targetMet,
       let next = nextUnskippedIndex(after: session.cursorExerciseIdx, in: session.queue) {
      session.cursorExerciseIdx = next
      advancedTo = next
    }

    self.session = session

    WKInterfaceDevice.current().play(.success)

    sendMutation(makeMutation(.logSet, sessionId: sessionId, set: set))

    // If the cursor advanced as a result of this set, tell the phone (LWW cursor).
    if let cursor = advancedTo {
      sendMutation(makeMutation(.gotoExercise, sessionId: sessionId, exerciseIdx: cursor))
    }

    // Auto-start rest after a logged set if a default is configured.
    if session.restDefaultSeconds > 0 {
      startRest(sec: session.restDefaultSeconds)
    }
  }

  /// Log a drop set as ONE logical set: the top + its drops share a `set_group`
  /// (so it counts once), each is sent as a logSet mutation (the phone
  /// attributes by `exerciseId`, not the cursor), the cursor advances on the
  /// distinct-group target, then rest auto-starts. Atomic: the UI collects all
  /// entries before calling this. `rir` is only meaningful on the top entry.
  func logSetGroup(_ entries: [(reps: Int, weightKg: Double, rir: Int)]) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId),
          session.queue.indices.contains(session.cursorExerciseIdx),
          !entries.isEmpty else { return }

    let exerciseId = session.queue[session.cursorExerciseIdx].exerciseId
    let groupId = entries.count > 1 ? UUID().uuidString : nil
    var madeSets: [WatchSetVM] = []
    for (i, e) in entries.enumerated() {
      let set = WatchSetVM(
        id: UUID().uuidString,
        exerciseId: exerciseId,
        reps: e.reps,
        weightKg: e.weightKg,
        rir: e.rir,
        loggedAtMs: nowMs(),
        setGroup: groupId,
        groupSeq: i
      )
      madeSets.append(set)
      pendingLocalSetIds.insert(set.id)
    }

    var exercise = session.queue[session.cursorExerciseIdx]
    exercise.loggedSets.append(contentsOf: madeSets)
    session.queue[session.cursorExerciseIdx] = exercise

    let targetMet = exercise.completedGroups >= exercise.targetSets
    var advancedTo: Int?
    if targetMet,
       let next = nextUnskippedIndex(after: session.cursorExerciseIdx, in: session.queue) {
      session.cursorExerciseIdx = next
      advancedTo = next
    }

    self.session = session
    WKInterfaceDevice.current().play(.success)
    for set in madeSets {
      sendMutation(makeMutation(.logSet, sessionId: sessionId, set: set))
    }
    if let cursor = advancedTo {
      sendMutation(makeMutation(.gotoExercise, sessionId: sessionId, exerciseIdx: cursor))
    }
    if session.restDefaultSeconds > 0 {
      startRest(sec: session.restDefaultSeconds)
    }
  }

  /// Edit an existing set by id (last-writer-wins).
  func editSet(setId: String, reps: Int, weightKg: Double, rir: Int) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }

    var updated: WatchSetVM?
    for exIdx in session.queue.indices {
      if let setIdx = session.queue[exIdx].loggedSets.firstIndex(where: { $0.id == setId }) {
        var set = session.queue[exIdx].loggedSets[setIdx]
        set.reps = reps
        set.weightKg = weightKg
        set.rir = rir
        session.queue[exIdx].loggedSets[setIdx] = set
        updated = set
        break
      }
    }
    self.session = session
    guard let updated else { return }
    sendMutation(makeMutation(.editSet, sessionId: sessionId, set: updated, setId: setId))
  }

  /// Delete a set by id (last-writer-wins).
  func deleteSet(setId: String) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }

    for exIdx in session.queue.indices {
      session.queue[exIdx].loggedSets.removeAll { $0.id == setId }
    }
    pendingLocalSetIds.remove(setId)
    self.session = session
    sendMutation(makeMutation(.deleteSet, sessionId: sessionId, setId: setId))
  }

  /// Jump the cursor to a queue index (last-writer-wins). Refuses to land on a
  /// skipped slot (skip is permanent and phone-only).
  func goToExercise(idx: Int) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId),
          session.queue.indices.contains(idx),
          !session.queue[idx].isSkipped else { return }
    session.cursorExerciseIdx = idx
    self.session = session
    sendMutation(makeMutation(.gotoExercise, sessionId: sessionId, exerciseIdx: idx))
  }

  /// First non-skipped queue index strictly after [idx], or nil when none
  /// remain (the cursor then stays put — mirrors the watch's "stop on the last
  /// exercise" behaviour rather than going to an empty finished state).
  private func nextUnskippedIndex(after idx: Int, in queue: [WatchExerciseVM]) -> Int? {
    var i = idx + 1
    while i < queue.count {
      if !queue[i].isSkipped { return i }
      i += 1
    }
    return nil
  }

  /// Start (or restart) rest for `sec` seconds from now.
  func startRest(sec: Int) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }
    let endMs = nowMs() + Int64(sec) * 1000
    session.restEndsAtMs = endMs
    self.session = session
    rescheduleRestTimer()
    sendMutation(makeMutation(.restSet, sessionId: sessionId, restEndsAtMs: endMs))
  }

  /// Add (or subtract) seconds to the running rest. Clamps to "now" on the floor.
  func adjustRest(deltaSec: Int) {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }
    let base = max(session.restEndsAtMs, nowMs())
    let endMs = max(nowMs(), base + Int64(deltaSec) * 1000)
    session.restEndsAtMs = endMs
    self.session = session
    rescheduleRestTimer()
    sendMutation(makeMutation(.restSet, sessionId: sessionId, restEndsAtMs: endMs))
  }

  /// Cancel the running rest timer (restEndsAtMs = 0 => cancel).
  func cancelRest() {
    guard var session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }
    session.restEndsAtMs = 0
    self.session = session
    restTimer?.invalidate()
    restTimer = nil
    sendMutation(makeMutation(.restSet, sessionId: sessionId, restEndsAtMs: 0))
  }

  /// Finish the workout (terminal, first-wins). Ends + saves the HealthKit
  /// workout, sends the mutation, and drops to idle locally.
  func finish() {
    guard let session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }
    terminatedSessionIds.insert(sessionId)
    sendMutation(makeMutation(.finish, sessionId: sessionId))
    workoutManager.end(save: true)
    healthKitStarted = false
    justFinished = true
    teardownToIdle()
  }

  /// Discard the workout (terminal, first-wins). Ends WITHOUT saving HealthKit,
  /// sends the mutation, and drops to idle locally.
  func discard() {
    guard let session, let sessionId = session.sessionId,
          !terminatedSessionIds.contains(sessionId) else { return }
    terminatedSessionIds.insert(sessionId)
    sendMutation(makeMutation(.discard, sessionId: sessionId))
    workoutManager.end(save: false)
    healthKitStarted = false
    justFinished = false
    teardownToIdle()
  }

  /// Dismiss the post-finish "workout complete" screen (back to plain idle).
  func dismissFinished() {
    justFinished = false
  }

  // MARK: - WCSessionDelegate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async {
      self.reachable = session.isReachable
      if session.isReachable { self.requestResyncIfReachable() }
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    let isReachable = session.isReachable
    DispatchQueue.main.async {
      self.reachable = isReachable
      if isReachable { self.requestResyncIfReachable() }
    }
  }

  /// Phone -> watch via updateApplicationContext (durable latest snapshot).
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    handleIncoming(applicationContext)
  }

  /// Phone -> watch via sendMessage (fast path), no reply expected.
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    handleIncoming(message)
  }

  /// Phone -> watch via sendMessage, reply expected. We ack and process.
  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    handleIncoming(message)
    replyHandler(["ok": true])
  }

  /// Phone -> watch via transferUserInfo (durable).
  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    handleIncoming(userInfo)
  }

  // MARK: - Incoming dispatch

  private func handleIncoming(_ dict: [String: Any]) {
    guard let kind = dict["kind"] as? String else { return }
    switch kind {
    case "snapshot":
      guard let json = dict["json"] as? String, let incoming = decodeSnapshot(json) else { return }
      DispatchQueue.main.async { self.mergeSnapshot(incoming) }
    case "mutation":
      guard let json = dict["json"] as? String, let mutation = decodeMutation(json) else { return }
      DispatchQueue.main.async { self.applyRemoteMutation(mutation) }
    default:
      break
    }
  }

  // MARK: - Snapshot MERGE (RECON)

  /// Snapshot is authoritative for queue/cursor/rest/meta. loggedSets are
  /// UNIONED by id with any local optimistic sets not yet echoed back.
  private func mergeSnapshot(_ incoming: WatchSession) {
    // A null-session snapshot means "no active workout" — go fully idle so the
    // UI shows the idle / completion screen rather than an empty "all done"
    // workout. (The phone sends sessionId=nil + empty queue on finish/discard
    // and whenever there's no active session.)
    guard incoming.sessionId != nil else {
      session = nil
      pendingLocalSetIds.removeAll()
      restTimer?.invalidate()
      restTimer = nil
      syncHealthKit()
      return
    }
    // A fresh active session supersedes any "just finished" celebration.
    justFinished = false

    var merged = incoming

    if let local = session {
      // Build a lookup of all locally known sets so we can re-attach optimistic
      // ones that the incoming snapshot doesn't yet contain.
      var localSetsByExercise: [String: [WatchSetVM]] = [:]
      for ex in local.queue { localSetsByExercise[ex.programExerciseId] = ex.loggedSets }

      for exIdx in merged.queue.indices {
        let key = merged.queue[exIdx].programExerciseId
        var incomingSets = merged.queue[exIdx].loggedSets
        let incomingIds = Set(incomingSets.map(\.id))

        // Re-add optimistic local sets the snapshot hasn't echoed back yet.
        if let localSets = localSetsByExercise[key] {
          for set in localSets where pendingLocalSetIds.contains(set.id) && !incomingIds.contains(set.id) {
            incomingSets.append(set)
          }
        }
        merged.queue[exIdx].loggedSets = incomingSets
      }

      // Anything the incoming snapshot itself now contains has been echoed back
      // by the phone, so it's no longer a pending optimistic local set.
      let incomingAllIds = Set(incoming.queue.flatMap { $0.loggedSets.map(\.id) })
      pendingLocalSetIds.subtract(incomingAllIds)
    }

    session = merged
    rescheduleRestTimer()
    syncHealthKit()
  }

  // MARK: - Remote mutation apply (RECON, rarely used)

  /// Apply a phone-originated mutation. Snapshot is the reliable path, but the
  /// phone may also push the occasional mutation; we apply it idempotently.
  private func applyRemoteMutation(_ m: WatchMutation) {
    guard var session, let sessionId = session.sessionId, m.sessionId == sessionId else { return }
    if terminatedSessionIds.contains(sessionId) { return }

    switch m.type {
    case .logSet, .editSet:
      guard let set = m.set else { return }
      var applied = false
      for exIdx in session.queue.indices {
        if let setIdx = session.queue[exIdx].loggedSets.firstIndex(where: { $0.id == set.id }) {
          session.queue[exIdx].loggedSets[setIdx] = set // LWW
          applied = true
          break
        }
      }
      if !applied, m.type == .logSet, session.queue.indices.contains(session.cursorExerciseIdx) {
        // Append-only by id at the cursor (dedupe enforced by the search above).
        session.queue[session.cursorExerciseIdx].loggedSets.append(set)
      }
    case .deleteSet:
      guard let setId = m.setId else { return }
      for exIdx in session.queue.indices {
        session.queue[exIdx].loggedSets.removeAll { $0.id == setId }
      }
    case .gotoExercise:
      if let idx = m.exerciseIdx, session.queue.indices.contains(idx) {
        session.cursorExerciseIdx = idx // LWW
      }
    case .restSet:
      if let endMs = m.restEndsAtMs {
        session.restEndsAtMs = endMs // LWW
      }
    case .finish, .discard:
      terminatedSessionIds.insert(sessionId)
      workoutManager.end(save: m.type == .finish)
      healthKitStarted = false
      justFinished = (m.type == .finish)
      self.session = nil
      restTimer?.invalidate(); restTimer = nil
      return
    }

    self.session = session
    rescheduleRestTimer()
  }

  // MARK: - Sending

  private func makeMutation(
    _ type: WatchMutationType,
    sessionId: String,
    set: WatchSetVM? = nil,
    setId: String? = nil,
    exerciseIdx: Int? = nil,
    restEndsAtMs: Int64? = nil
  ) -> WatchMutation {
    seq += 1
    return WatchMutation(
      type: type,
      sessionId: sessionId,
      deviceId: deviceId,
      seq: seq,
      timestampMs: nowMs(),
      set: set,
      setId: setId,
      exerciseIdx: exerciseIdx,
      restEndsAtMs: restEndsAtMs
    )
  }

  /// Watch -> phone: durable via transferUserInfo, fast via sendMessage when
  /// reachable. The phone dedupes by (deviceId + seq).
  private func sendMutation(_ mutation: WatchMutation) {
    guard let json = encodeMutation(mutation) else { return }
    let payload: [String: Any] = ["kind": "mutation", "json": json]

    guard WCSession.isSupported() else { return }
    let wc = WCSession.default

    // Durable delivery (survives unreachability / relaunch).
    wc.transferUserInfo(payload)

    // Fast delivery when the phone is awake.
    if wc.isReachable {
      wc.sendMessage(payload, replyHandler: nil, errorHandler: { _ in /* durable path covers it */ })
    }
  }

  /// Watch -> phone: ask for a fresh snapshot (cold launch / reconnect).
  private func requestResyncIfReachable() {
    guard WCSession.isSupported() else { return }
    let wc = WCSession.default
    guard wc.activationState == .activated, wc.isReachable else { return }
    wc.sendMessage(["kind": "resync"], replyHandler: nil, errorHandler: { _ in })
  }

  // MARK: - Rest-end haptic timer

  /// Schedule a one-shot timer to fire at restEndsAt and play the rest-over
  /// haptic. Invalidates any existing timer first; no-ops when there's no rest.
  private func rescheduleRestTimer() {
    restTimer?.invalidate()
    restTimer = nil
    guard let end = restEndsAt else { return }
    let interval = end.timeIntervalSinceNow
    guard interval > 0 else { return }
    let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
      WKInterfaceDevice.current().play(.notification)
      self?.restTimer = nil
    }
    RunLoop.main.add(timer, forMode: .common)
    restTimer = timer
  }

  // MARK: - HealthKit lifecycle

  /// Drive the HealthKit live workout from the session's active/idle state.
  /// active (sessionId != nil) & not started -> start(); idle (nil) -> end.
  private func syncHealthKit() {
    let active = session?.sessionId != nil
    if active, !healthKitStarted {
      healthKitStarted = true
      workoutManager.start()
    } else if !active, healthKitStarted {
      healthKitStarted = false
      workoutManager.end(save: false)
    }
  }

  // MARK: - Helpers

  private func teardownToIdle() {
    restTimer?.invalidate()
    restTimer = nil
    pendingLocalSetIds.removeAll()
    session = nil
  }

  private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

  private func decodeSnapshot(_ json: String) -> WatchSession? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(WatchSession.self, from: data)
  }

  private func decodeMutation(_ json: String) -> WatchMutation? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(WatchMutation.self, from: data)
  }

  private func encodeMutation(_ mutation: WatchMutation) -> String? {
    guard let data = try? JSONEncoder().encode(mutation) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
