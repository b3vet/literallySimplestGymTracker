import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_activities/live_activities.dart';

import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../domain/active_session.dart';
import 'workout_progress.dart';

/// App Group identifier shared between the Runner app and the Widget
/// Extension. Must match the Group ID configured in Xcode for both targets.
const liveActivityAppGroup = 'group.com.berkeucvet.lsWorkoutTracker';

class LiveActivityController {
  LiveActivityController();

  final LiveActivities _plugin = LiveActivities();
  bool _initialized = false;
  String? _activityId;

  // Plugin methods are async on both sides; back-to-back update() calls land
  // as two concurrent Swift Tasks that race writing to the shared
  // UserDefaults bag (last-writer-wins). Chain everything through a
  // single-slot queue so updates are observed in the order they were issued.
  Future<void> _queue = Future<void>.value();
  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task()).catchError((_) {});
    _queue = next;
    return next;
  }

  bool get _supported => !kIsWeb && Platform.isIOS;

  Future<void> _ensureInit() async {
    if (_initialized || !_supported) return;
    try {
      await _plugin.init(appGroupId: liveActivityAppGroup);
      final supported = await _plugin.areActivitiesSupported();
      final enabled = await _plugin.areActivitiesEnabled();
      debugPrint(
          '[LiveActivity] init OK — supported=$supported enabled=$enabled '
          'appGroup=$liveActivityAppGroup');
      _initialized = true;
    } catch (e, st) {
      debugPrint('[LiveActivity] init FAILED: $e\n$st');
      _initialized = false;
    }
  }

  /// Start a new activity for the current workout. Safe to call repeatedly;
  /// subsequent calls overwrite any prior activity. If the session has no
  /// active exercise (everything already done) we just end any stale
  /// activity instead of creating a new one.
  Future<void> start({
    required ActiveSession session,
    required WeightUnit unit,
    required LsAccentSpec accent,
    DateTime? restEndsAt,
  }) {
    return _enqueue(() async {
      if (!_supported) return;
      await _ensureInit();
      if (!_initialized) return;
      try {
        await _endLocked();
        final progress = WorkoutProgress.from(session);
        if (progress.allDone) {
          debugPrint(
              '[LiveActivity] start: session already done, not creating');
          return;
        }
        final state = _stateFromProgress(progress,
            unit: unit, accent: accent, restEndsAt: restEndsAt);
        // iOSEnableRemoteUpdates=false: we drive updates from the app
        // itself. Setting it to true (default) makes the plugin call
        // Activity.request(pushType: .token), which requires the Push
        // Notifications entitlement on Runner and fails with
        // ActivityInput error 0 if it isn't configured.
        final id = await _plugin.createActivity(
          session.sessionId,
          state,
          iOSEnableRemoteUpdates: false,
        );
        _activityId = id ?? session.sessionId;
        debugPrint(
            '[LiveActivity] createActivity returned id=$id (using=$_activityId)');
      } catch (e, st) {
        debugPrint('[LiveActivity] createActivity FAILED: $e\n$st');
        _activityId = null;
      }
    });
  }

  /// Push a new content state derived from the workout's PROGRESS — i.e.
  /// the first exercise in the queue that still has unfinished target sets.
  /// Independent of the in-app cursor: where the user is currently looking
  /// in the UI doesn't change what the lock screen shows. When the whole
  /// session is done, the activity is ended (the workout-complete UI lives
  /// in the app itself).
  Future<void> update({
    required ActiveSession session,
    required WeightUnit unit,
    required LsAccentSpec accent,
    DateTime? restEndsAt,
  }) {
    return _enqueue(() async {
      if (!_supported) return;
      await _ensureInit();
      if (!_initialized) return;
      final progress = WorkoutProgress.from(session);
      if (progress.allDone) {
        await _endLocked();
        return;
      }
      try {
        final state = _stateFromProgress(progress,
            unit: unit, accent: accent, restEndsAt: restEndsAt);
        if (_activityId == null) {
          final id = await _plugin.createOrUpdateActivity(
            session.sessionId,
            state,
            iOSEnableRemoteUpdates: false,
          );
          _activityId = id ?? session.sessionId;
          debugPrint(
              '[LiveActivity] createOrUpdate id=$id (using=$_activityId)');
        } else {
          await _plugin.updateActivity(_activityId!, state);
        }
      } catch (e, st) {
        debugPrint('[LiveActivity] update FAILED: $e\n$st');
      }
    });
  }

  Future<void> end() => _enqueue(() => _endLocked());

  Future<void> _endLocked() async {
    if (!_supported) return;
    if (_activityId == null) return;
    try {
      await _plugin.endActivity(_activityId!);
      debugPrint('[LiveActivity] endActivity OK id=$_activityId');
    } catch (e) {
      debugPrint('[LiveActivity] endActivity FAILED: $e');
    }
    _activityId = null;
  }

  Map<String, dynamic> _stateFromProgress(
    WorkoutProgress p, {
    required WeightUnit unit,
    required LsAccentSpec accent,
    DateTime? restEndsAt,
  }) {
    final pe = p.exercise!;
    final sets = p.setsForActive;
    final lastSet = sets.isEmpty ? null : sets.last;

    final setLines = <String>[
      for (final s in sets)
        '${WeightConv.format(s.weightKg, unit)} × ${s.reps}'
            '${s.rir > 0 ? '  RIR ${s.rir}' : ''}',
    ];

    return <String, dynamic>{
      'exerciseName': pe.exerciseName,
      'exerciseIndex': p.activeIndex + 1,
      'totalExercises': p.totalExercises,
      'setIndex': sets.length + 1,
      'targetSets': pe.targetSets,
      'targetRepsMin': pe.targetRepsMin,
      'targetRepsMax': pe.targetRepsMax,
      'targetWeightLabel': WeightConv.format(pe.defaultWeightKg, unit),
      'lastWeightLabel':
          lastSet == null ? '' : WeightConv.format(lastSet.weightKg, unit),
      'lastReps': lastSet?.reps ?? 0,
      'setLines': setLines,
      // 0 means "no active rest"; Swift renders Date(timeIntervalSince1970:).
      'restEndsAtSec': restEndsAt == null
          ? 0
          : restEndsAt.millisecondsSinceEpoch ~/ 1000,
      'isFinished': false,
      // Accent forwarded as ARGB int (0xAARRGGBB) so the Swift side can
      // decode without colorspace mismatches. The widget reads it from the
      // shared UserDefaults and falls back to a built-in default if absent.
      'accentArgb': _argb(accent.accent),
      'accentInkArgb': _argb(accent.accentInk),
    };
  }

  /// Convert a Flutter [Color] to a 32-bit ARGB int the widget extension can
  /// reconstruct via shift+mask. Flutter 3.27 deprecates `.value` in favour of
  /// the per-channel accessors; this preserves the same semantics without
  /// reaching for the deprecated property.
  int _argb(Color c) {
    int chan(double v) => (v.clamp(0.0, 1.0) * 255).round() & 0xff;
    final a = chan(c.a);
    final r = chan(c.r);
    final g = chan(c.g);
    final b = chan(c.b);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }
}

final liveActivityControllerProvider = Provider<LiveActivityController>((ref) {
  final controller = LiveActivityController();
  ref.onDispose(controller.end);
  return controller;
});
