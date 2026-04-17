class Exercise {
  const Exercise({required this.id, required this.name, this.notes});
  final String id;
  final String name;
  final String? notes;

  factory Exercise.fromRow(Map<String, Object?> row) => Exercise(
        id: row['id'] as String,
        name: row['name'] as String,
        notes: row['notes'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'notes': notes,
      };
}
