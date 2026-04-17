import '../../programs/domain/program_exercise.dart';
import 'workout_set.dart';

class PlannedExercise {
  const PlannedExercise({
    required this.programExerciseId,
    required this.exerciseId,
    required this.exerciseName,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    required this.defaultWeightKg,
  });
  final String programExerciseId;
  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;
  final double defaultWeightKg;

  factory PlannedExercise.fromView(ProgramExerciseView v) => PlannedExercise(
        programExerciseId: v.pe.id,
        exerciseId: v.pe.exerciseId,
        exerciseName: v.exerciseName,
        targetSets: v.pe.targetSets,
        targetRepsMin: v.pe.targetRepsMin,
        targetRepsMax: v.pe.targetRepsMax,
        defaultWeightKg: v.pe.defaultWeightKg,
      );
}

class ActiveSession {
  const ActiveSession({
    required this.sessionId,
    required this.programDayId,
    required this.startedAt,
    required this.queue,
    required this.cursor,
    required this.loggedSets,
  });
  final String sessionId;
  final String programDayId;
  final DateTime startedAt;
  final List<PlannedExercise> queue;
  final Cursor cursor;
  final List<WorkoutSet> loggedSets;

  PlannedExercise? get currentExercise =>
      cursor.exerciseIdx < queue.length ? queue[cursor.exerciseIdx] : null;

  bool get isFinished => cursor.exerciseIdx >= queue.length;

  ActiveSession copyWith({
    List<PlannedExercise>? queue,
    Cursor? cursor,
    List<WorkoutSet>? loggedSets,
  }) =>
      ActiveSession(
        sessionId: sessionId,
        programDayId: programDayId,
        startedAt: startedAt,
        queue: queue ?? this.queue,
        cursor: cursor ?? this.cursor,
        loggedSets: loggedSets ?? this.loggedSets,
      );
}

class Cursor {
  const Cursor({required this.exerciseIdx, required this.setIdx});
  final int exerciseIdx;
  final int setIdx;

  Cursor copyWith({int? exerciseIdx, int? setIdx}) => Cursor(
        exerciseIdx: exerciseIdx ?? this.exerciseIdx,
        setIdx: setIdx ?? this.setIdx,
      );
}
