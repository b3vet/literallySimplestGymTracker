import 'program_exercise.dart';

/// One variant of a program slot (SOW-14): an alternative exercise for the same
/// slot — e.g. "Shoulder Press (Machine)" for a "Shoulder Press" slot — with
/// its OWN prescription: target weight and weight step, and (DB v8, DEC-0007
/// #13) target sets, rep range and drop count. Each of those may be NULL,
/// meaning "inherit from the slot" — what every variant written by 1.5.0 (13)
/// has; the editor saves explicit values. PRs, Stats and targets are tracked
/// per variant (DEC-0007 H1).
class ProgramExerciseVariant {
  const ProgramExerciseVariant({
    required this.id,
    required this.programExerciseId,
    required this.exerciseId,
    required this.position,
    required this.defaultWeightKg,
    this.weightStepKg,
    this.targetSets,
    this.targetRepsMin,
    this.targetRepsMax,
    this.dropCount,
  });

  final String id;
  final String programExerciseId;
  final String exerciseId;
  final int position;
  final double defaultWeightKg;

  /// Weight step in **kg**; NULL → fall back to the slot's step.
  final double? weightStepKg;

  /// Own prescription; each NULL → the slot's value ([resolvedOn]).
  final int? targetSets;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final int? dropCount;

  /// The slot row as this variant runs it: the variant's exercise, weight and
  /// every prescription field it sets, the slot's value for each one it
  /// leaves NULL. Ids and position stay the slot's.
  ProgramExercise resolvedOn(ProgramExercise slot) => ProgramExercise(
    id: slot.id,
    programDayId: slot.programDayId,
    exerciseId: exerciseId,
    position: slot.position,
    targetSets: targetSets ?? slot.targetSets,
    targetRepsMin: targetRepsMin ?? slot.targetRepsMin,
    targetRepsMax: targetRepsMax ?? slot.targetRepsMax,
    defaultWeightKg: defaultWeightKg,
    weightStepKg: weightStepKg ?? slot.weightStepKg,
    dropCount: dropCount ?? slot.dropCount,
  );

  ProgramExerciseVariant copyWith({
    String? exerciseId,
    int? position,
    double? defaultWeightKg,
    double? weightStepKg,
    bool clearWeightStep = false,
  }) => ProgramExerciseVariant(
    id: id,
    programExerciseId: programExerciseId,
    exerciseId: exerciseId ?? this.exerciseId,
    position: position ?? this.position,
    defaultWeightKg: defaultWeightKg ?? this.defaultWeightKg,
    weightStepKg: clearWeightStep ? null : (weightStepKg ?? this.weightStepKg),
    targetSets: targetSets,
    targetRepsMin: targetRepsMin,
    targetRepsMax: targetRepsMax,
    dropCount: dropCount,
  );

  factory ProgramExerciseVariant.fromRow(Map<String, Object?> row) =>
      ProgramExerciseVariant(
        id: row['id'] as String,
        programExerciseId: row['program_exercise_id'] as String,
        exerciseId: row['exercise_id'] as String,
        position: (row['position'] as num).toInt(),
        defaultWeightKg: (row['default_weight'] as num).toDouble(),
        weightStepKg: (row['weight_step'] as num?)?.toDouble(),
        targetSets: (row['target_sets'] as num?)?.toInt(),
        targetRepsMin: (row['rep_min'] as num?)?.toInt(),
        targetRepsMax: (row['rep_max'] as num?)?.toInt(),
        dropCount: (row['drop_count'] as num?)?.toInt(),
      );

  Map<String, Object?> toRow() => {
    'id': id,
    'program_exercise_id': programExerciseId,
    'exercise_id': exerciseId,
    'position': position,
    'default_weight': defaultWeightKg,
    'weight_step': weightStepKg,
    'target_sets': targetSets,
    'rep_min': targetRepsMin,
    'rep_max': targetRepsMax,
    'drop_count': dropCount,
  };
}

/// A variant joined with its exercise name, for list UIs.
class ProgramExerciseVariantView {
  const ProgramExerciseVariantView({
    required this.variant,
    required this.exerciseName,
  });
  final ProgramExerciseVariant variant;
  final String exerciseName;
}

/// Why a variant — or a slot's base exercise — was refused. SOW-14 rule: within
/// one program day an exercise is used at most once as a variant, and never as
/// both a variant and a base (two slots may still share a base, as in 1.4.1).
enum VariantConflictReason {
  /// The variant would be the slot's own base exercise.
  sameAsBase,

  /// The slot already has this variant.
  duplicate,

  /// Another slot on the same day already uses it as its base exercise — the
  /// summary could no longer tell which slot a logged set belongs to.
  baseOfAnotherSlot,

  /// Another slot on the same day already has it as a variant — sets logged
  /// on it would be pooled across both slots. Raised for a new variant AND for
  /// a slot base added or renamed to it.
  variantOfAnotherSlot,
}

class VariantConflict implements Exception {
  const VariantConflict(this.reason, this.exerciseName);
  final VariantConflictReason reason;
  final String exerciseName;

  /// User-facing explanation.
  String get message {
    final n = exerciseName.toUpperCase();
    switch (reason) {
      case VariantConflictReason.sameAsBase:
        return '$n is this slot\'s own exercise.';
      case VariantConflictReason.duplicate:
        return '$n is already a variant here.';
      case VariantConflictReason.baseOfAnotherSlot:
        return '$n is already its own exercise on this day.';
      case VariantConflictReason.variantOfAnotherSlot:
        return '$n is already a variant of another exercise on this day.';
    }
  }

  @override
  String toString() => 'VariantConflict($reason, $exerciseName)';
}
