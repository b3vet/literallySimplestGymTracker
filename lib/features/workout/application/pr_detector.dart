import 'dart:math';

import '../data/workout_dao.dart';
import '../domain/workout_set.dart';

enum PrKind { none, weight, reps }

class ExercisePR {
  const ExercisePR({
    required this.exerciseId,
    required this.kind,
    required this.weightKg,
    required this.reps,
  });
  final String exerciseId;
  final PrKind kind;
  final double weightKg;
  final int reps;

  bool get isPr => kind != PrKind.none;
}

class PrDetector {
  PrDetector(this._dao);
  final WorkoutDao _dao;

  /// Analyse a completed session and return PR info per exercise.
  /// PRs are compared against all sets logged strictly before [session.startedAt].
  Future<Map<String, ExercisePR>> detect(String sessionId) async {
    final session = await _dao.findSession(sessionId);
    if (session == null) return {};
    final sets = await _dao.setsForSession(sessionId);
    final byExercise = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    final out = <String, ExercisePR>{};
    for (final entry in byExercise.entries) {
      final exerciseId = entry.key;
      final list = entry.value;
      final topWeight = list.map((s) => s.weightKg).reduce(max);
      final topSetsAtWeight =
          list.where((s) => s.weightKg == topWeight).toList();
      final topReps = topSetsAtWeight.map((s) => s.reps).reduce(max);

      final historicalMaxWeight = await _dao.historicalMaxWeight(
        exerciseId,
        before: session.startedAt,
      );
      final historicalRepsAtWeight = await _dao.historicalMaxRepsAtWeight(
        exerciseId,
        weightKg: topWeight,
        before: session.startedAt,
      );

      PrKind kind;
      if (historicalMaxWeight == null || topWeight > historicalMaxWeight) {
        kind = PrKind.weight;
      } else if (historicalRepsAtWeight == null ||
          topReps > historicalRepsAtWeight) {
        kind = PrKind.reps;
      } else {
        kind = PrKind.none;
      }

      out[exerciseId] = ExercisePR(
        exerciseId: exerciseId,
        kind: kind,
        weightKg: topWeight,
        reps: topReps,
      );
    }
    return out;
  }
}
