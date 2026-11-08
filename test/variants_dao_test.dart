import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/domain/program_exercise.dart';
import 'package:ls_workout_tracker/features/programs/domain/program_exercise_variant.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-14: variants of a program slot — CRUD and the rules that keep a slot's
/// members unambiguous.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String dayId;
  late ProgramExercise press;
  late ProgramExercise row;

  setUp(() async {
    db = await openTestDb();
    dao = ProgramDao(db);
    final p = await dao.createProgram('P');
    dayId = (await dao.createDay(p.id, 'Upper')).id;
    press = await dao.addProgramExercise(
      programDayId: dayId,
      exerciseName: 'Shoulder Press',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
      defaultWeightKg: 50,
      weightStepKg: 2.5,
    );
    row = await dao.addProgramExercise(
      programDayId: dayId,
      exerciseName: 'Barbell Row',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
      defaultWeightKg: 60,
    );
  });
  tearDown(() async => db.close());

  Future<ProgramExerciseVariant> add(
    String name,
    double kg, {
    String? slot,
    double? step,
  }) => dao.addVariant(
    programExerciseId: slot ?? press.id,
    exerciseName: name,
    defaultWeightKg: kg,
    weightStepKg: step,
  );

  test('add, list, edit, delete', () async {
    final machine = await add('Shoulder Press (Machine)', 40, step: 5);
    await add('Shoulder Press (DB)', 22.5);

    var list = await dao.listVariants(press.id);
    expect(list.map((v) => v.exerciseName), [
      'Shoulder Press (Machine)',
      'Shoulder Press (DB)',
    ]);
    expect(list.map((v) => v.variant.position), [0, 1]);
    expect(list.first.variant.defaultWeightKg, 40);
    expect(list.first.variant.weightStepKg, 5);
    expect(
      list.last.variant.weightStepKg,
      isNull,
      reason: 'null step falls back to the slot',
    );

    await dao.editVariant(
      id: machine.id,
      exerciseName: 'Shoulder Press (Machine)',
      defaultWeightKg: 45,
      weightStepKg: 5,
    );
    list = await dao.listVariants(press.id);
    expect(list.first.variant.defaultWeightKg, 45);

    await dao.editVariant(
      id: machine.id,
      exerciseName: 'Shoulder Press (Smith)',
      defaultWeightKg: 45,
    );
    list = await dao.listVariants(press.id);
    expect(
      list.first.exerciseName,
      'Shoulder Press (Smith)',
      reason: 'renaming points the variant at another exercise',
    );
    expect(list.first.variant.position, 0, reason: 'order kept');

    await dao.deleteVariant(machine.id);
    expect((await dao.listVariants(press.id)).map((v) => v.exerciseName), [
      'Shoulder Press (DB)',
    ]);
  });

  test('updateVariant writes the row verbatim', () async {
    final v = await add('Shoulder Press (Machine)', 40);
    await dao.updateVariant(v.copyWith(defaultWeightKg: 42.5));
    expect(
      (await dao.listVariants(press.id)).single.variant.defaultWeightKg,
      42.5,
    );
  });

  group('rejects', () {
    Future<VariantConflictReason> reasonOf(Future<Object?> f) async {
      try {
        await f;
      } on VariantConflict catch (e) {
        expect(e.message, isNotEmpty);
        return e.reason;
      }
      fail('expected a VariantConflict');
    }

    test('the slot\'s own base (any case)', () async {
      expect(
        await reasonOf(add('shoulder press', 40)),
        VariantConflictReason.sameAsBase,
      );
      expect(await dao.listVariants(press.id), isEmpty);
    });

    test('a duplicate', () async {
      await add('Shoulder Press (Machine)', 40);
      expect(
        await reasonOf(add('Shoulder Press (MACHINE)', 30)),
        VariantConflictReason.duplicate,
      );
    });

    test('another slot\'s base on the same day', () async {
      expect(
        await reasonOf(add('Barbell Row', 40)),
        VariantConflictReason.baseOfAnotherSlot,
      );
    });

    test('an edit that would collide', () async {
      final a = await add('Shoulder Press (Machine)', 40);
      await add('Shoulder Press (DB)', 20);
      expect(
        await reasonOf(
          dao.editVariant(
            id: a.id,
            exerciseName: 'Shoulder Press (DB)',
            defaultWeightKg: 1,
          ),
        ),
        VariantConflictReason.duplicate,
      );
      expect(
        await reasonOf(
          dao.editVariant(
            id: a.id,
            exerciseName: 'Shoulder Press',
            defaultWeightKg: 1,
          ),
        ),
        VariantConflictReason.sameAsBase,
      );
    });

    test('but allows the same variant on a slot of another day', () async {
      final p = await dao.createProgram('Q');
      final other = await dao.createDay(p.id, 'Pull');
      final otherSlot = await dao.addProgramExercise(
        programDayId: other.id,
        exerciseName: 'Lat Pulldown',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
      await add('Barbell Row', 40, slot: otherSlot.id);
      expect(
        (await dao.listVariants(otherSlot.id)).single.exerciseName,
        'Barbell Row',
      );
    });
  });

  test(
    'listVariantsForDay groups by slot, in slot then variant order',
    () async {
      await add('Shoulder Press (DB)', 20);
      await add('Pendlay Row', 55, slot: row.id);
      await add('Shoulder Press (Machine)', 40);

      final byslot = await dao.listVariantsForDay(dayId);
      expect(byslot.keys, [press.id, row.id]);
      expect(byslot[press.id]!.map((v) => v.exerciseName), [
        'Shoulder Press (DB)',
        'Shoulder Press (Machine)',
      ]);
      expect(byslot[row.id]!.single.exerciseName, 'Pendlay Row');
    },
  );

  test('renaming the base to one of its variants drops that variant', () async {
    final machine = await add('Shoulder Press (Machine)', 40);
    await add('Shoulder Press (DB)', 20);
    await dao.updateProgramExercise(
      ProgramExercise(
        id: press.id,
        programDayId: press.programDayId,
        exerciseId: machine.exerciseId,
        position: press.position,
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 40,
      ),
    );
    expect((await dao.listVariants(press.id)).map((v) => v.exerciseName), [
      'Shoulder Press (DB)',
    ]);
  });

  test('deleting the slot, day or program cascades variants', () async {
    await add('Shoulder Press (Machine)', 40);
    await add('Pendlay Row', 55, slot: row.id);
    await dao.deleteProgramExercise(press.id);
    expect(await dao.listVariants(press.id), isEmpty);
    await dao.deleteDay(dayId);
    expect(await db.query('program_exercise_variants'), isEmpty);
  });
}
