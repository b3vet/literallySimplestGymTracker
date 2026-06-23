class ProgramExercise {
  const ProgramExercise({
    required this.id,
    required this.programDayId,
    required this.exerciseId,
    required this.position,
    required this.targetSets,
    required this.targetRepsMin,
    required this.targetRepsMax,
    required this.defaultWeightKg,
    this.weightStepKg,
    this.dropCount = 0,
  });
  final String id;
  final String programDayId;
  final String exerciseId;
  final int position;
  final int targetSets;
  final int targetRepsMin;
  final int targetRepsMax;
  final double defaultWeightKg;

  /// Per-exercise weight step in **kg**. Persisted as NULL when the user has
  /// never customised it — callers should fall back to the unit's default
  /// step (`WeightUnit.defaultStep`) for display.
  final double? weightStepKg;

  /// 0 = normal exercise; N ≥ 1 = each working set is a drop set with N drops
  /// after the top. The reps/weight targets describe the TOP set.
  final int dropCount;

  ProgramExercise copyWith({
    int? position,
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    double? defaultWeightKg,
    double? weightStepKg,
    bool clearWeightStep = false,
    int? dropCount,
  }) =>
      ProgramExercise(
        id: id,
        programDayId: programDayId,
        exerciseId: exerciseId,
        position: position ?? this.position,
        targetSets: targetSets ?? this.targetSets,
        targetRepsMin: targetRepsMin ?? this.targetRepsMin,
        targetRepsMax: targetRepsMax ?? this.targetRepsMax,
        defaultWeightKg: defaultWeightKg ?? this.defaultWeightKg,
        weightStepKg: clearWeightStep ? null : (weightStepKg ?? this.weightStepKg),
        dropCount: dropCount ?? this.dropCount,
      );

  factory ProgramExercise.fromRow(Map<String, Object?> row) => ProgramExercise(
        id: row['id'] as String,
        programDayId: row['program_day_id'] as String,
        exerciseId: row['exercise_id'] as String,
        position: row['position'] as int,
        targetSets: row['target_sets'] as int,
        targetRepsMin: row['target_reps_min'] as int,
        targetRepsMax: row['target_reps_max'] as int,
        defaultWeightKg: (row['default_weight'] as num).toDouble(),
        weightStepKg: (row['weight_step'] as num?)?.toDouble(),
        dropCount: (row['drop_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'program_day_id': programDayId,
        'exercise_id': exerciseId,
        'position': position,
        'target_sets': targetSets,
        'target_reps_min': targetRepsMin,
        'target_reps_max': targetRepsMax,
        'default_weight': defaultWeightKg,
        'weight_step': weightStepKg,
        'drop_count': dropCount,
      };
}

/// Program exercise joined with its exercise name for list UIs.
class ProgramExerciseView {
  const ProgramExerciseView({required this.pe, required this.exerciseName});
  final ProgramExercise pe;
  final String exerciseName;
}
