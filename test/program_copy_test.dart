import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/domain/program_exercise.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-13: copying a program or a day is a deep, independent copy that shares
/// the exercise library (so history follows the movement into the copy).
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;

  setUp(() async {
    db = await openTestDb();
    dao = ProgramDao(db);
  });
  tearDown(() async => db.close());

  /// PPL-ish program: two days, varied targets, a weight step and a drop set.
  Future<String> seed() async {
    final p = await dao.createProgram('Strength');
    final push = await dao.createDay(p.id, 'Push');
    final pull = await dao.createDay(p.id, 'Pull');
    await dao.addProgramExercise(
      programDayId: push.id,
      exerciseName: 'Bench Press',
      targetSets: 4,
      targetRepsMin: 5,
      targetRepsMax: 5,
      defaultWeightKg: 90,
      weightStepKg: 2.5,
    );
    await dao.addProgramExercise(
      programDayId: push.id,
      exerciseName: 'Lateral Raise',
      targetSets: 3,
      targetRepsMin: 12,
      targetRepsMax: 15,
      defaultWeightKg: 10,
      dropCount: 2,
    );
    await dao.addProgramExercise(
      programDayId: pull.id,
      exerciseName: 'Barbell Row',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
      defaultWeightKg: 70,
    );
    return p.id;
  }

  /// Everything about a slot except its own ids.
  List<Object?> shape(ProgramExerciseView v) => [
    v.exerciseName,
    v.pe.exerciseId,
    v.pe.position,
    v.pe.targetSets,
    v.pe.targetRepsMin,
    v.pe.targetRepsMax,
    v.pe.defaultWeightKg,
    v.pe.weightStepKg,
    v.pe.dropCount,
  ];

  Future<List<Object?>> programShape(String programId) async {
    final out = <Object?>[];
    for (final d in await dao.listDays(programId)) {
      out.add([d.name, d.position]);
      for (final v in await dao.listProgramExercises(d.id)) {
        out.add(shape(v));
      }
    }
    return out;
  }

  Future<Set<String>> idsOf(String programId) async {
    final ids = <String>{programId};
    for (final d in await dao.listDays(programId)) {
      ids.add(d.id);
      for (final v in await dao.listProgramExercises(d.id)) {
        ids.add(v.pe.id);
      }
    }
    return ids;
  }

  group('duplicateProgram', () {
    test('copies the whole structure under new ids, same exercises', () async {
      final original = await seed();
      final exercisesBefore = (await dao.listExercises()).length;

      final copy = await dao.duplicateProgram(
        original,
        name: ' Strength COPY ',
      );

      expect(copy.name, 'Strength COPY', reason: 'name is trimmed');
      expect(await programShape(copy.id), await programShape(original));
      final shared = (await idsOf(copy.id)).intersection(await idsOf(original));
      expect(shared, isEmpty, reason: 'every program/day/slot id is new');
      expect(
        (await dao.listExercises()).length,
        exercisesBefore,
        reason: 'the exercise library is shared, not duplicated',
      );
      expect((await dao.listPrograms()).length, 2);
    });

    test('editing or deleting the copy leaves the original alone', () async {
      final original = await seed();
      final before = await programShape(original);
      final copy = await dao.duplicateProgram(original, name: 'B');

      final copyDays = await dao.listDays(copy.id);
      final slots = await dao.listProgramExercises(copyDays.first.id);
      await dao.updateProgramExercise(
        slots.first.pe.copyWith(defaultWeightKg: 120, targetSets: 6),
      );
      await dao.deleteProgramExercise(slots.last.pe.id);
      await dao.renameDay(copyDays.first.id, 'Push Heavy');
      expect(await programShape(original), before);

      await dao.deleteProgram(copy.id);
      expect(await programShape(original), before);
    });

    test('an empty program copies', () async {
      final p = await dao.createProgram('Empty');
      final copy = await dao.duplicateProgram(p.id, name: 'Empty COPY');
      expect(await dao.listDays(copy.id), isEmpty);
      expect((await dao.listPrograms()).length, 2);
    });
  });

  group('variants (SOW-14)', () {
    Future<List<Object?>> variantShape(String dayId) async {
      final out = <Object?>[];
      final byslot = await dao.listVariantsForDay(dayId);
      for (final v in await dao.listProgramExercises(dayId)) {
        for (final x in byslot[v.pe.id] ?? const []) {
          out.add([
            v.exerciseName,
            x.exerciseName,
            x.variant.exerciseId,
            x.variant.position,
            x.variant.defaultWeightKg,
            x.variant.weightStepKg,
          ]);
        }
      }
      return out;
    }

    Future<String> seedWithVariants() async {
      final programId = await seed();
      final push = (await dao.listDays(programId)).first;
      final bench = (await dao.listProgramExercises(push.id)).first;
      await dao.addVariant(
        programExerciseId: bench.pe.id,
        exerciseName: 'Machine Press',
        defaultWeightKg: 70,
        weightStepKg: 5,
      );
      await dao.addVariant(
        programExerciseId: bench.pe.id,
        exerciseName: 'DB Bench',
        defaultWeightKg: 32,
      );
      return programId;
    }

    test('a program copy carries every variant, independently', () async {
      final original = await seedWithVariants();
      final origPush = (await dao.listDays(original)).first;
      final before = await variantShape(origPush.id);
      expect(before.length, 2);

      final copy = await dao.duplicateProgram(original, name: 'C');
      final copyPush = (await dao.listDays(copy.id)).first;
      expect(await variantShape(copyPush.id), before);

      final copySlot = (await dao.listProgramExercises(copyPush.id)).first;
      final copyVariants = await dao.listVariants(copySlot.pe.id);
      final origSlot = (await dao.listProgramExercises(origPush.id)).first;
      final origVariants = await dao.listVariants(origSlot.pe.id);
      expect(
        copyVariants
            .map((v) => v.variant.id)
            .toSet()
            .intersection(origVariants.map((v) => v.variant.id).toSet()),
        isEmpty,
        reason: 'variant ids are new',
      );

      await dao.deleteVariant(copyVariants.first.variant.id);
      await dao.updateVariant(
        copyVariants.last.variant.copyWith(defaultWeightKg: 99),
      );
      expect(await variantShape(origPush.id), before);
    });

    test('a day copy carries its variants', () async {
      final programId = await seedWithVariants();
      final push = (await dao.listDays(programId)).first;
      final copy = await dao.duplicateDay(push.id, name: 'Push COPY');
      expect(await variantShape(copy.id), await variantShape(push.id));
    });

    // SOW-14 day rule: a day that already breaks it (written before the rule)
    // is copied clean — the conflicting variants are not carried over.
    test('a copy drops variants that break the day rule', () async {
      final programId = await seedWithVariants();
      final push = (await dao.listDays(programId)).first;
      final slots = await dao.listProgramExercises(push.id);
      final bench = slots.first;
      final machine = (await dao.listVariants(bench.pe.id)).first;
      Future<void> raw(String slotId, String exerciseId, int pos) =>
          db.insert('program_exercise_variants', {
            'id': 'raw-$pos',
            'program_exercise_id': slotId,
            'exercise_id': exerciseId,
            'position': pos,
            'default_weight': 10.0,
            'weight_step': null,
          });
      await raw(bench.pe.id, bench.pe.exerciseId, 7); // = its own base
      await raw(slots[1].pe.id, machine.variant.exerciseId, 0); // shared

      final copy = await dao.duplicateDay(push.id, name: 'Push COPY');
      final copied = await db.rawQuery(
        'SELECT v.exercise_id FROM program_exercise_variants v '
        'JOIN program_exercises pe ON pe.id = v.program_exercise_id '
        'WHERE pe.program_day_id = ?',
        [copy.id],
      );
      expect(copied, hasLength(2), reason: 'Machine Press + DB Bench only');
      expect(await variantShape(copy.id), await variantShape(push.id));

      final progCopy = await dao.duplicateProgram(programId, name: 'C');
      final copyPush = (await dao.listDays(progCopy.id)).first;
      expect(await variantShape(copyPush.id), await variantShape(push.id));
    });
  });

  group('duplicateDay', () {
    test('appends a deep copy to the same program', () async {
      final programId = await seed();
      final push = (await dao.listDays(programId)).first;

      final copy = await dao.duplicateDay(push.id, name: 'Push COPY');

      final days = await dao.listDays(programId);
      expect(days.map((d) => d.name), ['Push', 'Pull', 'Push COPY']);
      expect(copy.programId, programId);
      final a = await dao.listProgramExercises(push.id);
      final b = await dao.listProgramExercises(copy.id);
      expect(b.map(shape), a.map(shape));
      expect(
        b
            .map((v) => v.pe.id)
            .toSet()
            .intersection(a.map((v) => v.pe.id).toSet()),
        isEmpty,
      );
    });

    test('lands after the last day even when positions have a gap', () async {
      final programId = await seed();
      final days = await dao.listDays(programId);
      await dao.createDay(programId, 'Legs'); // position 2
      await dao.deleteDay(days.first.id); // positions now 1, 2
      final copy = await dao.duplicateDay(days.last.id, name: 'Pull COPY');
      expect((await dao.listDays(programId)).last.id, copy.id);
    });

    test('editing the copy leaves the original day alone', () async {
      final programId = await seed();
      final push = (await dao.listDays(programId)).first;
      final before = (await dao.listProgramExercises(
        push.id,
      )).map(shape).toList();
      final copy = await dao.duplicateDay(push.id, name: 'X');
      final slot = (await dao.listProgramExercises(copy.id)).first;
      await dao.updateProgramExercise(slot.pe.copyWith(defaultWeightKg: 1));
      await dao.deleteDay(copy.id);
      expect((await dao.listProgramExercises(push.id)).map(shape), before);
    });

    test('an empty day copies', () async {
      final p = await dao.createProgram('P');
      final d = await dao.createDay(p.id, 'Rest');
      final copy = await dao.duplicateDay(d.id, name: 'Rest COPY');
      expect(await dao.listProgramExercises(copy.id), isEmpty);
      expect((await dao.listDays(p.id)).length, 2);
    });
  });
}
