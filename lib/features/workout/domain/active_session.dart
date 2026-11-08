import '../../programs/domain/program_exercise.dart';
import '../../programs/domain/program_exercise_variant.dart';
import 'workout_set.dart';

/// One exercise a slot can run as (SOW-14): its base, or one of its variants.
/// Each carries its OWN target weight + step; sets/reps/drops are the slot's.
class SlotVariant {
  const SlotVariant({
    this.variantId,
    required this.exerciseId,
    required this.name,
    required this.defaultWeightKg,
    this.weightStepKg,
  });

  /// `program_exercise_variants.id`; null for the slot's base exercise.
  final String? variantId;
  final String exerciseId;
  final String name;
  final double defaultWeightKg;

  /// kg; null → the slot's step.
  final double? weightStepKg;

  bool get isBase => variantId == null;

  factory SlotVariant.fromView(ProgramExerciseVariantView v) => SlotVariant(
        variantId: v.variant.id,
        exerciseId: v.variant.exerciseId,
        name: v.exerciseName,
        defaultWeightKg: v.variant.defaultWeightKg,
        weightStepKg: v.variant.weightStepKg,
      );
}

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
    this.baseExerciseId,
    this.baseExerciseName,
    this.baseDefaultWeightKg,
    this.baseWeightStepKg,
    this.variants = const [],
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

  /// The program slot's own (base) exercise and its planned weight/step, kept
  /// verbatim while [exerciseId] follows swaps and variant switches (SOW-14).
  /// Null on slots built without a template row (inserted exercises, tests).
  final String? baseExerciseId;
  final String? baseExerciseName;
  final double? baseDefaultWeightKg;
  final double? baseWeightStepKg;

  /// The slot's variants in program order (empty for most slots). Loaded at
  /// start/resume; edits made mid-workout apply from the next start/resume.
  final List<SlotVariant> variants;

  /// Whether this slot is a drop-set exercise.
  bool get isDropSet => dropCount > 0;

  /// True when the in-workout menu should offer "Switch variant".
  bool get hasVariants =>
      variants.isNotEmpty && !isInserted && baseExerciseId != null;

  /// Base first, then the variants. Empty when [hasVariants] is false. Each
  /// exercise appears once: a variant repeating the base (or an earlier
  /// variant) is dropped — the base wins — so the picker never shows a dead
  /// duplicate row (the DAO's read guard already hides these; belt and braces).
  List<SlotVariant> get members {
    if (!hasVariants) return const [];
    final seen = <String>{baseExerciseId!};
    return [
      SlotVariant(
        exerciseId: baseExerciseId!,
        name: baseExerciseName ?? exerciseName,
        defaultWeightKg: baseDefaultWeightKg ?? defaultWeightKg,
        weightStepKg: baseWeightStepKg,
      ),
      for (final v in variants)
        if (seen.add(v.exerciseId)) v,
    ];
  }

  /// True when every target set of the exercise the slot runs as now is
  /// logged — the same test the cursor uses ([completedSetsFor]).
  bool isCompleteIn(List<WorkoutSet> logged) =>
      completedSetsFor(logged, exerciseId) >= targetSets;

  /// The member currently running, or null (no variants, or swapped to an
  /// exercise outside the slot with "Change exercise").
  SlotVariant? get activeMember {
    for (final m in members) {
      if (m.exerciseId == exerciseId) return m;
    }
    return null;
  }

  factory PlannedExercise.fromView(
    ProgramExerciseView v, {
    List<ProgramExerciseVariantView> variants = const [],
  }) =>
      PlannedExercise(
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
        baseExerciseId: v.pe.exerciseId,
        baseExerciseName: v.exerciseName,
        baseDefaultWeightKg: v.pe.defaultWeightKg,
        baseWeightStepKg: v.pe.weightStepKg,
        variants: [for (final x in variants) SlotVariant.fromView(x)],
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
        baseExerciseId: baseExerciseId,
        baseExerciseName: baseExerciseName,
        baseDefaultWeightKg: baseDefaultWeightKg,
        baseWeightStepKg: baseWeightStepKg,
        variants: variants,
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
