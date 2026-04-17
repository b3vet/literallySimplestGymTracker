class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.setIndex,
    required this.reps,
    required this.weightKg,
    required this.rir,
    required this.loggedAt,
  });
  final String id;
  final String sessionId;
  final String exerciseId;
  final int setIndex;
  final int reps;
  final double weightKg;
  final int rir;
  final DateTime loggedAt;

  WorkoutSet copyWith({
    int? reps,
    double? weightKg,
    int? rir,
  }) =>
      WorkoutSet(
        id: id,
        sessionId: sessionId,
        exerciseId: exerciseId,
        setIndex: setIndex,
        reps: reps ?? this.reps,
        weightKg: weightKg ?? this.weightKg,
        rir: rir ?? this.rir,
        loggedAt: loggedAt,
      );

  factory WorkoutSet.fromRow(Map<String, Object?> row) => WorkoutSet(
        id: row['id'] as String,
        sessionId: row['session_id'] as String,
        exerciseId: row['exercise_id'] as String,
        setIndex: row['set_index'] as int,
        reps: row['reps'] as int,
        weightKg: (row['weight'] as num).toDouble(),
        rir: row['rir'] as int,
        loggedAt:
            DateTime.fromMillisecondsSinceEpoch(row['logged_at'] as int),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'session_id': sessionId,
        'exercise_id': exerciseId,
        'set_index': setIndex,
        'reps': reps,
        'weight': weightKg,
        'rir': rir,
        'logged_at': loggedAt.millisecondsSinceEpoch,
      };
}
