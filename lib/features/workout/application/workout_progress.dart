import '../domain/active_session.dart';
import '../domain/workout_set.dart';

/// Computed "where am I in the workout?" view.
///
/// We can't tell whether a 0/N exercise that comes BEFORE the user's
/// current work was intentionally skipped or just forgotten, so the rule is:
///
///   1. If any exercise has a partial log (`0 < logged < target`), pick the
///      LAST such exercise — that's almost certainly where the user is
///      actively working.
///   2. Otherwise, pick the FIRST exercise with zero logged sets — that's
///      the next thing to start.
///   3. If neither exists, every exercise is complete → `allDone`.
///
/// Skipped exercises are excluded from this search entirely — they're out of
/// the session, so the Live Activity / progress view never rests on one.
class WorkoutProgress {
  WorkoutProgress._({
    required this.totalExercises,
    required this.activeIndex,
    required this.exercise,
    required this.setsForActive,
    required this.completedSets,
  });

  final int totalExercises;
  final int activeIndex;
  final PlannedExercise? exercise;
  final List<WorkoutSet> setsForActive;

  /// Distinct completed groups (= logical sets done) for the active exercise —
  /// a drop set's top+drops count as one. Use this for "set N of M", not
  /// `setsForActive.length` (which is raw rows).
  final int completedSets;

  bool get allDone => exercise == null;

  factory WorkoutProgress.from(ActiveSession s) {
    int? lastPartial;
    int? firstZero;
    final perExerciseSets = <int, List<WorkoutSet>>{};
    final perExerciseGroups = <int, int>{};

    for (var i = 0; i < s.queue.length; i++) {
      final pe = s.queue[i];
      if (pe.skipped) continue; // skipped slots are out of the session
      final sets = s.loggedSets
          .where((x) => x.exerciseId == pe.exerciseId)
          .toList(growable: false);
      perExerciseSets[i] = sets;
      final groups = completedSetsFor(s.loggedSets, pe.exerciseId);
      perExerciseGroups[i] = groups;
      if (groups == 0) {
        firstZero ??= i;
      } else if (groups < pe.targetSets) {
        lastPartial = i; // overwrite so we end up with the LAST partial
      }
    }

    final pickedIdx = lastPartial ?? firstZero;
    if (pickedIdx == null) {
      return WorkoutProgress._(
        totalExercises: s.queue.length,
        activeIndex: s.queue.length,
        exercise: null,
        setsForActive: const [],
        completedSets: 0,
      );
    }
    return WorkoutProgress._(
      totalExercises: s.queue.length,
      activeIndex: pickedIdx,
      exercise: s.queue[pickedIdx],
      setsForActive: perExerciseSets[pickedIdx]!,
      completedSets: perExerciseGroups[pickedIdx]!,
    );
  }
}
