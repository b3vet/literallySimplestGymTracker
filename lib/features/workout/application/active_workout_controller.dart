import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../main.dart' show databaseProvider;
import '../../programs/application/programs_provider.dart';
import '../../programs/data/program_dao.dart';
import '../../programs/domain/program_exercise.dart';
import '../data/workout_dao.dart';
import '../domain/active_session.dart';
import '../domain/session_exercise_override.dart';
import '../domain/workout_set.dart';
import 'live_activity_controller.dart';
import 'pr_detector.dart';
import 'rest_timer_controller.dart';
import 'watch_bridge.g.dart';

final workoutDaoProvider = Provider<WorkoutDao>((ref) {
  return WorkoutDao(ref.watch(databaseProvider));
});

final prDetectorProvider = Provider((ref) {
  return PrDetector(ref.watch(workoutDaoProvider));
});

final sessionPrsProvider =
    FutureProvider.family<Map<String, ExercisePR>, String>(
        (ref, sessionId) async {
  return ref.watch(prDetectorProvider).detect(sessionId);
});

final activeSessionProvider =
    AsyncNotifierProvider<ActiveWorkoutController, ActiveSession?>(
  ActiveWorkoutController.new,
);

/// Last weight (in kg) logged for an exercise — used as SetLogSheet default.
final lastWeightForExerciseProvider =
    FutureProvider.family<double?, String>((ref, exerciseId) async {
  final last = await ref.read(workoutDaoProvider).lastSetForExercise(exerciseId);
  return last?.weightKg;
});

/// Display name for an exerciseId. Watched by the active workout screen to
/// render the "PREVIOUS: N SETS ON [OLD NAME]" affordance for slots that
/// have been substituted mid-session.
final exerciseNameProvider =
    FutureProvider.family<String?, String>((ref, exerciseId) async {
  final e = await ref.read(programDaoProvider).findExercise(exerciseId);
  return e?.name;
});

class ActiveWorkoutController extends AsyncNotifier<ActiveSession?> {
  WorkoutDao get _workoutDao => ref.read(workoutDaoProvider);
  ProgramDao get _programDao => ref.read(programDaoProvider);
  LiveActivityController get _liveActivity =>
      ref.read(liveActivityControllerProvider);
  bool get _liveActivityEnabled =>
      ref.read(settingsProvider).liveActivityEnabled;

  @override
  Future<ActiveSession?> build() async {
    return _resumeIfPossible();
  }

  DateTime? _currentRestEndsAt() {
    final rt = ref.read(restTimerProvider);
    return rt.endsAt != null && rt.endsAt!.isAfter(DateTime.now())
        ? rt.endsAt
        : null;
  }

  WeightUnit get _unit =>
      ref.read(settingsProvider).unit ?? WeightUnit.kg;

  LsAccentSpec get _accent =>
      lsAccentSpec(ref.read(settingsProvider).accent);

  void _pushLiveActivity(ActiveSession session) {
    if (!_liveActivityEnabled) return;
    _liveActivity.update(
      session: session,
      unit: _unit,
      accent: _accent,
      restEndsAt: _currentRestEndsAt(),
    );
  }

  Future<ActiveSession?> _resumeIfPossible() async {
    final session = await _workoutDao.findActiveSession();
    if (session == null || session.programDayId == null) return null;

    final planned = await _programDao.listProgramExercises(session.programDayId!);
    if (planned.isEmpty) {
      // Nothing to do — abandon.
      await _workoutDao.abandonSession(session.id);
      return null;
    }
    final overrides = await _workoutDao.overridesForSession(session.id);
    final queue = _applyOverrides(planned, overrides);
    final loggedSets = await _workoutDao.setsForSession(session.id);
    final cursor = _cursorAfter(queue, loggedSets);
    final resumed = ActiveSession(
      sessionId: session.id,
      programDayId: session.programDayId!,
      startedAt: session.startedAt,
      queue: queue,
      cursor: cursor,
      loggedSets: loggedSets,
    );
    if (_liveActivityEnabled) {
      _liveActivity.start(
        session: resumed,
        unit: _unit,
        accent: _accent,
        restEndsAt: _currentRestEndsAt(),
      );
    }
    return resumed;
  }

  /// Given a queue and the sets already logged, return the cursor pointing at the next unlogged set.
  Cursor _cursorAfter(
      List<PlannedExercise> queue, List<WorkoutSet> loggedSets) {
    final countsPerExercise = <String, int>{};
    for (final s in loggedSets) {
      countsPerExercise.update(s.exerciseId, (v) => v + 1, ifAbsent: () => 1);
    }
    for (var i = 0; i < queue.length; i++) {
      final pe = queue[i];
      final logged = countsPerExercise[pe.exerciseId] ?? 0;
      if (logged < pe.targetSets) {
        return Cursor(exerciseIdx: i, setIdx: logged);
      }
    }
    return Cursor(exerciseIdx: queue.length, setIdx: 0);
  }

