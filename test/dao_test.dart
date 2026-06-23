import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/application/pr_detector.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async =>
            db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final b = db.batch();
          for (final stmt in schemaV1) {
            b.execute(stmt);
          }
          for (final stmt in schemaV2Up) {
            b.execute(stmt);
          }
          for (final stmt in schemaV3Up) {
            b.execute(stmt);
          }
          for (final stmt in schemaV4Up) {
            b.execute(stmt);
          }
          for (final stmt in schemaV5Up) {
            b.execute(stmt);
          }
          for (final stmt in schemaV6Up) {
            b.execute(stmt);
          }
          await b.commit(noResult: true);
        },
      ));
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('ProgramDao CRUD roundtrip', () async {
    final db = await _openInMemory();
    final dao = ProgramDao(db);
    final p = await dao.createProgram('PPL');
    expect((await dao.listPrograms()).length, 1);

    final d = await dao.createDay(p.id, 'Push A');
    expect((await dao.listDays(p.id)).length, 1);

    final pe = await dao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 80,
    );
    final list = await dao.listProgramExercises(d.id);
    expect(list.length, 1);
    expect(list.first.exerciseName, 'Bench Press');
    expect(list.first.pe.targetSets, 3);

    await dao.deleteProgramExercise(pe.id);
    expect((await dao.listProgramExercises(d.id)).length, 0);

    await dao.deleteProgram(p.id);
    expect((await dao.listPrograms()).length, 0);
    // Cascade removed days.
    expect((await dao.listDays(p.id)).length, 0);

    await db.close();
  });

  test('WorkoutDao: lastSetForExercise and historicalMaxWeight', () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Push A');
    await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 80,
    );
    final ex = (await pdao.listExercises()).first;

    final session = await wdao.startSession(d.id);
    await wdao.insertSet(
        sessionId: session.id,
        exerciseId: ex.id,
        setIndex: 0,
        reps: 10,
        weightKg: 80,
        rir: 2);
    // Small delay so next set has later timestamp.
    await Future.delayed(const Duration(milliseconds: 2));
    await wdao.insertSet(
        sessionId: session.id,
        exerciseId: ex.id,
        setIndex: 1,
        reps: 8,
        weightKg: 82.5,
        rir: 1);

    final last = await wdao.lastSetForExercise(ex.id);
    expect(last?.weightKg, 82.5);
    final maxAll = await wdao.historicalMaxWeight(ex.id);
    expect(maxAll, 82.5);

    // Max *before* first set = null (no prior sets).
    final maxBeforeFirst =
        await wdao.historicalMaxWeight(ex.id, before: session.startedAt);
    expect(maxBeforeFirst, null);

    await db.close();
  });

  test('PrDetector flags first-ever session as weight PR', () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Push A');
    await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench',
      targetSets: 1,
      targetRepsMin: 5,
      targetRepsMax: 5,
      defaultWeightKg: 80,
    );
    final ex = (await pdao.listExercises()).first;
    final session = await wdao.startSession(d.id);
    await wdao.insertSet(
        sessionId: session.id,
        exerciseId: ex.id,
        setIndex: 0,
        reps: 5,
        weightKg: 80,
        rir: 2);
    await wdao.completeSession(session.id);

    final prs = await PrDetector(wdao).detect(session.id);
    expect(prs[ex.id]?.kind, PrKind.weight);
    expect(prs[ex.id]?.weightKg, 80);

    await db.close();
  });

  test(
      'session exercise overrides: upsert rotates previous_exercise_id and stays unique per slot',
      () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Push A');
    final pe = await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Shoulder Press (Smith)',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 60,
    );
    final smith = await pdao.findOrCreateExercise('Shoulder Press (Smith)');
    final machine = await pdao.findOrCreateExercise('Shoulder Press (Machine)');
    final dumbbell =
        await pdao.findOrCreateExercise('Shoulder Press (Dumbbell)');

    final session = await wdao.startSession(d.id);

    // First swap: Smith -> Machine. The slot's prior exercise is Smith.
    await wdao.upsertOverride(
      sessionId: session.id,
      programExerciseId: pe.id,
      exerciseId: machine.id,
      previousExerciseId: smith.id,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 55,
    );
    var overrides = await wdao.overridesForSession(session.id);
    expect(overrides.length, 1);
    expect(overrides.first.exerciseId, machine.id);
    expect(overrides.first.exerciseName, 'Shoulder Press (Machine)');
    expect(overrides.first.previousExerciseId, smith.id);
    expect(overrides.first.targetSets, 3);
    expect(overrides.first.defaultWeightKg, 55);

    // Second swap on the same slot: Machine -> Dumbbell. The override row
    // must be UPDATED (not duplicated) and previous_exercise_id should now
    // point at Machine (the slot's prior state).
    await wdao.upsertOverride(
      sessionId: session.id,
      programExerciseId: pe.id,
      exerciseId: dumbbell.id,
      previousExerciseId: machine.id,
      targetSets: 4,
      targetRepsMin: 10,
      targetRepsMax: 15,
      defaultWeightKg: 22.5,
      weightStepKg: 2.5,
    );
    overrides = await wdao.overridesForSession(session.id);
    expect(overrides.length, 1, reason: 'UNIQUE constraint should hold');
    expect(overrides.first.exerciseId, dumbbell.id);
    expect(overrides.first.previousExerciseId, machine.id);
    expect(overrides.first.targetSets, 4);
    expect(overrides.first.weightStepKg, 2.5);

    // Delete should drop the row.
    await wdao.deleteOverride(
      sessionId: session.id,
      programExerciseId: pe.id,
    );
    overrides = await wdao.overridesForSession(session.id);
    expect(overrides, isEmpty);

    await db.close();
  });

  test('session exercise overrides cascade on session delete', () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Push A');
    final pe = await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench',
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 80,
    );
    final alt = await pdao.findOrCreateExercise('Incline DB');

    final session = await wdao.startSession(d.id);
    await wdao.upsertOverride(
      sessionId: session.id,
      programExerciseId: pe.id,
      exerciseId: alt.id,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 30,
    );
    expect((await wdao.overridesForSession(session.id)).length, 1);

    // Direct DELETE on workout_sessions should cascade-clear the override.
    await db.delete('workout_sessions',
        where: 'id = ?', whereArgs: [session.id]);
    expect((await wdao.overridesForSession(session.id)).length, 0);

    await db.close();
  });

  test('session exercise overrides: skipped flag persists and round-trips',
      () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Push A');
    final pe = await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Lateral Raise',
      targetSets: 3,
      targetRepsMin: 12,
      targetRepsMax: 15,
      defaultWeightKg: 10,
    );
    final ex = await pdao.findOrCreateExercise('Lateral Raise');
    final session = await wdao.startSession(d.id);

    // Default is not-skipped.
    await wdao.upsertOverride(
      sessionId: session.id,
      programExerciseId: pe.id,
      exerciseId: ex.id,
      targetSets: 3,
      targetRepsMin: 12,
      targetRepsMax: 15,
      defaultWeightKg: 10,
    );
    expect((await wdao.overridesForSession(session.id)).first.skipped, false);

    // Skipping updates the same row (UNIQUE per slot), preserves the exercise
    // and targets, and reads back as skipped.
    await wdao.upsertOverride(
      sessionId: session.id,
      programExerciseId: pe.id,
      exerciseId: ex.id,
      targetSets: 3,
      targetRepsMin: 12,
      targetRepsMax: 15,
      defaultWeightKg: 10,
      skipped: true,
    );
    final overrides = await wdao.overridesForSession(session.id);
    expect(overrides.length, 1, reason: 'UNIQUE constraint should hold');
    expect(overrides.first.skipped, true);
    expect(overrides.first.exerciseId, ex.id);
    expect(overrides.first.targetSets, 3);

    await db.close();
  });

  test('insertSessionExercise persists an inserted override and round-trips',
      () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Pull A');
    final ex = await pdao.findOrCreateExercise('Face Pull');
    final session = await wdao.startSession(d.id);

    final peId = await wdao.insertSessionExercise(
      sessionId: session.id,
      exerciseId: ex.id,
      targetSets: 4,
      targetRepsMin: 12,
      targetRepsMax: 20,
      defaultWeightKg: 15,
      orderPos: 1.5,
    );
    expect(peId, isNotEmpty);

    final overrides = await wdao.overridesForSession(session.id);
    expect(overrides.length, 1);
    final o = overrides.first;
    expect(o.inserted, true);
    expect(o.orderPos, 1.5);
    expect(o.programExerciseId, peId);
    expect(o.exerciseId, ex.id);
    expect(o.exerciseName, 'Face Pull');
    expect(o.targetSets, 4);
    expect(o.skipped, false);

    // Mutating the inserted slot (e.g. add a set) via the same upsert path must
    // preserve its inserted flag + order position.
    await wdao.upsertOverride(
      sessionId: session.id,
      programExerciseId: peId,
      exerciseId: ex.id,
      targetSets: 5,
      targetRepsMin: 12,
      targetRepsMax: 20,
      defaultWeightKg: 15,
      inserted: true,
      orderPos: 1.5,
    );
    final after = await wdao.overridesForSession(session.id);
    expect(after.length, 1, reason: 'still one row (UNIQUE per slot)');
    expect(after.first.targetSets, 5);
    expect(after.first.inserted, true);
    expect(after.first.orderPos, 1.5);

    await db.close();
  });

  test('summary program-sync: raise target weight + add new exercise at end',
      () async {
    final db = await _openInMemory();
    final dao = ProgramDao(db);
    final p = await dao.createProgram('PPL');
    final d = await dao.createDay(p.id, 'Push A');
    final bench = await dao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 80,
    );

    // "Raise target": update the plan slot's default weight to a session PR.
    await dao.updateProgramExercise(bench.copyWith(defaultWeightKg: 92.5));
    var list = await dao.listProgramExercises(d.id);
    expect(list.single.pe.defaultWeightKg, 92.5);
    expect(list.single.pe.targetRepsMin, 5, reason: 'reps untouched');

    // "Add to this day": an off-plan exercise becomes a new slot at the end.
    final added = await dao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Cable Fly',
      targetSets: 4,
      targetRepsMin: 12,
      targetRepsMax: 15,
      defaultWeightKg: 20,
    );
    list = await dao.listProgramExercises(d.id);
    expect(list.length, 2);
    expect(list.last.exerciseName, 'Cable Fly');
    expect(list.last.pe.position, 1, reason: 'appended after Bench');

    // UNDO of add removes exactly that slot.
    await dao.deleteProgramExercise(added.id);
    list = await dao.listProgramExercises(d.id);
    expect(list.length, 1);
    expect(list.single.exerciseName, 'Bench Press');

    await db.close();
  });

  test('drop sets: program drop_count + grouped workout_sets round-trip',
      () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Pull A');
    final pe = await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Lateral Raise',
      targetSets: 3,
      targetRepsMin: 12,
      targetRepsMax: 15,
      defaultWeightKg: 12,
      dropCount: 2,
    );
    expect(pe.dropCount, 2);
    final reloaded = await pdao.listProgramExercises(d.id);
    expect(reloaded.single.pe.dropCount, 2);

    final ex = await pdao.findOrCreateExercise('Lateral Raise');
    final session = await wdao.startSession(d.id);

    // Log one drop set as a group of 3 rows sharing a set_group.
    const groupId = 'grp-1';
    for (var i = 0; i < 3; i++) {
      await wdao.insertSet(
        sessionId: session.id,
        exerciseId: ex.id,
        setIndex: i,
        reps: 12 - i,
        weightKg: 12 - i * 2,
        rir: i == 0 ? 1 : 0,
        setGroup: groupId,
        groupSeq: i,
      );
    }
    // Plus a plain set (singleton group).
    await wdao.insertSet(
      sessionId: session.id,
      exerciseId: ex.id,
      setIndex: 3,
      reps: 10,
      weightKg: 12,
      rir: 0,
    );

    final sets = await wdao.setsForSession(session.id);
    expect(sets.length, 4);
    final grouped = sets.where((s) => s.setGroup == groupId).toList();
    expect(grouped.length, 3);
    expect(grouped.map((s) => s.groupSeq).toList(), [0, 1, 2]);
    // Distinct group keys = 2 (one drop set + one plain set).
    expect(sets.map((s) => s.groupKey).toSet().length, 2);
    // The plain set's group key is its own id.
    final plain = sets.firstWhere((s) => s.setGroup == null);
    expect(plain.groupKey, plain.id);

    await db.close();
  });

  test('PrDetector detects rep PR at same weight', () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);

    final p = await pdao.createProgram('PPL');
    final d = await pdao.createDay(p.id, 'Push A');
    await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench',
      targetSets: 1,
      targetRepsMin: 5,
      targetRepsMax: 10,
      defaultWeightKg: 80,
    );
    final ex = (await pdao.listExercises()).first;

    // Prior session: 80kg x 6
    final s1 = await wdao.startSession(d.id);
    await wdao.insertSet(
        sessionId: s1.id,
        exerciseId: ex.id,
        setIndex: 0,
        reps: 6,
        weightKg: 80,
        rir: 2);
    await wdao.completeSession(s1.id);
    await Future.delayed(const Duration(milliseconds: 2));

    // New session: 80kg x 8 (same weight, more reps → rep PR)
    final s2 = await wdao.startSession(d.id);
    await wdao.insertSet(
        sessionId: s2.id,
        exerciseId: ex.id,
        setIndex: 0,
        reps: 8,
        weightKg: 80,
        rir: 1);
    await wdao.completeSession(s2.id);

    final prs = await PrDetector(wdao).detect(s2.id);
    expect(prs[ex.id]?.kind, PrKind.reps);
    expect(prs[ex.id]?.reps, 8);

    await db.close();
  });
}
