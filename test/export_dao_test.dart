import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/export/data/export_dao.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _openInMemory() async {
  final factory = databaseFactoryFfi;
  return factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final b = db.batch();
          for (final stmt in [
            ...schemaV1,
            ...schemaV2Up,
            ...schemaV3Up,
            ...schemaV4Up,
            ...schemaV5Up,
            ...schemaV6Up,
          ]) {
            b.execute(stmt);
          }
          await b.commit(noResult: true);
        },
      ));
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('exportAllSessions: completed only, names joined, sets + drop group',
      () async {
    final db = await _openInMemory();
    addTearDown(db.close); // sqflite caches ':memory:' by path — close per test
    final programDao = ProgramDao(db);
    final workoutDao = WorkoutDao(db);

    final program = await programDao.createProgram('PPL');
    final day = await programDao.createDay(program.id, 'Push A');
    final pe = await programDao.addProgramExercise(
      programDayId: day.id,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 80,
    );

    // A completed session: one plain set + a drop-set group (top + drop).
    final done = await workoutDao.startSession(day.id);
    await workoutDao.insertSet(
        sessionId: done.id,
        exerciseId: pe.exerciseId,
        setIndex: 1,
        reps: 8,
        weightKg: 80,
        rir: 2);
    await workoutDao.insertSet(
        sessionId: done.id,
        exerciseId: pe.exerciseId,
        setIndex: 2,
        reps: 6,
        weightKg: 80,
        rir: 0,
        setGroup: 'grp-1',
        groupSeq: 0);
    await workoutDao.insertSet(
        sessionId: done.id,
        exerciseId: pe.exerciseId,
        setIndex: 2,
        reps: 4,
        weightKg: 60,
        rir: 0,
        setGroup: 'grp-1',
        groupSeq: 1);
    await workoutDao.completeSession(done.id);

    // An abandoned and an active session — both must be excluded.
    final abandoned = await workoutDao.startSession(day.id);
    await workoutDao.insertSet(
        sessionId: abandoned.id,
        exerciseId: pe.exerciseId,
        setIndex: 1,
        reps: 5,
        weightKg: 70,
        rir: 1);
    await workoutDao.abandonSession(abandoned.id);
    await workoutDao.startSession(day.id); // left active

    final sessions = await ExportDao(db).exportAllSessions();

    expect(sessions.length, 1, reason: 'only the completed session');
    final s = sessions.single;
    expect(s.id, done.id);
    // import-ready FK ids propagate (SOW-12 reattaches by these, not by name)
    expect(s.programDayId, day.id);
    expect(s.programId, program.id);
    expect(s.programName, 'PPL');
    expect(s.dayName, 'Push A');
    expect(s.sets.length, 3);
    expect(s.sets.every((x) => x.exercise == 'Bench Press'), isTrue);
    expect(s.sets.every((x) => x.exerciseId == pe.exerciseId), isTrue);
    expect(s.sets.every((x) => x.id.isNotEmpty), isTrue,
        reason: 'every set carries a stable id for import dedup');
    final drops = s.sets.where((x) => x.setGroup == 'grp-1').toList();
    expect(drops.length, 2);
    expect(drops.map((x) => x.groupSeq).toList(), [0, 1]);
  });

  test('exportAllSessions: empty completed session survives with no sets',
      () async {
    final db = await _openInMemory();
    addTearDown(db.close);
    final programDao = ProgramDao(db);
    final workoutDao = WorkoutDao(db);
    final program = await programDao.createProgram('P');
    final day = await programDao.createDay(program.id, 'D');
    final empty = await workoutDao.startSession(day.id);
    await workoutDao.completeSession(empty.id);

    final sessions = await ExportDao(db).exportAllSessions();
    expect(sessions.length, 1);
    expect(sessions.single.sets, isEmpty);
  });
}