  /// Start a new session for the given program day. Fails if there's already an active session.
  Future<void> start(String programDayId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final existing = await _workoutDao.findActiveSession();
      if (existing != null) {
        throw StateError('A workout is already in progress.');
      }
      final planned = await _programDao.listProgramExercises(programDayId);
      if (planned.isEmpty) {
        throw StateError('This day has no exercises.');
      }
      final session = await _workoutDao.startSession(programDayId);
      final created = ActiveSession(
        sessionId: session.id,
        programDayId: programDayId,
        startedAt: session.startedAt,
        queue: planned.map(PlannedExercise.fromView).toList(),
        cursor: const Cursor(exerciseIdx: 0, setIdx: 0),
        loggedSets: const [],
      );
      if (_liveActivityEnabled) {
        await _liveActivity.start(
          session: created,
          unit: _unit,
          accent: _accent,
          restEndsAt: _currentRestEndsAt(),
        );
      }
      return created;
    });
  }

  Future<WorkoutSet?> logSet({
    required int reps,
    required double weightKg,
    required int rir,
  }) async {
    final current = state.value;
    if (current == null || current.isFinished) return null;
    final pe = current.currentExercise!;
    final newSet = await _workoutDao.insertSet(
      sessionId: current.sessionId,
      exerciseId: pe.exerciseId,
      setIndex: current.loggedSets.length,
      reps: reps,
      weightKg: weightKg,
      rir: rir,
    );

    final newLoggedSets = [...current.loggedSets, newSet];

    // Auto-advance only forward: if this set completes the target sets for
    // the current exercise, move the cursor to the next position. Never
    // rewind, so back-navigated edits don't drag the user away from where
    // they actually are.
    final setsForCurrent =
        newLoggedSets.where((s) => s.exerciseId == pe.exerciseId).length;
    final shouldAdvance = setsForCurrent >= pe.targetSets;
    final nextCursor = shouldAdvance
        ? Cursor(exerciseIdx: current.cursor.exerciseIdx + 1, setIdx: 0)
        : current.cursor;

    final updated = current.copyWith(
      loggedSets: newLoggedSets,
      cursor: nextCursor,
    );
    state = AsyncValue.data(updated);
    _pushLiveActivity(updated);
    return newSet;
  }

  /// Apply a set logged on the watch (SOW §6). The set log is append-only and
  /// keyed by [WatchSet.id]: if a set with this id already exists in
  /// [loggedSets] this is a no-op (idempotent — the watch may re-deliver or we
  /// may have already echoed it back), otherwise it's persisted under the
  /// watch-authored id and the cursor advances using the SAME rule as [logSet].
  ///
  /// Like [logSet], the set is attributed to the current exercise. Inbound
  /// apply only — it must not re-push a mutation back to the watch.
  Future<void> applyWatchLogSet(WatchSet set) async {
    final current = state.value;
    if (current == null || current.isFinished) return;
    // Idempotency: dedupe by id, never double-add the same set.
    if (current.loggedSets.any((s) => s.id == set.id)) return;
    final pe = current.currentExercise!;
    final newSet = await _workoutDao.insertSet(
      id: set.id,
      sessionId: current.sessionId,
      exerciseId: pe.exerciseId,
      setIndex: current.loggedSets.length,
      reps: set.reps,
      weightKg: set.weightKg,
      rir: set.rir,
    );

    final newLoggedSets = [...current.loggedSets, newSet];

    // Same auto-advance rule as logSet: advance only forward when the current
    // exercise's target sets are complete.
    final setsForCurrent =
        newLoggedSets.where((s) => s.exerciseId == pe.exerciseId).length;
    final shouldAdvance = setsForCurrent >= pe.targetSets;
    final nextCursor = shouldAdvance
        ? Cursor(exerciseIdx: current.cursor.exerciseIdx + 1, setIdx: 0)
        : current.cursor;

    final updated = current.copyWith(
      loggedSets: newLoggedSets,
      cursor: nextCursor,
    );
    state = AsyncValue.data(updated);
    _pushLiveActivity(updated);
  }

  Future<void> editSet(WorkoutSet updated) async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.updateSet(updated);
    final updatedSets = [
      for (final s in current.loggedSets)
        if (s.id == updated.id) updated else s,
    ];
    final next = current.copyWith(loggedSets: updatedSets);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  Future<void> deleteSet(String setId) async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.deleteSet(setId);
    final updatedSets =
        current.loggedSets.where((s) => s.id != setId).toList();
    final next = current.copyWith(loggedSets: updatedSets);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Move the cursor to a specific exercise. Out-of-range values are clamped
  /// to a valid index (or to `queue.length` when [idx] is `>= queue.length`,
  /// which represents the "all exercises done" state).
  /// Cursor moves don't push to the Live Activity — the lock screen tracks
  /// the workout's actual progress, not what the user is looking at.
  Future<void> goToExerciseIndex(int idx) async {
    final current = state.value;
    if (current == null) return;
    final clamped = idx < 0
        ? 0
        : (idx > current.queue.length ? current.queue.length : idx);
    final next = current.copyWith(
      cursor: Cursor(exerciseIdx: clamped, setIdx: 0),
    );
    state = AsyncValue.data(next);
  }

  Future<void> goPrev() async {
    final current = state.value;
    if (current == null) return;
    return goToExerciseIndex(current.cursor.exerciseIdx - 1);
  }

  Future<void> goNext() async {
    final current = state.value;
    if (current == null) return;
    return goToExerciseIndex(current.cursor.exerciseIdx + 1);
  }

  /// Skip past the current exercise even if remaining sets aren't logged.
  /// Equivalent to [goNext] — kept under this name for callers expressing
  /// intent.
  Future<void> skipCurrentExercise() => goNext();

  /// Apply session-scoped overrides to the planned queue.
  ///
  /// The program template is fixed once a workout starts, but a lifter can
  /// swap any slot mid-session (smith machine occupied → switch to the
  /// plate-loaded variant). Each override targets one [PlannedExercise] by
  /// its `programExerciseId`. Unaffected slots are returned unchanged.
  List<PlannedExercise> _applyOverrides(
    List<ProgramExerciseView> planned,
    List<SessionExerciseOverride> overrides,
  ) {
    if (overrides.isEmpty) {
      return planned.map(PlannedExercise.fromView).toList();
    }
    final byPeId = {for (final o in overrides) o.programExerciseId: o};
    return planned.map((v) {
      final base = PlannedExercise.fromView(v);
      final o = byPeId[v.pe.id];
      if (o == null) return base;
      return base.copyWith(
        exerciseId: o.exerciseId,
        exerciseName: o.exerciseName,
        targetSets: o.targetSets,
        targetRepsMin: o.targetRepsMin,
        targetRepsMax: o.targetRepsMax,
        defaultWeightKg: o.defaultWeightKg,
        weightStepKg: o.weightStepKg,
        isOverridden: true,
        previousExerciseId: o.previousExerciseId,
      );
    }).toList();
  }

  /// Substitute one queue slot with a different exercise for this session
  /// only. The program template is never modified. Logged sets prior to
  /// the swap retain their original `exercise_id` — they show up under the
  /// old exercise in the summary, which is honest history.
  ///
  /// The cursor stays at the same queue index; the new exercise's set
  /// count starts from zero (the cursor-advance logic already keys on
  /// `pe.exerciseId`).
  Future<void> substituteExercise({
    required int queueIdx,
    required String exerciseName,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required double defaultWeightKg,
    double? weightStepKg,
  }) async {
    final current = state.value;
    if (current == null) return;
    if (queueIdx < 0 || queueIdx >= current.queue.length) return;
    final slot = current.queue[queueIdx];
    final exercise = await _programDao.findOrCreateExercise(exerciseName);
    await _workoutDao.upsertOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
      exerciseId: exercise.id,
      // Preserve the slot's pre-swap exerciseId so the UI can surface a
      // "PREVIOUS: N SETS ON [OLD NAME]" affordance for any sets the user
      // already logged at this slot.
      previousExerciseId: slot.exerciseId,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
      weightStepKg: weightStepKg,
    );
    final replaced = slot.copyWith(
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
      weightStepKg: weightStepKg,
      isOverridden: true,
      previousExerciseId: slot.exerciseId,
    );
    final newQueue = [...current.queue]..[queueIdx] = replaced;
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Remove the session override on a slot and restore the planned exercise.
  /// Logged sets under the substitute are left in the database — they
  /// remain visible in the summary and contribute to that substitute
  /// exercise's history. Reverting only affects the queue going forward.
  Future<void> revertSubstitution(int queueIdx) async {
    final current = state.value;
    if (current == null) return;
    if (queueIdx < 0 || queueIdx >= current.queue.length) return;
    final slot = current.queue[queueIdx];
    if (!slot.isOverridden) return;
    await _workoutDao.deleteOverride(
      sessionId: current.sessionId,
      programExerciseId: slot.programExerciseId,
    );
    // Rebuild this single queue item from the planned program. We refetch
    // all planned exercises for the day and pick the one matching this
    // slot's programExerciseId — cheap on a typical workout day.
    final planned =
        await _programDao.listProgramExercises(current.programDayId);
    final original = planned.firstWhere(
      (v) => v.pe.id == slot.programExerciseId,
      orElse: () => throw StateError(
          'Cannot revert: program exercise no longer exists.'),
    );
    final restored = PlannedExercise.fromView(original);
    final newQueue = [...current.queue]..[queueIdx] = restored;
    final next = current.copyWith(queue: newQueue);
    state = AsyncValue.data(next);
    _pushLiveActivity(next);
  }

  /// Finish the session (completed). Returns the session ID for navigation.
  Future<String?> finish() async {
    final current = state.value;
    if (current == null) return null;
    await _workoutDao.completeSession(current.sessionId);
    state = const AsyncValue.data(null);
    await _liveActivity.end();
    return current.sessionId;
  }

  Future<void> abandon() async {
    final current = state.value;
    if (current == null) return;
    await _workoutDao.abandonSession(current.sessionId);
    state = const AsyncValue.data(null);
    await _liveActivity.end();
  }
}
