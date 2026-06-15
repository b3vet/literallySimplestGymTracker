import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/maintenance.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/onboarding/data/program_templates.dart';
import 'package:ls_workout_tracker/features/onboarding/data/template_seeder.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
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
        for (final stmt in [...schemaV1, ...schemaV2Up, ...schemaV3Up]) {
          b.execute(stmt);
        }
        await b.commit(noResult: true);
      },
    ),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('seeds a template with every day and exercise in order', () async {
    final db = await _openInMemory();
    final seeder = TemplateSeeder(db);
    final dao = ProgramDao(db);
    final tpl = kProgramTemplates.firstWhere((t) => t.id == 'push_pull');

    final program = await seeder.seed(tpl);
    expect(program.name, 'Push Pull Legs');

    final days = await dao.listDays(program.id);
    expect(days.length, tpl.dayCount);

    var total = 0;
    for (var i = 0; i < days.length; i++) {
      expect(days[i].name, tpl.days[i].name);
      final exs = await dao.listProgramExercises(days[i].id);
      expect(exs.length, tpl.days[i].exercises.length);
      // First slot's name / sets / rep-range / weight survive the round trip.
      final te = tpl.days[i].exercises.first;
      expect(exs.first.exerciseName, te.name);
      expect(exs.first.pe.targetSets, te.sets);
      expect(exs.first.pe.targetRepsMin, te.repsMin);
      expect(exs.first.pe.targetRepsMax, te.repsMax);
      expect(exs.first.pe.defaultWeightKg, te.weightKg);
      total += exs.length;
    }
    expect(total, tpl.exerciseCount);
  });

  test('shared exercise names are reused, never duplicated', () async {
    final db = await _openInMemory();
    final seeder = TemplateSeeder(db);
    final dao = ProgramDao(db);

    // Both templates use Bench Press, Back Squat, etc.
    await seeder.seed(kProgramTemplates.firstWhere((t) => t.id == 'push_pull'));
    await seeder.seed(kProgramTemplates.firstWhere((t) => t.id == 'antagonist'));

    final names = (await dao.listExercises()).map((e) => e.name.toLowerCase());
    expect(names.where((n) => n == 'bench press').length, 1);
    expect(names.where((n) => n == 'back squat').length, 1);
  });

  test('every bundled template seeds without error', () async {
    for (final tpl in kProgramTemplates) {
      final db = await _openInMemory();
      final program = await TemplateSeeder(db).seed(tpl);
      final days = await ProgramDao(db).listDays(program.id);
      expect(days.length, tpl.dayCount, reason: tpl.name);
      await db.close();
    }
  });

  test('wipeAllData empties every user table', () async {
    final db = await _openInMemory();
    final dao = ProgramDao(db);
    await TemplateSeeder(db).seed(kProgramTemplates.first);
    expect((await dao.listPrograms()).isNotEmpty, true);
    expect((await dao.listExercises()).isNotEmpty, true);

    await wipeAllData(db);

    expect((await dao.listPrograms()).isEmpty, true);
    expect((await dao.listExercises()).isEmpty, true);
    expect((await db.query('program_days')).isEmpty, true);
    expect((await db.query('program_exercises')).isEmpty, true);
  });
}
