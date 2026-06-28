import 'dart:ui' show Color;

import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/active_session.dart';
import 'rest_timer_controller.dart';
import 'watch_bridge.g.dart';

/// Current snapshot contract version. Bump on any breaking change to the
/// flattened projection below; the watch ignores unknown newer versions.
///
/// v2: added `WatchExercise.skipped` (durable per-session skip flag).
/// v3: added `WatchExercise.dropCount` + `WatchSet.exerciseId/setGroup/groupSeq`
/// (drop sets on the general set-group primitive).
const int watchSnapshotSchemaVersion = 3;

/// Pure builder mapping the phone's authoritative state — the active session,
/// the rest timer, and user settings — into the flattened [WatchSessionSnapshot]
/// pushed to the watch (SOW §4). No side effects: takes plain values, returns a
/// snapshot. When [session] is null the result is the idle snapshot (null
/// sessionId, empty queue) signalling "no active workout".
WatchSessionSnapshot buildWatchSnapshot({
  required ActiveSession? session,
  required RestTimerState rest,
  required AppSettings settings,
}) {
  final accent = lsAccentSpec(settings.accent);
  final unit = settings.unit?.short ?? 'kg';

  // 0 => no active rest. An expired endsAt is treated as "none".
  final now = DateTime.now();
  final endsAt = rest.endsAt;
  final restEndsAtMs = (endsAt != null && endsAt.isAfter(now))
      ? endsAt.millisecondsSinceEpoch
      : 0;

  if (session == null) {
    return WatchSessionSnapshot(
      schemaVersion: watchSnapshotSchemaVersion,
      sessionId: null,
      programDayName: '',
      startedAtMs: 0,
      unit: unit,
      accentArgb: _argb(accent.accent),
      accentInkArgb: _argb(accent.accentInk),
      cursorExerciseIdx: 0,
      restEndsAtMs: restEndsAtMs,
      restDefaultSeconds: settings.restSeconds,
      barWeightKg: settings.barWeightKg,
      plateInventoryKg: settings.plateInventoryKg,
      queue: const [],
    );
  }

  final queue = <WatchExercise>[
    for (final pe in session.queue)
      WatchExercise(
        programExerciseId: pe.programExerciseId,
        exerciseId: pe.exerciseId,
        name: pe.exerciseName,
        targetSets: pe.targetSets,
        targetRepsMin: pe.targetRepsMin,
        targetRepsMax: pe.targetRepsMax,
        defaultWeightKg: pe.defaultWeightKg,
        weightStepKg: pe.weightStepKg,
        isOverridden: pe.isOverridden,
        skipped: pe.skipped,
        dropCount: pe.dropCount,
        loggedSets: [
          for (final s in session.loggedSets)
            if (s.exerciseId == pe.exerciseId)
              WatchSet(
                id: s.id,
                exerciseId: s.exerciseId,
                reps: s.reps,
                // Weight stays in kg on the wire; each device formats locally.
                weightKg: s.weightKg,
                rir: s.rir,
                loggedAtMs: s.loggedAt.millisecondsSinceEpoch,
                setGroup: s.setGroup,
                groupSeq: s.groupSeq,
              ),
        ],
      ),
  ];

  return WatchSessionSnapshot(
    schemaVersion: watchSnapshotSchemaVersion,
    sessionId: session.sessionId,
    // The active-session domain doesn't carry the day's display name; the
    // watch renders the queue itself, so an empty label is acceptable here.
    programDayName: '',
    startedAtMs: session.startedAt.millisecondsSinceEpoch,
    unit: unit,
    accentArgb: _argb(accent.accent),
    accentInkArgb: _argb(accent.accentInk),
    cursorExerciseIdx: session.cursor.exerciseIdx,
    restEndsAtMs: restEndsAtMs,
    restDefaultSeconds: settings.restSeconds,
    barWeightKg: settings.barWeightKg,
    plateInventoryKg: settings.plateInventoryKg,
    queue: queue,
  );
}

/// Convert a Flutter [Color] to a 32-bit ARGB int (0xAARRGGBB) the watch can
/// reconstruct via shift+mask. Copied from `LiveActivityController._argb` so
/// both bridges pack accents identically and the Swift side decodes one scheme.
int _argb(Color c) {
  int chan(double v) => (v.clamp(0.0, 1.0) * 255).round() & 0xff;
  final a = chan(c.a);
  final r = chan(c.r);
  final g = chan(c.g);
  final b = chan(c.b);
  return (a << 24) | (r << 16) | (g << 8) | b;
}
