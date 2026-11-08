/// One variant of a program slot (SOW-14): an alternative exercise for the same
/// slot — e.g. "Shoulder Press (Machine)" for a "Shoulder Press" slot — with
/// its OWN target weight and weight step. Sets, reps and drop count come from
/// the slot. PRs, Stats and targets are tracked per variant (DEC-0007 H1).
class ProgramExerciseVariant {
  const ProgramExerciseVariant({
    required this.id,
    required this.programExerciseId,
    required this.exerciseId,
    required this.position,
    required this.defaultWeightKg,
    this.weightStepKg,
  });

  final String id;
  final String programExerciseId;
  final String exerciseId;
  final int position;
  final double defaultWeightKg;

  /// Weight step in **kg**; NULL → fall back to the slot's step.
  final double? weightStepKg;

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
  );

  factory ProgramExerciseVariant.fromRow(Map<String, Object?> row) =>
      ProgramExerciseVariant(
        id: row['id'] as String,
        programExerciseId: row['program_exercise_id'] as String,
        exerciseId: row['exercise_id'] as String,
        position: (row['position'] as num).toInt(),
        defaultWeightKg: (row['default_weight'] as num).toDouble(),
        weightStepKg: (row['weight_step'] as num?)?.toDouble(),
      );

  Map<String, Object?> toRow() => {
    'id': id,
    'program_exercise_id': programExerciseId,
    'exercise_id': exerciseId,
    'position': position,
    'default_weight': defaultWeightKg,
    'weight_step': weightStepKg,
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

/// Why a variant was refused.
enum VariantConflictReason {
  /// The variant would be the slot's own base exercise.
  sameAsBase,

  /// The slot already has this variant.
  duplicate,

  /// Another slot on the same day already uses it as its base exercise — the
  /// summary could no longer tell which slot a logged set belongs to.
  baseOfAnotherSlot,
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
    }
  }

  @override
  String toString() => 'VariantConflict($reason, $exerciseName)';
}
