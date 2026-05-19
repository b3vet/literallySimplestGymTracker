/// Per-session override of a planned exercise.
///
/// When a lifter swaps "Shoulder Press (Smith)" for "Shoulder Press (Machine)"
/// mid-workout, we persist that decision against the active session only —
/// the program template stays unchanged. On resume, the active-workout
/// controller looks up overrides for the session and replaces the matching
/// queue items.
///
/// `previousExerciseId` is the slot's `exercise_id` immediately before the
/// current override. It powers the "PREVIOUS: N SETS ON [OLD NAME]" affordance
/// on the active workout screen when sets were already logged at this slot
/// before the swap. Nullable so the field can be omitted on synthetic overrides
/// where no prior exercise is meaningful.
class SessionExerciseOverride {
  const SessionExerciseOverride({
    required this.id,
    required this.sessionId,
    required this.programExerciseId,
    required this.exerciseId,
    required this.exerciseName,
    this.previousExerciseId,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    required this.defaultWeightKg,
    this.weightStepKg,
  });

  final String id;
  final String sessionId;
  final String programExerciseId;
  final String exerciseId;

  /// The current exercise's name, joined in at read time so callers don't
  /// have to make a follow-up query. Not stored in the override table.
  final String exerciseName;

  final String? previousExerciseId;
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;
  final double defaultWeightKg;
  final double? weightStepKg;
}
