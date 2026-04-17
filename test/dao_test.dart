import 'package:flutter_test/flutter_test.dart';
import 'package:literally_simplest_gym_tracker/core/db/migrations.dart';
import 'package:literally_simplest_gym_tracker/features/programs/data/program_dao.dart';
import 'package:literally_simplest_gym_tracker/features/workout/application/pr_detector.dart';
import 'package:literally_simplest_gym_tracker/features/workout/data/workout_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async =>
            db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final b = db.batch();
          for (final stmt in schemaV1) {
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
