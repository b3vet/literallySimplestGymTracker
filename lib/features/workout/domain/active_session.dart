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
    this.weightStepKg,
    this.isOverridden = false,
    this.previousExerciseId,
  });
  final String programExerciseId;
  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;
  final double defaultWeightKg;

  /// Per-exercise weight step in **kg**. NULL → caller falls back to the
  /// unit's default step.
  final double? weightStepKg;

  /// True when this slot has been substituted mid-workout via the
  /// active-workout edit sheet. Drives the "SUBSTITUTED" badge in the UI.
  /// Never set on the program-side `ProgramExercise` — purely a session
  /// concern.
  final bool isOverridden;

  /// The slot's previous exerciseId immediately before the current override.
  /// Used by the UI to render "PREVIOUS: N SETS ON [OLD NAME]" when sets
  /// were logged at this slot before the swap. Null when [isOverridden] is
  /// false.
  final String? previousExerciseId;

  factory PlannedExercise.fromView(ProgramExerciseView v) => PlannedExercise(
        programExerciseId: v.pe.id,
        exerciseId: v.pe.exerciseId,
        exerciseName: v.exerciseName,
        targetSets: v.pe.targetSets,
        targetRepsMin: v.pe.targetRepsMin,
        targetRepsMax: v.pe.targetRepsMax,
        defaultWeightKg: v.pe.defaultWeightKg,
        weightStepKg: v.pe.weightStepKg,
      );

  PlannedExercise copyWith({
    String? exerciseId,
    String? exerciseName,
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    double? defaultWeightKg,
    // Use `Object?` sentinel to distinguish "skip" from "explicit null".
    Object? weightStepKg = _unset,
    bool? isOverridden,
    Object? previousExerciseId = _unset,
  }) =>
      PlannedExercise(
        programExerciseId: programExerciseId,
        exerciseId: exerciseId ?? this.exerciseId,
        exerciseName: exerciseName ?? this.exerciseName,
        targetSets: targetSets ?? this.targetSets,
        targetRepsMin: targetRepsMin ?? this.targetRepsMin,
        targetRepsMax: targetRepsMax ?? this.targetRepsMax,
        defaultWeightKg: defaultWeightKg ?? this.defaultWeightKg,
        weightStepKg: identical(weightStepKg, _unset)
            ? this.weightStepKg
            : weightStepKg as double?,
        isOverridden: isOverridden ?? this.isOverridden,
        previousExerciseId: identical(previousExerciseId, _unset)
            ? this.previousExerciseId
            : previousExerciseId as String?,
      );
}

const Object _unset = Object();

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
