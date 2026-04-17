class ProgramDay {
  const ProgramDay({
    required this.id,
    required this.programId,
    required this.name,
    required this.position,
  });
  final String id;
  final String programId;
  final String name;
  final int position;

  ProgramDay copyWith({String? name, int? position}) => ProgramDay(
        id: id,
        programId: programId,
        name: name ?? this.name,
        position: position ?? this.position,
      );

  factory ProgramDay.fromRow(Map<String, Object?> row) => ProgramDay(
        id: row['id'] as String,
        programId: row['program_id'] as String,
        name: row['name'] as String,
        position: row['position'] as int,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'program_id': programId,
        'name': name,
        'position': position,
      };
}
