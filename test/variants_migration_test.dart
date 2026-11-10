import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/database.dart';
import 'package:ls_workout_tracker/core/db/maintenance.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/domain/program_exercise.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-14 DB v7: `program_exercise_variants`; v8 (D-0016): its prescription
/// columns. Both are additive and must survive being re-run: Berke flips
/// between the App Store build (1.4.1, v6), TestFlight 1.5.0 (13, v7) and this
/// build, and sqflite rewrites `user_version` without a hook when an older
/// build opens the file.
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
    // Written as 1.4.1 writes it: the 1.5.0 DAO consults the v7 variants
    // table (SOW-14 day rule), which a v6 file doesn't have.
    final bench = await pDao.findOrCreateExercise('Bench Press');
    final pe = ProgramExercise(
      id: 'pe-v6',
      programDayId: day.id,
      exerciseId: bench.id,
      position: 0,
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 80,
      weightStepKg: 2.5,
      dropCount: 1,
    );
    await db.insert('program_exercises', pe.toRow());
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
    expect(await db.getVersion(), kDbVersion);
  });

  test('v6 → v7 keeps every row and adds the table', () async {
    final v6 = await openAsV6();
    await seedV6(v6);
    final before = await counts(v6);
    expect(await hasVariantsTable(v6), isFalse);
    await v6.close();

    final v7 = await openAsCurrent();
    expect(await v7.getVersion(), kDbVersion);
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
    expect(await again.getVersion(), kDbVersion);
    final variants = await again.query('program_exercise_variants');
    expect(variants.single['id'], 'v1', reason: 'the variant survived');
    await again.close();
  });

  test('a user_version forced back to 6 reopens cleanly', () async {
    final db = await openAsCurrent();
    await db.setVersion(6);
    await db.close();
    final reopened = await openAsCurrent();
    expect(await reopened.getVersion(), kDbVersion);
    expect(await hasVariantsTable(reopened), isTrue);
    await reopened.close();
  });

  // ---------- v8: the variant's own prescription (D-0016) ----------

  /// `program_exercise_variants` exactly as 1.5.0 (13) created it: no
  /// prescription columns.
  const build13V7 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS program_exercise_variants (
      id TEXT PRIMARY KEY,
      program_exercise_id TEXT NOT NULL
        REFERENCES program_exercises(id) ON DELETE CASCADE,
      exercise_id TEXT NOT NULL REFERENCES exercises(id),
      position INTEGER NOT NULL,
      default_weight REAL NOT NULL,
      weight_step REAL,
      UNIQUE (program_exercise_id, exercise_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_pev_pe '
        'ON program_exercise_variants(program_exercise_id, position)',
  ];

  /// Open [path] the way 1.5.0 (13) does: v1…v6 + its v7, no v8. Like the app
  /// it has no `onDowngrade`, so a newer file is just stamped back to 7.
  Future<Database> openAsBuild13() => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 7,
      onConfigure: configureDatabase,
      onCreate: (db, _) async {
        for (final step in [
          schemaV1,
          schemaV2Up,
          schemaV3Up,
          schemaV4Up,
          schemaV5Up,
          schemaV6Up,
          build13V7,
        ]) {
          for (final stmt in step) {
            await db.execute(stmt);
          }
        }
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 7) {
          for (final stmt in build13V7) {
            await db.execute(stmt);
          }
        }
      },
    ),
  );

  Future<List<String>> variantColumns(Database db) async => [
    for (final c in await db.rawQuery(
      'PRAGMA table_info(program_exercise_variants)',
    ))
      c['name'] as String,
  ];

  /// A build-13 file with a slot (3 × 5-8, 1 drop) and two variants written
  /// the way build 13 writes them (no prescription columns).
  Future<String> seedBuild13(Database db) async {
    await seedV6(db);
    final slotId = (await db.query('program_exercises')).single['id'] as String;
    final dao = ProgramDao(db);
    for (final (i, name, kg) in [
      (0, 'DB Press', 30.0),
      (1, 'Smith Press', 70.0),
    ]) {
      await db.insert('program_exercise_variants', {
        'id': 'v$i',
        'program_exercise_id': slotId,
        'exercise_id': (await dao.findOrCreateExercise(name)).id,
        'position': i,
        'default_weight': kg,
        'weight_step': i == 0 ? 2.0 : null,
      });
    }
    return slotId;
  }

  test('build 13 (v7) → v8 adds the columns, keeps every variant, NULLs '
      'inherit from the slot', () async {
    final b13 = await openAsBuild13();
    final slotId = await seedBuild13(b13);
    expect(await variantColumns(b13), isNot(contains('target_sets')));
    final before = await b13.query('program_exercise_variants', orderBy: 'id');
    final rowsBefore = await counts(b13);
    await b13.close();

    final v8 = await openAsCurrent();
    expect(await v8.getVersion(), kDbVersion);
    expect(
      await variantColumns(v8),
      containsAll(variantPrescriptionColumns.keys),
    );
    expect(await counts(v8), rowsBefore);
    final after = await v8.query('program_exercise_variants', orderBy: 'id');
    expect(after.length, 2);
    for (var i = 0; i < 2; i++) {
      for (final k in before[i].keys) {
        expect(after[i][k], before[i][k], reason: 'v$i.$k preserved');
      }
      for (final k in variantPrescriptionColumns.keys) {
        expect(after[i][k], isNull, reason: 'v$i.$k inherits');
      }
    }

    final slot = (await ProgramDao(v8).listProgramExercises(
      (await v8.query('program_days')).single['id'] as String,
    )).single.pe;
    final views = await ProgramDao(v8).listVariants(slotId);
    expect(views.map((v) => v.exerciseName), ['DB Press', 'Smith Press']);
    final db = views.first.variant.resolvedOn(slot);
    expect(db.targetSets, 3);
    expect(db.targetRepsMin, 5);
    expect(db.targetRepsMax, 8);
    expect(db.dropCount, 1);
    expect(db.defaultWeightKg, 30);
    expect(db.weightStepKg, 2.0);
    expect(
      views.last.variant.resolvedOn(slot).weightStepKg,
      2.5,
      reason: 'a NULL step still falls back to the slot',
    );
    await v8.close();
  });

  test(
    'v8 survives every downgrade reset: 1.4.1 (v6) and build 13 (v7)',
    () async {
      final first = await openAsCurrent();
      final slotId = await seedBuild13(first);
      await ProgramDao(first).editVariant(
        id: 'v0',
        exerciseName: 'DB Press',
        defaultWeightKg: 32,
        weightStepKg: 2,
        targetSets: 4,
        targetRepsMin: 6,
        targetRepsMax: 8,
        dropCount: 0,
      );
      final shape = await variantColumns(first);
      await first.close();

      for (final older in [6, 7]) {
        // The older build opens the file (no onDowngrade, like the app):
        // sqflite stamps its version and leaves the table as it is.
        final old = await databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: older,
            onConfigure: configureDatabase,
          ),
        );
        expect(await old.getVersion(), older);
        if (older == 7) {
          // Build 13 keeps writing variants without the new columns.
          await old.insert('program_exercise_variants', {
            'id': 'v-b13',
            'program_exercise_id': slotId,
            'exercise_id': (await ProgramDao(
              old,
            ).findOrCreateExercise('Cable Press')).id,
            'position': 9,
            'default_weight': 20,
          });
        }
        await old.close();

        // Back on this build: v7 (and v8) run again — no duplicate-column error.
        final again = await openAsCurrent();
        expect(await again.getVersion(), kDbVersion);
        expect(await variantColumns(again), shape, reason: 'after v$older');
        final v0 = (await again.query(
          'program_exercise_variants',
          where: 'id = ?',
          whereArgs: ['v0'],
        )).single;
        expect(
          [v0['target_sets'], v0['rep_min'], v0['rep_max'], v0['drop_count']],
          [4, 6, 8, 0],
          reason: 'explicit values survive the v$older round trip',
        );
        expect(v0['default_weight'], 32);
        await again.close();
      }
      final last = await openAsCurrent();
      final b13Row = (await last.query(
        'program_exercise_variants',
        where: 'id = ?',
        whereArgs: ['v-b13'],
      )).single;
      expect(b13Row['target_sets'], isNull, reason: 'written by 13: inherits');
      await last.close();
    },
  );

  test(
    'fresh create has the columns in the table; v8 is a no-op on it',
    () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final cols = await variantColumns(db);
      expect(cols, containsAll(variantPrescriptionColumns.keys));
      final sql =
          (await db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE name = 'program_exercise_variants'",
              )).single['sql']
              as String;
      expect(sql, contains('rep_min'), reason: 'created directly, not ALTERed');
      await schemaV8Up(db);
      await schemaV8Up(db);
      expect(await variantColumns(db), cols);
    },
  );

  test('wipeAllData works on a file upgraded from build 13', () async {
    final b13 = await openAsBuild13();
    await seedBuild13(b13);
    await b13.close();
    final v8 = await openAsCurrent();
    await wipeAllData(v8);
    expect(await v8.query('program_exercise_variants'), isEmpty);
    expect(await v8.query('program_exercises'), isEmpty);
    expect(await v8.query('exercises'), isEmpty);
    await v8.close();
  });

  // ---------- v9: the exercises a slot ran (D-0016 review #1) ----------

  Future<List<String>> overrideColumns(Database db) async => [
    for (final c in await db.rawQuery(
      'PRAGMA table_info(session_exercise_overrides)',
    ))
      c['name'] as String,
  ];

  test('v9 adds ran_exercise_ids to overrides; every reset (6, 7, and 8 — '
      'build 14) re-runs it as a no-op and keeps the ids', () async {
    // A file as build 14 left it (v8, no column), with a v8 override row.
    final b13 = await openAsBuild13();
    await seedV6(b13);
    await b13.close();
    final v8 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onConfigure: configureDatabase,
        onUpgrade: (db, _, _) => schemaV8Up(db),
      ),
    );
    expect(await overrideColumns(v8), isNot(contains('ran_exercise_ids')));
    await v8.close();

    final first = await openAsCurrent();
    expect(await first.getVersion(), kDbVersion);
    expect(await overrideColumns(first), contains('ran_exercise_ids'));
    final o = (await WorkoutDao(first).overridesForSession(
      (await first.query('workout_sessions')).single['id'] as String,
    )).single;
    expect(o.ranExerciseIds, isEmpty, reason: 'a v8 row: NULL reads as none');
    await WorkoutDao(first).upsertOverride(
      sessionId: o.sessionId,
      programExerciseId: o.programExerciseId,
      exerciseId: o.exerciseId,
      previousExerciseId: o.previousExerciseId,
      targetSets: o.targetSets,
      targetRepsMin: o.targetRepsMin,
      targetRepsMax: o.targetRepsMax,
      defaultWeightKg: o.defaultWeightKg,
      dropCount: o.dropCount,
      ranExerciseIds: [o.previousExerciseId!, o.exerciseId],
    );
    final shape = await overrideColumns(first);
    await first.close();

    for (final older in [6, 7, 8]) {
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: older,
          onConfigure: configureDatabase,
        ),
      );
      expect(await old.getVersion(), older);
      await old.close();
      final again = await openAsCurrent();
      expect(await again.getVersion(), kDbVersion);
      expect(await overrideColumns(again), shape, reason: 'after v$older');
      expect(
        (await WorkoutDao(again).overridesForSession(o.sessionId))
            .single
            .ranExerciseIds,
        [o.previousExerciseId, o.exerciseId],
        reason: 'the ids survive the v$older round trip',
      );
      await again.close();
    }

    final db = await openTestDb();
    addTearDown(db.close);
    final cols = await overrideColumns(db);
    expect(cols, contains('ran_exercise_ids'), reason: 'fresh install');
    await schemaV9Up(db);
    await schemaV9Up(db);
    expect(await overrideColumns(db), cols);
  });

  test('upsertOverride only ever adds to ran_exercise_ids', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    await seedV6(db);
    final dao = WorkoutDao(db);
    final sessionId =
        (await db.query('workout_sessions')).single['id'] as String;
    final o = (await dao.overridesForSession(sessionId)).single;
    Future<void> write(List<String> ran) => dao.upsertOverride(
      sessionId: sessionId,
      programExerciseId: o.programExerciseId,
      exerciseId: o.exerciseId,
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 50,
      ranExerciseIds: ran,
    );
    Future<List<String>> read() async =>
        (await dao.overridesForSession(sessionId)).single.ranExerciseIds;

    await write(['a', 'b']);
    expect(await read(), ['a', 'b']);
    await write(['b', 'c']);
    expect(await read(), ['a', 'b', 'c']);
    await write(const []); // e.g. a skip that doesn't know the chain
    expect(await read(), ['a', 'b', 'c']);
    await db.update('session_exercise_overrides', {
      'ran_exercise_ids': 'not json',
    });
    expect(await read(), isEmpty, reason: 'unreadable counts as none');
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
