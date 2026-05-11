import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/exercise.dart';
import '../domain/program.dart';
import '../domain/program_day.dart';
import '../domain/program_exercise.dart';

class ProgramDao {
  ProgramDao(this._db);
  final Database _db;
  static const _uuid = Uuid();

  // ---------- Programs ----------

  Future<List<Program>> listPrograms() async {
    final rows =
        await _db.query('programs', orderBy: 'created_at DESC');
    return rows.map(Program.fromRow).toList();
  }

  Future<Program> createProgram(String name) async {
    final program = Program(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    await _db.insert('programs', program.toRow());
    return program;
  }

  Future<void> renameProgram(String id, String name) async {
    await _db.update(
      'programs',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteProgram(String id) async {
    await _db.delete('programs', where: 'id = ?', whereArgs: [id]);
  }

  Future<Program?> findProgram(String id) async {
    final rows =
        await _db.query('programs', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Program.fromRow(rows.first);
  }

  // ---------- Days ----------

  Future<List<ProgramDay>> listDays(String programId) async {
    final rows = await _db.query(
      'program_days',
      where: 'program_id = ?',
      whereArgs: [programId],
      orderBy: 'position ASC',
    );
    return rows.map(ProgramDay.fromRow).toList();
  }

  Future<ProgramDay?> findDay(String id) async {
    final rows = await _db
        .query('program_days', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProgramDay.fromRow(rows.first);
  }

  Future<ProgramDay> createDay(String programId, String name) async {
    final count = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM program_days WHERE program_id = ?',
          [programId],
        )) ??
        0;
    final day = ProgramDay(
      id: _uuid.v4(),
      programId: programId,
      name: name.trim(),
      position: count,
    );
    await _db.insert('program_days', day.toRow());
    return day;
  }

  Future<void> renameDay(String id, String name) async {
    await _db.update(
      'program_days',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDay(String id) async {
    await _db.delete('program_days', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorderDays(String programId, List<String> dayIdsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < dayIdsInOrder.length; i++) {
      batch.update(
        'program_days',
        {'position': i},
        where: 'id = ?',
        whereArgs: [dayIdsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  // ---------- Exercise library ----------

  Future<Exercise> findOrCreateExercise(String name) async {
    final trimmed = name.trim();
    final existing = await _db.query(
      'exercises',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (existing.isNotEmpty) return Exercise.fromRow(existing.first);
    final e = Exercise(id: _uuid.v4(), name: trimmed);
    await _db.insert('exercises', e.toRow());
    return e;
  }

  Future<List<Exercise>> listExercises() async {
    final rows = await _db.query('exercises', orderBy: 'name COLLATE NOCASE');
    return rows.map(Exercise.fromRow).toList();
  }

  Future<Exercise?> findExercise(String id) async {
    final rows = await _db
        .query('exercises', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Exercise.fromRow(rows.first);
  }

  /// Names of every exercise the user has ever named, sorted alphabetically
  /// (case-insensitive). Used to populate the program-editor combobox.
  Future<List<String>> listKnownExerciseNames() async {
    final rows = await _db.query(
      'exercises',
      columns: ['name'],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Most recent [ProgramExercise] in any program/day that references the
  /// exercise with the given case-insensitive name. Used to autofill
  /// sets/reps/weight when the user picks an existing exercise in the editor.
  Future<ProgramExercise?> mostRecentProgramExerciseForName(String name) async {
    final rows = await _db.rawQuery(
      '''
      SELECT pe.*
      FROM program_exercises pe
      JOIN exercises e     ON e.id  = pe.exercise_id
      JOIN program_days pd ON pd.id = pe.program_day_id
      JOIN programs p      ON p.id  = pd.program_id
      WHERE e.name = ? COLLATE NOCASE
      ORDER BY p.created_at DESC, pd.position DESC, pe.position DESC
      LIMIT 1
      ''',
      [name.trim()],
    );
    return rows.isEmpty ? null : ProgramExercise.fromRow(rows.first);
  }

  // ---------- Program exercises ----------

  Future<List<ProgramExerciseView>> listProgramExercises(
      String programDayId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT pe.*, e.name AS exercise_name
      FROM program_exercises pe
      JOIN exercises e ON e.id = pe.exercise_id
      WHERE pe.program_day_id = ?
      ORDER BY pe.position ASC
      ''',
      [programDayId],
    );
    return rows
        .map((r) => ProgramExerciseView(
              pe: ProgramExercise.fromRow(r),
              exerciseName: r['exercise_name'] as String,
            ))
        .toList();
  }

  Future<ProgramExercise> addProgramExercise({
    required String programDayId,
    required String exerciseName,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required double defaultWeightKg,
  }) async {
    final exercise = await findOrCreateExercise(exerciseName);
    final count = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM program_exercises WHERE program_day_id = ?',
          [programDayId],
        )) ??
        0;
    final pe = ProgramExercise(
      id: _uuid.v4(),
      programDayId: programDayId,
      exerciseId: exercise.id,
      position: count,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      defaultWeightKg: defaultWeightKg,
    );
    await _db.insert('program_exercises', pe.toRow());
    return pe;
  }

  Future<void> updateProgramExercise(ProgramExercise pe) async {
    await _db.update(
      'program_exercises',
      pe.toRow(),
      where: 'id = ?',
      whereArgs: [pe.id],
    );
  }

  Future<void> deleteProgramExercise(String id) async {
    await _db.delete('program_exercises', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reorderProgramExercises(
      String programDayId, List<String> idsInOrder) async {
    final batch = _db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update(
        'program_exercises',
        {'position': i},
        where: 'id = ?',
        whereArgs: [idsInOrder[i]],
      );
    }
    await batch.commit(noResult: true);
  }
}
