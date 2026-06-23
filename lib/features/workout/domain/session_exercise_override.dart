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
    this.skipped = false,
    this.inserted = false,
    this.orderPos,
    this.dropCount = 0,
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

  /// True when the lifter skipped this exercise for this session. Durable so it
  /// survives resume/watch-resync: the cursor walks past skipped slots and the
  /// program status sheet renders them struck-through. Permanent in v1 — there
  /// is no un-skip affordance. Logged sets (if any) are retained as history.
  final bool skipped;

  /// True when this row is a session-only INSERTED exercise rather than an
  /// override of a template slot. Inserted rows have a synthetic
  /// [programExerciseId] that matches no template exercise.
  final bool inserted;

  /// Queue order key for an inserted exercise (a midpoint between the integer
  /// `position`s of neighbouring template slots). Null for template overrides,
  /// which inherit their slot's template position.
  final double? orderPos;

  /// Drop-set config carried on the override so a mid-session swap/edit/insert
  /// keeps it. 0 = normal; N ≥ 1 = drops after the top.
  final int dropCount;
}
