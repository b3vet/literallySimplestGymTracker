import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/database.dart';
import 'package:ls_workout_tracker/core/db/maintenance.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-14 DB v7: `program_exercise_variants`. The migration is additive and
/// must survive being re-run: Berke flips between the App Store build (1.4.1,
/// v6) and TestFlight builds, and sqflite rewrites `user_version` back to 6
/// without a hook when the older build opens the file.
int? firstIntValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? null : (rows.first.values.first as num?)?.toInt();

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lsgt_v7_');
    path = p.join(dir.path, 'simple_gym.db');
  });
  tearDown(() async => dir.delete(recursive: true));

  /// Open [path] the way 1.4.1 does: schema v1…v6 only.
  Future<Database> openAsV6() => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 6,
      onConfigure: configureDatabase,
      onCreate: (db, _) async {
        for (final step in [
          schemaV1,
          schemaV2Up,
          schemaV3Up,
          schemaV4Up,
          schemaV5Up,
          schemaV6Up,
        ]) {
          for (final stmt in step) {
            await db.execute(stmt);
          }
        }
      },
    ),
  );

  /// Open [path] the way 1.5.0 does.
  Future<Database> openAsCurrent() => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: kDbVersion,
      onConfigure: configureDatabase,
      onCreate: (db, _) => createSchema(db),
      onUpgrade: upgradeSchema,
    ),
  );

  Future<bool> hasVariantsTable(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name IN "
      "('program_exercise_variants', 'idx_pev_pe')",
    );
    return rows.length == 2;
  }

  Future<Map<String, int>> counts(Database db) async => {
    for (final t in [
      'exercises',
      'programs',
      'program_days',
      'program_exercises',
      'workout_sessions',
      'workout_sets',
      'session_exercise_overrides',
    ])
      t: firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t'))!,
  };

  /// A realistic v6 file: program, day, slot, a completed session with a
  /// drop set and a swap override.
  Future<void> seedV6(Database db) async {
    final pDao = ProgramDao(db);
    final wDao = WorkoutDao(db);
    final prog = await pDao.createProgram('PPL');
    final day = await pDao.createDay(prog.id, 'Push');
    final pe = await pDao.addProgramExercise(
      programDayId: day.id,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 80,
      weightStepKg: 2.5,
      dropCount: 1,
    );
    final swap = await pDao.findOrCreateExercise('Machine Press');
    final s = await wDao.startSession(day.id);
    await wDao.insertSet(
      sessionId: s.id,
      exerciseId: pe.exerciseId,
      setIndex: 0,
      reps: 5,
      weightKg: 80,
      rir: 1,
      setGroup: 'g1',
    );
    await wDao.insertSet(
      sessionId: s.id,
      exerciseId: pe.exerciseId,
      setIndex: 1,
      reps: 8,
      weightKg: 60,
      rir: 0,
      setGroup: 'g1',
      groupSeq: 1,
    );
    await wDao.upsertOverride(
      sessionId: s.id,
      programExerciseId: pe.id,
      exerciseId: swap.id,
      previousExerciseId: pe.exerciseId,
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 50,
      dropCount: 1,
    );
    await wDao.completeSession(s.id);
  }

  test('a fresh database has the table and its index', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    expect(await hasVariantsTable(db), isTrue);
    expect(await db.getVersion(), 7);
  });

  test('v6 → v7 keeps every row and adds the table', () async {
    final v6 = await openAsV6();
    await seedV6(v6);
    final before = await counts(v6);
    expect(await hasVariantsTable(v6), isFalse);
    await v6.close();

    final v7 = await openAsCurrent();
    expect(await v7.getVersion(), 7);
    expect(await hasVariantsTable(v7), isTrue);
    expect(await counts(v7), before);
    final slot = (await v7.query('program_exercises')).single;
    expect(slot['weight_step'], 2.5);
    expect(slot['drop_count'], 1);
    await v7.close();
  });

  test('downgrade to 1.4.1 and back re-runs v7 without failing', () async {
    final first = await openAsCurrent();
    await seedV6(first);
    final slotId = (await first.query('program_exercises')).single['id'];
    final exId = (await ProgramDao(first).findOrCreateExercise('DB Press')).id;
    await first.insert('program_exercise_variants', {
      'id': 'v1',
      'program_exercise_id': slotId,
      'exercise_id': exId,
      'position': 0,
      'default_weight': 30,
    });
    await first.close();

    // 1.4.1 opens the file (no onDowngrade, like the app): sqflite rewrites
    // user_version to 6 and leaves the table in place.
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 6, onConfigure: configureDatabase),
    );
    expect(await old.getVersion(), 6);
    await old.close();

    // Back on 1.5.0: onUpgrade(6 → 7) runs the v7 step again.
    final again = await openAsCurrent();
    expect(await again.getVersion(), 7);
    final variants = await again.query('program_exercise_variants');
    expect(variants.single['id'], 'v1', reason: 'the variant survived');
    await again.close();
  });

  test('a user_version forced back to 6 reopens cleanly', () async {
    final db = await openAsCurrent();
    await db.setVersion(6);
    await db.close();
    final reopened = await openAsCurrent();
    expect(await reopened.getVersion(), 7);
    expect(await hasVariantsTable(reopened), isTrue);
    await reopened.close();
  });

  group('on a v7 database', () {
    late Database db;
    late String slotId;
    late String exId;

    setUp(() async {
      db = await openTestDb();
      await seedV6(db);
      slotId = (await db.query('program_exercises')).single['id'] as String;
      exId = (await ProgramDao(db).findOrCreateExercise('DB Press')).id;
      await db.insert('program_exercise_variants', {
        'id': 'v1',
        'program_exercise_id': slotId,
        'exercise_id': exId,
        'position': 0,
        'default_weight': 30,
      });
    });
    tearDown(() async => db.close());

    test('deleting the slot cascades its variants', () async {
      await ProgramDao(db).deleteProgramExercise(slotId);
      expect(await db.query('program_exercise_variants'), isEmpty);
    });

    test('a slot cannot hold the same variant twice', () async {
      await expectLater(
        db.insert('program_exercise_variants', {
          'id': 'v2',
          'program_exercise_id': slotId,
          'exercise_id': exId,
          'position': 1,
          'default_weight': 32,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('wipeAllData empties everything, variants included', () async {
      await wipeAllData(db);
      expect(await db.query('program_exercise_variants'), isEmpty);
      expect(await db.query('exercises'), isEmpty);
    });
  });
}
