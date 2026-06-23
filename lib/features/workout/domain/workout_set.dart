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
    this.setGroup,
    this.groupSeq = 0,
  });
  final String id;
  final String sessionId;
  final String exerciseId;
  final int setIndex;
  final int reps;
  final double weightKg;
  final int rir;
  final DateTime loggedAt;

  /// The "back-to-back unit" this set belongs to (drop set now, superset later).
  /// NULL for a plain set, which is then a singleton group keyed by its own id.
  final String? setGroup;

  /// Order within the group: 0 = top set, 1..N = drops (or superset member
  /// order). 0 for a plain set.
  final int groupSeq;

  /// The effective group key — explicit [setGroup] if present, else the set's
  /// own id (a singleton group). Completed-set counts use distinct group keys.
  String get groupKey => setGroup ?? id;

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
        setGroup: setGroup,
        groupSeq: groupSeq,
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
        setGroup: row['set_group'] as String?,
        groupSeq: (row['group_seq'] as num?)?.toInt() ?? 0,
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
        'set_group': setGroup,
        'group_seq': groupSeq,
      };
}
