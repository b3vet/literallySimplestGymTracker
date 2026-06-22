// Pigeon schema for the iPhone <-> Apple Watch bridge.
//
// SINGLE SOURCE OF TRUTH for the Dart<->Swift seam on the PHONE side. Regenerate
// after any edit:
//
//   dart run pigeon --input pigeons/watch_bridge.dart
//
// Generated outputs (committed, no runtime dependency on pigeon):
//   - lib/features/workout/application/watch_bridge.g.dart   (Dart)
//   - ios/Runner/WatchBridge.g.swift                          (Swift, Runner target)
//
// The WATCH side is plain Swift (no Pigeon). The phone's WCSessionManager
// serialises these Pigeon structs to/from JSON for the WatchConnectivity wire;
// the watch app decodes that JSON into its own Swift model. Pigeon only types
// the in-app Dart<->Swift channel, not the device<->device transport.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/features/workout/application/watch_bridge.g.dart',
    swiftOut: 'ios/Runner/WatchBridge.g.swift',
    dartPackageName: 'ls_workout_tracker',
  ),
)
/// One logged set. `id` is authored by the originating device (phone or watch)
/// and is the idempotency key for the append-only set log (SOW §6).
class WatchSet {
  WatchSet({
    required this.id,
    required this.reps,
    required this.weightKg,
    required this.rir,
    required this.loggedAtMs,
  });
  String id;
  int reps;
  double weightKg;
  int rir;
  int loggedAtMs;
}

/// One slot in the workout queue, flattened for the watch.
class WatchExercise {
  WatchExercise({
    required this.programExerciseId,
    required this.exerciseId,
    required this.name,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    required this.defaultWeightKg,
    this.weightStepKg,
    required this.isOverridden,
    required this.loggedSets,
  });
  String programExerciseId;
  String exerciseId;
  String name;
  int targetSets;
  int targetRepsMin;
  int targetRepsMax;
  double defaultWeightKg;

  /// Per-exercise weight step in kg; null => caller falls back to the unit
  /// default.
  double? weightStepKg;

  /// True when this slot was substituted on the phone (read-only "SUBSTITUTED"
  /// badge on the watch; swapping is phone-only).
  bool isOverridden;

  List<WatchSet> loggedSets;
}

/// The full state-of-record pushed phone -> watch. A flattened projection of
/// `ActiveSession` + rest timer + settings.
class WatchSessionSnapshot {
  WatchSessionSnapshot({
    required this.schemaVersion,
    this.sessionId,
    required this.programDayName,
    required this.startedAtMs,
    required this.unit,
    required this.accentArgb,
    required this.accentInkArgb,
    required this.cursorExerciseIdx,
    required this.restEndsAtMs,
    required this.restDefaultSeconds,
    required this.queue,
  });

  /// Bump on contract change; the watch ignores unknown newer versions.
  int schemaVersion;

  /// Null => no active workout (idle state on the watch).
  String? sessionId;
  String programDayName;

  /// elapsed = now - startedAtMs, rendered locally on each device.
  int startedAtMs;

  /// "kg" | "lb" — the watch formats kg weights into this display unit.
  String unit;

  /// User accent forwarded as 0xAARRGGBB (same scheme as the Live Activity).
  int accentArgb;
  int accentInkArgb;

  int cursorExerciseIdx;

  /// 0 => no active rest; both devices render the countdown locally.
  int restEndsAtMs;

  /// Default rest length in seconds, so the watch can auto-start rest after a
  /// logged set (mirrors the phone setting).
  int restDefaultSeconds;

  List<WatchExercise> queue;
}

/// The kind of change one device is telling the other about (SOW §6).
enum WatchMutationType {
  logSet,
  editSet,
  deleteSet,
  gotoExercise,
  restSet,
  finish,
  discard,
}

/// A single change event. Append-only set log + LWW for edits/cursor/rest.
class WatchMutation {
  WatchMutation({
    required this.type,
    required this.sessionId,
    required this.deviceId,
    required this.seq,
    required this.timestampMs,
    this.set,
    this.setId,
    this.exerciseIdx,
    this.restEndsAtMs,
  });

  WatchMutationType type;
  String sessionId;

  /// "watch" | "phone" — merge attribution.
  String deviceId;

  /// Per-device monotonic counter; dedupe + ordering.
  int seq;

  /// Wall clock; LWW tiebreaker for edits/cursor/rest.
  int timestampMs;

  /// logSet / editSet — the set (its `id` authored by the originator).
  WatchSet? set;

  /// deleteSet — which set to remove.
  String? setId;

  /// gotoExercise — target queue index.
  int? exerciseIdx;

  /// restSet — new rest end (epoch ms); 0 => cancel rest.
  int? restEndsAtMs;
}

/// Dart -> Swift. Implemented natively by the WCSession manager in the Runner.
@HostApi()
abstract class WatchBridgeHostApi {
  /// Configure this device's WCSession and activate it. Safe to call repeatedly.
  void activate();

  /// Whether an Apple Watch is currently paired with this iPhone.
  bool isPaired();

  /// Whether the watch app counterpart is currently reachable.
  bool isReachable();

  /// Push the authoritative session snapshot to the watch (applicationContext +
  /// App-Group stash, plus an instant sendMessage when reachable). Pass a
  /// snapshot with a null `sessionId` to signal "no active workout".
  void pushSnapshot(WatchSessionSnapshot snapshot);

  /// Send a phone-originated mutation to the watch (e.g. the user logged a set
  /// on the phone while the watch is connected).
  void sendMutation(WatchMutation mutation);
}

/// Swift -> Dart. Implemented in Dart by the watch sync controller; the native
/// side calls these when WatchConnectivity events arrive.
@FlutterApi()
abstract class WatchBridgeFlutterApi {
  /// A mutation arrived from the watch (via sendMessage or transferUserInfo).
  void onMutationReceived(WatchMutation mutation);

  /// The watch asked for a fresh snapshot (cold launch / reconnect).
  void onWatchRequestedResync();

  /// The watch's reachability changed.
  void onReachabilityChanged(bool reachable);

  /// The watch app opened onto an active session (used to light the phone-side
  /// "watch connected" indicator).
  void onWatchJoinedSession(String sessionId);
}
