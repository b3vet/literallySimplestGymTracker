import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../main.dart' show databaseProvider;
import '../../programs/application/programs_provider.dart';
import '../../programs/data/program_dao.dart';
import '../data/workout_dao.dart';
import '../domain/active_session.dart';
import '../domain/workout_set.dart';
import 'live_activity_controller.dart';
import 'pr_detector.dart';
import 'rest_timer_controller.dart';

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

  void _pushLiveActivity(ActiveSession session) {
    if (!_liveActivityEnabled) return;
    _liveActivity.update(
      session: session,
      unit: _unit,
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
    final queue = planned.map(PlannedExercise.fromView).toList();
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
