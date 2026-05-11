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
class WorkoutProgress {
  WorkoutProgress._({
    required this.totalExercises,
    required this.activeIndex,
    required this.exercise,
    required this.setsForActive,
  });

  final int totalExercises;
  final int activeIndex;
  final PlannedExercise? exercise;
  final List<WorkoutSet> setsForActive;

  bool get allDone => exercise == null;

  factory WorkoutProgress.from(ActiveSession s) {
    int? lastPartial;
    int? firstZero;
    final perExerciseSets = <int, List<WorkoutSet>>{};

    for (var i = 0; i < s.queue.length; i++) {
      final pe = s.queue[i];
      final sets = s.loggedSets
          .where((x) => x.exerciseId == pe.exerciseId)
          .toList(growable: false);
      perExerciseSets[i] = sets;
      if (sets.isEmpty) {
        firstZero ??= i;
      } else if (sets.length < pe.targetSets) {
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
      );
    }
    return WorkoutProgress._(
      totalExercises: s.queue.length,
      activeIndex: pickedIdx,
      exercise: s.queue[pickedIdx],
      setsForActive: perExerciseSets[pickedIdx]!,
    );
  }
}
