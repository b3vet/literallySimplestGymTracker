import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openInMemory() async {
  final factory = databaseFactoryFfi;
  return factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 3,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
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
        await b.commit(noResult: true);
      },
    ),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('listKnownExerciseNames returns sorted, unique names', () async {
    final db = await _openInMemory();
    final dao = ProgramDao(db);
    await dao.findOrCreateExercise('Bench Press');
    await dao.findOrCreateExercise('Squat');
    // Case-insensitive UNIQUE on name should make this a no-op.
    await dao.findOrCreateExercise('bench press');
    final names = await dao.listKnownExerciseNames();
    expect(names, ['Bench Press', 'Squat']);
    await db.close();
  });

  test('mostRecentProgramExerciseForName picks the latest program', () async {
    final db = await _openInMemory();
    final dao = ProgramDao(db);

    final older = await dao.createProgram('Old Plan');
    await Future.delayed(const Duration(milliseconds: 5));
    final newer = await dao.createProgram('New Plan');

    final dOld = await dao.createDay(older.id, 'Push');
    final dNew = await dao.createDay(newer.id, 'Push');

    await dao.addProgramExercise(
      programDayId: dOld.id,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 60,
    );
    await dao.addProgramExercise(
      programDayId: dNew.id,
      exerciseName: 'Bench Press',
      targetSets: 4,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 80,
    );

    final pe = await dao.mostRecentProgramExerciseForName('Bench Press');
    expect(pe, isNotNull);
    expect(pe!.targetSets, 4);
    expect(pe.targetRepsMin, 5);
    expect(pe.defaultWeightKg, 80);

    final missing = await dao.mostRecentProgramExerciseForName('Nope');
    expect(missing, isNull);

    await db.close();
  });

  test('previousCompletedSessionForDay finds prior of same day only',
      () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);
    final p = await pdao.createProgram('Plan');
    final d1 = await pdao.createDay(p.id, 'Push');
    final d2 = await pdao.createDay(p.id, 'Pull');

    final s1 = await wdao.startSession(d1.id);
    await Future.delayed(const Duration(milliseconds: 2));
    await wdao.completeSession(s1.id);

    final s2 = await wdao.startSession(d2.id);
    await Future.delayed(const Duration(milliseconds: 2));
    await wdao.completeSession(s2.id);

    final s3 = await wdao.startSession(d1.id);
    final beforeS3 = s3.startedAt;

    final prev = await wdao.previousCompletedSessionForDay(
      d1.id,
      before: beforeS3,
    );
    expect(prev?.id, s1.id);

    final prevPull = await wdao.previousCompletedSessionForDay(
      d2.id,
      before: beforeS3,
    );
    expect(prevPull?.id, s2.id);

    await db.close();
  });

  test('totalTonnageBySession sums weight*reps and excludes abandoned',
      () async {
    final db = await _openInMemory();
    final pdao = ProgramDao(db);
    final wdao = WorkoutDao(db);
    final p = await pdao.createProgram('Plan');
    final d = await pdao.createDay(p.id, 'Push');
    await pdao.addProgramExercise(
      programDayId: d.id,
      exerciseName: 'Bench',
      targetSets: 1,
      targetRepsMin: 5,
      targetRepsMax: 5,
      defaultWeightKg: 80,
    );
    final ex = (await pdao.listExercises()).first;

    final completed = await wdao.startSession(d.id);
    await wdao.insertSet(
        sessionId: completed.id,
        exerciseId: ex.id,
        setIndex: 0,
        reps: 5,
        weightKg: 80,
        rir: 2);
    await wdao.completeSession(completed.id);

    final abandoned = await wdao.startSession(d.id);
    await wdao.insertSet(
        sessionId: abandoned.id,
        exerciseId: ex.id,
        setIndex: 0,
        reps: 5,
        weightKg: 100,
        rir: 0);
    await wdao.abandonSession(abandoned.id);

    final pts = await wdao.totalTonnageBySession(limit: 8);
    expect(pts.length, 1);
    expect(pts.first.tonnageKg, 80 * 5);
    await db.close();
  });
}
