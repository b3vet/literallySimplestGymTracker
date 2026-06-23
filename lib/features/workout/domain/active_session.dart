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
    this.skipped = false,
    this.position = 0,
    this.isInserted = false,
    this.dropCount = 0,
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

  /// True when this slot was skipped for the session (durable, persisted on the
  /// override). The cursor walks past skipped slots; the program status sheet
  /// renders them struck-through. Never set on the program-side template.
  final bool skipped;

  /// Queue order key. Template slots use their program `position` (0,1,2,…);
  /// inserted slots use a fractional midpoint so they sit between neighbours.
  /// The queue is kept sorted by this; cursor navigation uses list order.
  final double position;

  /// True when this slot was inserted into the session (not from the program
  /// template). Drives the "revert to plan" gate and the resume merge.
  final bool isInserted;

  /// 0 = normal; N ≥ 1 = each working set is a drop set with N drops. Mirrors
  /// the program/override `drop_count` so it survives swaps/edits/inserts.
  final int dropCount;

  /// Whether this slot is a drop-set exercise.
  bool get isDropSet => dropCount > 0;

  factory PlannedExercise.fromView(ProgramExerciseView v) => PlannedExercise(
        programExerciseId: v.pe.id,
        exerciseId: v.pe.exerciseId,
        exerciseName: v.exerciseName,
        targetSets: v.pe.targetSets,
        targetRepsMin: v.pe.targetRepsMin,
        targetRepsMax: v.pe.targetRepsMax,
        defaultWeightKg: v.pe.defaultWeightKg,
        weightStepKg: v.pe.weightStepKg,
        position: v.pe.position.toDouble(),
        dropCount: v.pe.dropCount,
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
    bool? skipped,
    double? position,
    bool? isInserted,
    int? dropCount,
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
        skipped: skipped ?? this.skipped,
        position: position ?? this.position,
        isInserted: isInserted ?? this.isInserted,
        dropCount: dropCount ?? this.dropCount,
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

/// Completed sets for an exercise = number of DISTINCT group keys among its
/// logged rows. Identical to row-count for normal (singleton-group) sets; a
/// drop set (top + drops sharing one group) counts as exactly one.
int completedSetsFor(List<WorkoutSet> logged, String exerciseId) {
  final keys = <String>{};
  for (final s in logged) {
    if (s.exerciseId == exerciseId) keys.add(s.groupKey);
  }
  return keys.length;
}

/// An exercise's logged rows split into back-to-back groups (drop sets), in log
/// order; each group's rows sorted by `groupSeq`. A normal set is a group of
/// one. Used for grouped display.
List<List<WorkoutSet>> groupedSetsFor(
    List<WorkoutSet> logged, String exerciseId) {
  final order = <String>[];
  final byKey = <String, List<WorkoutSet>>{};
  for (final s in logged) {
    if (s.exerciseId != exerciseId) continue;
    final k = s.groupKey;
    final list = byKey[k];
    if (list == null) {
      byKey[k] = [s];
      order.add(k);
    } else {
      list.add(s);
    }
  }
  return [
    for (final k in order)
      byKey[k]!..sort((a, b) => a.groupSeq.compareTo(b.groupSeq)),
  ];
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
