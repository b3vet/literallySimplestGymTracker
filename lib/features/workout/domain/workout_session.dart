enum SessionStatus { active, completed, abandoned }

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.programDayId,
    required this.startedAt,
    this.endedAt,
    required this.status,
  });
  final String id;
  final String? programDayId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final SessionStatus status;

  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt);

  factory WorkoutSession.fromRow(Map<String, Object?> row) => WorkoutSession(
        id: row['id'] as String,
        programDayId: row['program_day_id'] as String?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
        endedAt: row['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['ended_at'] as int),
        status: SessionStatus.values.firstWhere(
          (s) => s.name == row['status'],
          orElse: () => SessionStatus.abandoned,
        ),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'program_day_id': programDayId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'status': status.name,
      };
}
