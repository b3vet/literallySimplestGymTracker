import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/exercise.dart';
import '../domain/program.dart';
import '../domain/program_day.dart';
import '../domain/program_exercise.dart';
import '../domain/program_exercise_variant.dart';

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

  /// Whether the in-progress workout runs on [dayId], or on any day of
  /// [programId] — the delete confirmation warns that it will end.
  Future<bool> hasActiveWorkout({String? programId, String? dayId}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT 1 FROM workout_sessions ws
      JOIN program_days pd ON pd.id = ws.program_day_id
      WHERE ws.status = 'active' AND (pd.id = ? OR pd.program_id = ?)
      LIMIT 1
      ''',
      [dayId ?? '', programId ?? ''],
    );
    return rows.isNotEmpty;
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
      orderBy: _byPosition,
    );
    return rows.map(ProgramDay.fromRow).toList();
  }

  Future<ProgramDay?> findDay(String id) async {
    final rows = await _db
        .query('program_days', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProgramDay.fromRow(rows.first);
  }

  /// Add a day, last in order.
  Future<ProgramDay> createDay(String programId, String name) async {
    return _db.transaction((txn) async {
      final day = ProgramDay(
        id: _uuid.v4(),
        programId: programId,
        name: name.trim(),
        position:
            await _nextPosition(txn, 'program_days', 'program_id', programId),
      );
      await txn.insert('program_days', day.toRow());
      return day;
    });
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
  /// logged against it — see [deleteProgram]. The program's remaining days
  /// are renumbered 0..n-1 in the same transaction, so a later add lands last.
  Future<void> deleteDay(String id) async {
    await _db.transaction((txn) async {
      final day = await txn.query('program_days',
          columns: ['program_id'], where: 'id = ?', whereArgs: [id], limit: 1);
      await txn.update(
        'workout_sessions',
        {'program_day_id': null},
        where: 'program_day_id = ?',
        whereArgs: [id],
      );
      await txn.delete('program_days', where: 'id = ?', whereArgs: [id]);
      if (day.isNotEmpty) {
        await _renumber(txn, 'program_days', 'program_id',
            day.first['program_id'] as String);
      }
    });
  }

  // ---------- Copy (SOW-13) ----------

  /// Deep-copy a program: the program row, every day and every slot, each
  /// under a fresh id, order kept (positions renumbered 0..n-1, so a source
  /// with gaps or duplicate positions copies clean). The copy points at the SAME `exercises`
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
        orderBy: _byPosition,
      );
      for (final (i, d) in days.indexed) {
        final day = ProgramDay.fromRow(d);
        final newDayId = _uuid.v4();
        await txn.insert(
          'program_days',
          ProgramDay(
            id: newDayId,
            programId: copy.id,
            name: day.name,
            position: i,
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
      final copy = ProgramDay(
        id: _uuid.v4(),
        programId: source.programId,
        name: name.trim(),
        position: await _nextPosition(
            txn, 'program_days', 'program_id', source.programId),
      );
      await txn.insert('program_days', copy.toRow());
      await _copySlots(txn, fromDayId: source.id, toDayId: copy.id);
      return copy;
    });
  }

  /// Copy every slot of [fromDayId] — and each slot's variants — into
  /// [toDayId] under new ids. Copies raw rows (all columns but the ids and
  /// positions), so a column added by a later migration is carried along
  /// without touching this code. Order is kept; positions are renumbered
  /// 0..n-1 (slots, and each slot's copied variants).
  Future<void> _copySlots(
    Transaction txn, {
    required String fromDayId,
    required String toDayId,
  }) async {
    final slots = await txn.query(
      'program_exercises',
      where: 'program_day_id = ?',
      whereArgs: [fromDayId],
      orderBy: _byPosition,
    );
    // SOW-14 day rule: a variant that collides with a base on the day, or
    // repeats an earlier variant, is not copied (the base / first one wins) —
    // the same rows [listVariantsForDay] hides, so the copy looks identical.
    final bases = {for (final s in slots) s['exercise_id'] as String};
    final usedVariants = <String>{};
    for (final (slotPos, slot) in slots.indexed) {
      final newSlotId = _uuid.v4();
      final row = Map<String, Object?>.of(slot)
        ..['id'] = newSlotId
        ..['program_day_id'] = toDayId
        ..['position'] = slotPos;
      await txn.insert('program_exercises', row);
      final variants = await txn.query(
        'program_exercise_variants',
        where: 'program_exercise_id = ?',
        whereArgs: [slot['id']],
        orderBy: _byPosition,
      );
      var variantPos = 0;
      for (final v in variants) {
        final exerciseId = v['exercise_id'] as String;
        if (bases.contains(exerciseId) || !usedVariants.add(exerciseId)) {
          continue;
        }
        await txn.insert(
          'program_exercise_variants',
          Map<String, Object?>.of(v)
            ..['id'] = _uuid.v4()
            ..['program_exercise_id'] = newSlotId
            ..['position'] = variantPos++,
        );
      }
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

  /// Case-insensitive lookup by name; never creates a row.
  Future<Exercise?> findExerciseByName(String name) async {
    final rows = await _db.query(
      'exercises',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Exercise.fromRow(rows.first);
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
      ORDER BY p.created_at DESC, pd.position DESC, pd.rowid DESC,
               pe.position DESC, pe.rowid DESC
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
      ORDER BY pe.position ASC, pe.rowid ASC
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
    return _db.transaction((txn) async {
      // SOW-14 day rule: an exercise that is already a variant on this day
      // can't also be a slot's base (two slots sharing a base stay allowed).
      if (await _isVariantOnDay(txn, programDayId, exercise.id)) {
        throw VariantConflict(
            VariantConflictReason.variantOfAnotherSlot, exercise.name);
      }
      final pe = ProgramExercise(
        id: _uuid.v4(),
        programDayId: programDayId,
        exerciseId: exercise.id,
        position: await _nextPosition(
            txn, 'program_exercises', 'program_day_id', programDayId),
        targetSets: targetSets,
        targetRepsMin: targetRepsMin,
        targetRepsMax: targetRepsMax,
        defaultWeightKg: defaultWeightKg,
        weightStepKg: weightStepKg,
        dropCount: dropCount,
      );
      await txn.insert('program_exercises', pe.toRow());
      return pe;
    });
  }

  /// Write a slot. If its (possibly renamed) base exercise is one of the
  /// slot's own variants, that variant is dropped in the same transaction —
  /// a slot can't be a variant of itself. Renaming the base to a variant of
  /// ANOTHER slot on the day throws [VariantConflict] and writes nothing
  /// (SOW-14 day rule); a write that keeps the exercise is never refused.
  Future<void> updateProgramExercise(ProgramExercise pe) async {
    await _db.transaction((txn) async {
      final current = await txn.query('program_exercises',
          columns: ['exercise_id'],
          where: 'id = ?',
          whereArgs: [pe.id],
          limit: 1);
      final renamed =
          current.isEmpty || current.first['exercise_id'] != pe.exerciseId;
      if (renamed &&
          await _isVariantOnDay(txn, pe.programDayId, pe.exerciseId,
              exceptSlotId: pe.id)) {
        final e = await txn.query('exercises',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [pe.exerciseId],
            limit: 1);
        throw VariantConflict(VariantConflictReason.variantOfAnotherSlot,
            e.isEmpty ? '' : e.first['name'] as String);
      }
      await txn.update(
        'program_exercises',
        pe.toRow(),
        where: 'id = ?',
        whereArgs: [pe.id],
      );
      await txn.delete(
        'program_exercise_variants',
        where: 'program_exercise_id = ? AND exercise_id = ?',
        whereArgs: [pe.id, pe.exerciseId],
      );
    });
  }

  Future<ProgramExercise?> findProgramExercise(String id) async {
    final rows = await _db.query('program_exercises',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProgramExercise.fromRow(rows.first);
  }

  /// Delete a slot; its variants cascade. Sets already logged stay (they are
  /// keyed by exercise, not by slot), so History, PRs and Stats are untouched.
  ///
  /// SOW-15: when a workout in progress runs on the slot's day, the slot's
  /// session override is kept as a *dropped* marker (`skipped = 1`; written
  /// when the slot had none) in the same transaction. The workout's queue
  /// ignores it — the queue is built from the plan, and the slot is gone — but
  /// the summary reads it so it does not offer ADD TO DAY for the exercise
  /// just deleted from the day. No schema change: `program_exercise_id` has
  /// no foreign key.
  ///
  /// The day's remaining slots are renumbered 0..n-1 in the same
  /// transaction, so a later add lands last. That workout's inserted
  /// exercises (`order_pos`, placed between the old integer positions) are
  /// remapped with [remapOrderPos] so they keep their place in the queue.
  Future<void> deleteProgramExercise(String id) async {
    await _db.transaction((txn) async {
      final slot = await txn.query('program_exercises',
          where: 'id = ?', whereArgs: [id], limit: 1);
      var active = const <Map<String, Object?>>[];
      if (slot.isNotEmpty) {
        final pe = ProgramExercise.fromRow(slot.first);
        active = await txn.query('workout_sessions',
            columns: ['id'],
            where: "program_day_id = ? AND status = 'active'",
            whereArgs: [pe.programDayId]);
        for (final s in active) {
          final marked = await txn.update(
            'session_exercise_overrides',
            {'skipped': 1},
            where: 'session_id = ? AND program_exercise_id = ?',
            whereArgs: [s['id'], id],
          );
          if (marked > 0) continue;
          await txn.insert('session_exercise_overrides', {
            'id': _uuid.v4(),
            'session_id': s['id'],
            'program_exercise_id': id,
            'exercise_id': pe.exerciseId,
            'target_sets': pe.targetSets,
            'target_reps_min': pe.targetRepsMin,
            'target_reps_max': pe.targetRepsMax,
            'default_weight': pe.defaultWeightKg,
            'weight_step': pe.weightStepKg,
            'skipped': 1,
            'inserted': 0,
            'drop_count': pe.dropCount,
          });
        }
      }
      await txn.delete('program_exercises', where: 'id = ?', whereArgs: [id]);
      if (slot.isEmpty) return;
      final oldPositions = await _renumber(txn, 'program_exercises',
          'program_day_id', slot.first['program_day_id'] as String);
      for (final s in active) {
        final inserted = await txn.query('session_exercise_overrides',
            columns: ['id', 'order_pos'],
            where: 'session_id = ? AND inserted = 1 AND order_pos IS NOT NULL',
            whereArgs: [s['id']]);
        for (final o in inserted) {
          final pos = (o['order_pos'] as num).toDouble();
          final next = remapOrderPos(pos, oldPositions);
          if (next == pos) continue;
          await txn.update('session_exercise_overrides', {'order_pos': next},
              where: 'id = ?', whereArgs: [o['id']]);
        }
      }
    });
  }

  /// Whether the in-progress workout runs on the day that holds slot [id] —
  /// the exercise delete confirmation then warns that the workout drops it.
  Future<bool> hasActiveWorkoutOnSlot(String id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT 1 FROM workout_sessions ws
      JOIN program_exercises pe ON pe.program_day_id = ws.program_day_id
      WHERE ws.status = 'active' AND pe.id = ?
      LIMIT 1
      ''',
      [id],
    );
    return rows.isNotEmpty;
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

  // ---------- Variants (SOW-14) ----------

  /// A slot's variants, in order, with their exercise names. Same read guard
  /// as [listVariantsForDay].
  Future<List<ProgramExerciseVariantView>> listVariants(
      String programExerciseId) async {
    final slot = await _db.query('program_exercises',
        columns: ['program_day_id'],
        where: 'id = ?',
        whereArgs: [programExerciseId],
        limit: 1);
    if (slot.isEmpty) return const [];
    final day = await listVariantsForDay(slot.first['program_day_id'] as String);
    return day[programExerciseId] ?? const [];
  }

  /// Every slot's variants on a day, keyed by slot id, each list in order.
  /// Slots without variants are absent from the map.
  ///
  /// Read guard for the SOW-14 day rule (each exercise once per day): the DAO
  /// refuses new conflicts, but a day can still hold one written before the
  /// rule (e.g. 1.4.1 renamed a base to one of its variants, or to another
  /// slot's variant). Such a variant is hidden — the base wins, else the first
  /// variant in day order — so the workout picker never shows a dead or
  /// ambiguous row.
  Future<Map<String, List<ProgramExerciseVariantView>>> listVariantsForDay(
      String programDayId) async {
    final bases = {
      for (final r in await _db.query('program_exercises',
          columns: ['exercise_id'],
          where: 'program_day_id = ?',
          whereArgs: [programDayId]))
        r['exercise_id'] as String,
    };
    final rows = await _db.rawQuery(
      '''
      SELECT v.*, e.name AS exercise_name
      FROM program_exercise_variants v
      JOIN exercises e ON e.id = v.exercise_id
      JOIN program_exercises pe ON pe.id = v.program_exercise_id
      WHERE pe.program_day_id = ?
      ORDER BY pe.position ASC, pe.rowid ASC, v.position ASC, v.rowid ASC
      ''',
      [programDayId],
    );
    final out = <String, List<ProgramExerciseVariantView>>{};
    final seen = <String>{};
    for (final r in rows) {
      final view = _variantView(r);
      final exerciseId = view.variant.exerciseId;
      if (bases.contains(exerciseId) || !seen.add(exerciseId)) continue;
      (out[view.variant.programExerciseId] ??= []).add(view);
    }
    return out;
  }

  /// Add a variant to a slot, last in order. Throws [VariantConflict] when the
  /// exercise is the slot's base, already a variant of it, or another slot's
  /// base or variant on the same day (SOW-14 day rule). A prescription field
  /// left null inherits the slot's value; the editor always passes all four.
  Future<ProgramExerciseVariant> addVariant({
    required String programExerciseId,
    required String exerciseName,
    required double defaultWeightKg,
    double? weightStepKg,
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    int? dropCount,
  }) async {
    final exercise = await findOrCreateExercise(exerciseName);
    return _db.transaction((txn) async {
      await _checkVariant(txn, programExerciseId, exercise.id, exercise.name);
      final v = ProgramExerciseVariant(
        id: _uuid.v4(),
        programExerciseId: programExerciseId,
        exerciseId: exercise.id,
        position: await _nextPosition(txn, 'program_exercise_variants',
            'program_exercise_id', programExerciseId),
        defaultWeightKg: defaultWeightKg,
        weightStepKg: weightStepKg,
        targetSets: targetSets,
        targetRepsMin: targetRepsMin,
        targetRepsMax: targetRepsMax,
        dropCount: dropCount,
      );
      await txn.insert('program_exercise_variants', v.toRow());
      return v;
    });
  }

  /// Edit a variant from the editor: name (may switch to another exercise),
  /// weight, step and prescription — written as given (null = inherit). Same
  /// rules as [addVariant].
  Future<ProgramExerciseVariant> editVariant({
    required String id,
    required String exerciseName,
    required double defaultWeightKg,
    double? weightStepKg,
    int? targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    int? dropCount,
  }) async {
    final exercise = await findOrCreateExercise(exerciseName);
    return _db.transaction((txn) async {
      final rows = await txn.query('program_exercise_variants',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('Variant $id not found.');
      final current = ProgramExerciseVariant.fromRow(rows.first);
      if (exercise.id != current.exerciseId) {
        await _checkVariant(
            txn, current.programExerciseId, exercise.id, exercise.name);
      }
      final updated = ProgramExerciseVariant(
        id: current.id,
        programExerciseId: current.programExerciseId,
        exerciseId: exercise.id,
        position: current.position,
        defaultWeightKg: defaultWeightKg,
        weightStepKg: weightStepKg,
        targetSets: targetSets,
        targetRepsMin: targetRepsMin,
        targetRepsMax: targetRepsMax,
        dropCount: dropCount,
      );
      await txn.update('program_exercise_variants', updated.toRow(),
          where: 'id = ?', whereArgs: [id]);
      return updated;
    });
  }

  /// Write a variant row verbatim (summary target raise and its undo).
  Future<void> updateVariant(ProgramExerciseVariant v) async {
    await _db.update('program_exercise_variants', v.toRow(),
        where: 'id = ?', whereArgs: [v.id]);
  }

  /// Delete a variant; the slot's remaining variants are renumbered 0..n-1
  /// in the same transaction.
  Future<void> deleteVariant(String id) async {
    await _db.transaction((txn) async {
      final row = await txn.query('program_exercise_variants',
          columns: ['program_exercise_id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1);
      await txn.delete('program_exercise_variants',
          where: 'id = ?', whereArgs: [id]);
      if (row.isNotEmpty) {
        await _renumber(txn, 'program_exercise_variants', 'program_exercise_id',
            row.first['program_exercise_id'] as String);
      }
    });
  }

  Future<void> _checkVariant(
    Transaction txn,
    String programExerciseId,
    String exerciseId,
    String exerciseName,
  ) async {
    final slot = await txn.query('program_exercises',
        where: 'id = ?', whereArgs: [programExerciseId], limit: 1);
    if (slot.isEmpty) throw StateError('Slot $programExerciseId not found.');
    if (slot.first['exercise_id'] == exerciseId) {
      throw VariantConflict(VariantConflictReason.sameAsBase, exerciseName);
    }
    final dup = await txn.query('program_exercise_variants',
        where: 'program_exercise_id = ? AND exercise_id = ?',
        whereArgs: [programExerciseId, exerciseId],
        limit: 1);
    if (dup.isNotEmpty) {
      throw VariantConflict(VariantConflictReason.duplicate, exerciseName);
    }
    final otherBase = await txn.query('program_exercises',
        where: 'program_day_id = ? AND exercise_id = ? AND id != ?',
        whereArgs: [slot.first['program_day_id'], exerciseId, programExerciseId],
        limit: 1);
    if (otherBase.isNotEmpty) {
      throw VariantConflict(
          VariantConflictReason.baseOfAnotherSlot, exerciseName);
    }
    if (await _isVariantOnDay(
        txn, slot.first['program_day_id'] as String, exerciseId,
        exceptSlotId: programExerciseId)) {
      throw VariantConflict(
          VariantConflictReason.variantOfAnotherSlot, exerciseName);
    }
  }

  /// Whether [exerciseId] is a variant of some slot on [programDayId] (other
  /// than [exceptSlotId]).
  Future<bool> _isVariantOnDay(
    DatabaseExecutor txn,
    String programDayId,
    String exerciseId, {
    String? exceptSlotId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT 1 FROM program_exercise_variants v
      JOIN program_exercises pe ON pe.id = v.program_exercise_id
      WHERE pe.program_day_id = ? AND v.exercise_id = ? AND pe.id != ?
      LIMIT 1
      ''',
      [programDayId, exerciseId, exceptSlotId ?? ''],
    );
    return rows.isNotEmpty;
  }

  ProgramExerciseVariantView _variantView(Map<String, Object?> r) =>
      ProgramExerciseVariantView(
        variant: ProgramExerciseVariant.fromRow(r),
        exerciseName: r['exercise_name'] as String,
      );

  // ---------- Positions ----------

  /// Sibling order. `rowid` breaks ties so rows that share a position (data
  /// written by builds that numbered new rows with COUNT, which collided after
  /// a delete) still read in a stable, insertion order.
  static const _byPosition = 'position ASC, rowid ASC';

  /// Position for a new row appended to the siblings under [parentId]:
  /// MAX + 1, never COUNT — a gap or a duplicate makes COUNT land on, or
  /// before, an existing row.
  static Future<int> _nextPosition(
    DatabaseExecutor txn,
    String table,
    String parentColumn,
    String parentId,
  ) async {
    return Sqflite.firstIntValue(await txn.rawQuery(
          'SELECT COALESCE(MAX(position), -1) + 1 FROM $table '
          'WHERE $parentColumn = ?',
          [parentId],
        )) ??
        0;
  }

  /// Renumber the siblings under [parentId] to 0..n-1, keeping their order
  /// ([_byPosition]); rows already in place are not written. Returns the old
  /// positions in that order — index i held old position `result[i]`.
  static Future<List<int>> _renumber(
    DatabaseExecutor txn,
    String table,
    String parentColumn,
    String parentId,
  ) async {
    final rows = await txn.query(table,
        columns: ['id', 'position'],
        where: '$parentColumn = ?',
        whereArgs: [parentId],
        orderBy: _byPosition);
    final old = <int>[];
    for (final (i, r) in rows.indexed) {
      final pos = (r['position'] as num).toInt();
      old.add(pos);
      if (pos == i) continue;
      await txn.update(table, {'position': i},
          where: 'id = ?', whereArgs: [r['id']]);
    }
    return old;
  }
}

/// Map a session queue key [pos] — placed relative to the template slots'
/// integer positions [oldPositions] (ascending; the slot now at index i had
/// `oldPositions[i]`) — onto the renumbered positions 0..n-1, keeping its
/// place between the same neighbours. Monotonic, so the queue's order is
/// unchanged. With no slots left the key is returned as is.
double remapOrderPos(double pos, List<int> oldPositions) {
  if (oldPositions.isEmpty) return pos;
  final first = oldPositions.first;
  final last = oldPositions.last;
  if (pos <= first) return pos - first;
  if (pos >= last) return oldPositions.length - 1 + (pos - last);
  // first < pos < last: find the neighbours a <= pos < b.
  var k = 0;
  while (oldPositions[k + 1] <= pos) {
    k++;
  }
  final a = oldPositions[k];
  final b = oldPositions[k + 1];
  return k + (pos - a) / (b - a);
}
