import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../main.dart' show databaseProvider;
import '../../programs/domain/exercise.dart';
import '../../programs/domain/program.dart';
import '../../programs/domain/program_day.dart';
import '../../programs/domain/program_exercise.dart';
import 'program_templates.dart';

/// Seeds a [ProgramTemplate] into the database as a real, editable program.
///
/// All inserts run inside a single `transaction`, so a process kill mid-seed
/// can never leave a half-built program (e.g. 2 of 3 days). Either the whole
/// program lands or none of it does — which is exactly what the onboarding
/// completion gate relies on (the flag is only set after this resolves).
class TemplateSeeder {
  TemplateSeeder(this._db);
  final Database _db;
  static const _uuid = Uuid();

  /// Inserts [template] and returns the created [Program]. Reuses the programs
  /// feature's own domain models / `toRow()` so the seeded rows are identical
  /// in shape to anything the editor writes — no parallel schema knowledge.
  Future<Program> seed(ProgramTemplate template) async {
    final program = Program(
      id: _uuid.v4(),
      name: template.name.trim(),
      createdAt: DateTime.now(),
    );
    await _db.transaction((txn) async {
      await txn.insert('programs', program.toRow());
      for (var di = 0; di < template.days.length; di++) {
        final tDay = template.days[di];
        final day = ProgramDay(
          id: _uuid.v4(),
          programId: program.id,
          name: tDay.name.trim(),
          position: di,
        );
        await txn.insert('program_days', day.toRow());
        for (var ei = 0; ei < tDay.exercises.length; ei++) {
          final te = tDay.exercises[ei];
          final exercise = await _findOrCreateExercise(txn, te.name);
          final pe = ProgramExercise(
            id: _uuid.v4(),
            programDayId: day.id,
            exerciseId: exercise.id,
            position: ei,
            targetSets: te.sets,
            targetRepsMin: te.repsMin,
            targetRepsMax: te.repsMax,
            defaultWeightKg: te.weightKg,
          );
          await txn.insert('program_exercises', pe.toRow());
        }
      }
    });
    return program;
  }

  /// Transaction-scoped twin of `ProgramDao.findOrCreateExercise`. Exercise
  /// names are `UNIQUE COLLATE NOCASE`, so we look up case-insensitively and
  /// only insert when absent — letting two template days share an exercise
  /// (e.g. Bench Press) without a constraint violation.
  Future<Exercise> _findOrCreateExercise(
      Transaction txn, String name) async {
    final trimmed = name.trim();
    final existing = await txn.query(
      'exercises',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (existing.isNotEmpty) return Exercise.fromRow(existing.first);
    final e = Exercise(id: _uuid.v4(), name: trimmed);
    await txn.insert('exercises', e.toRow());
    return e;
  }
}

final templateSeederProvider = Provider<TemplateSeeder>((ref) {
  return TemplateSeeder(ref.watch(databaseProvider));
});
