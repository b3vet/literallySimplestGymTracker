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

  /// Delete a program with its days and slots (cascade). Workouts logged
  /// against any of its days are KEPT and detached (`program_day_id = NULL`)
  /// inside the same transaction — `workout_sessions.program_day_id` has no
  /// `ON DELETE`, so without this the delete fails on the foreign key as soon
  /// as one workout was logged. History then shows those sessions as plain
  /// workouts; their sets, PRs and Stats are untouched (DEC-0007 H5).
  Future<void> deleteProgram(String id) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE workout_sessions SET program_day_id = NULL '
        'WHERE program_day_id IN '
        '(SELECT id FROM program_days WHERE program_id = ?)',
        [id],
      );
      await txn.delete('programs', where: 'id = ?', whereArgs: [id]);
    });
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

  /// Delete a day with its slots (cascade), keeping and detaching any workouts
  /// logged against it — see [deleteProgram].
  Future<void> deleteDay(String id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'workout_sessions',
        {'program_day_id': null},
        where: 'program_day_id = ?',
        whereArgs: [id],
      );
      await txn.delete('program_days', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------- Copy (SOW-13) ----------

  /// Deep-copy a program: the program row, every day and every slot, each
  /// under a fresh id, positions kept. The copy points at the SAME `exercises`
  /// rows (the shared library), so PRs, Stats and last-set prefill carry over;
  /// sessions, sets and session overrides are never copied. One transaction:
  /// a failure leaves no half-copied program behind.
  Future<Program> duplicateProgram(
    String programId, {
    required String name,
  }) async {
    return _db.transaction((txn) async {
      final copy = Program(
        id: _uuid.v4(),
        name: name.trim(),
        createdAt: DateTime.now(),
      );
      await txn.insert('programs', copy.toRow());
      final days = await txn.query(
        'program_days',
        where: 'program_id = ?',
        whereArgs: [programId],
        orderBy: 'position ASC',
      );
      for (final d in days) {
        final day = ProgramDay.fromRow(d);
        final newDayId = _uuid.v4();
        await txn.insert(
          'program_days',
          ProgramDay(
            id: newDayId,
            programId: copy.id,
            name: day.name,
            position: day.position,
          ).toRow(),
        );
        await _copySlots(txn, fromDayId: day.id, toDayId: newDayId);
      }
      return copy;
    });
  }

  /// Copy one day (with its slots) into the same program, appended last.
  Future<ProgramDay> duplicateDay(String dayId, {required String name}) async {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'program_days',
        where: 'id = ?',
        whereArgs: [dayId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Day $dayId not found.');
      final source = ProgramDay.fromRow(rows.first);
      // MAX + 1, not COUNT: deleting a day leaves a gap in the positions, so a
      // count could collide with the last day.
      final maxPos = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT MAX(position) FROM program_days WHERE program_id = ?',
            [source.programId],
          )) ??
          -1;
      final copy = ProgramDay(
        id: _uuid.v4(),
        programId: source.programId,
        name: name.trim(),
        position: maxPos + 1,
      );
      await txn.insert('program_days', copy.toRow());
      await _copySlots(txn, fromDayId: source.id, toDayId: copy.id);
      return copy;
    });
  }

  /// Copy every slot of [fromDayId] into [toDayId] under new ids. Copies the
  /// raw row (all columns but the ids), so a column added by a later migration
  /// is carried along without touching this code.
  Future<void> _copySlots(
    Transaction txn, {
    required String fromDayId,
    required String toDayId,
  }) async {
    final slots = await txn.query(
      'program_exercises',
      where: 'program_day_id = ?',
      whereArgs: [fromDayId],
      orderBy: 'position ASC',
    );
    for (final slot in slots) {
      final row = Map<String, Object?>.of(slot)
        ..['id'] = _uuid.v4()
        ..['program_day_id'] = toDayId;
      await txn.insert('program_exercises', row);
    }
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
    double? weightStepKg,
    int dropCount = 0,
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
      weightStepKg: weightStepKg,
      dropCount: dropCount,
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
