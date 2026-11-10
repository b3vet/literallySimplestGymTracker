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

  test(
    'a variant stores its own prescription; NULL inherits the slot',
    () async {
      final v = await dao.addVariant(
        programExerciseId: press.id,
        exerciseName: 'Shoulder Press (Machine)',
        defaultWeightKg: 40,
        weightStepKg: 5,
        targetSets: 4,
        targetRepsMin: 6,
        targetRepsMax: 8,
        dropCount: 2,
      );
      var stored = (await dao.listVariants(press.id)).single.variant;
      expect(
        [
          stored.targetSets,
          stored.targetRepsMin,
          stored.targetRepsMax,
          stored.dropCount,
        ],
        [4, 6, 8, 2],
      );
      final run = stored.resolvedOn(press);
      expect(run.targetSets, 4);
      expect(run.targetRepsMax, 8);
      expect(run.exerciseId, v.exerciseId);
      expect(run.id, press.id, reason: 'still the slot');

      await dao.editVariant(
        id: v.id,
        exerciseName: 'Shoulder Press (Machine)',
        defaultWeightKg: 42.5,
        weightStepKg: 5,
        targetSets: 2,
        targetRepsMin: 10,
        targetRepsMax: 12,
        dropCount: 0,
      );
      stored = (await dao.listVariants(press.id)).single.variant;
      expect(
        [
          stored.targetSets,
          stored.targetRepsMin,
          stored.targetRepsMax,
          stored.dropCount,
          stored.defaultWeightKg,
        ],
        [2, 10, 12, 0, 42.5],
      );

      // A raise keeps the prescription (copyWith carries it).
      await dao.updateVariant(stored.copyWith(defaultWeightKg: 45));
      stored = (await dao.listVariants(press.id)).single.variant;
      expect(stored.targetSets, 2);
      expect(stored.dropCount, 0);

      final inherit = await add('Shoulder Press (DB)', 20);
      final r = inherit.resolvedOn(press);
      expect(
        [r.targetSets, r.targetRepsMin, r.targetRepsMax, r.dropCount],
        [
          press.targetSets,
          press.targetRepsMin,
          press.targetRepsMax,
          press.dropCount,
        ],
      );
    },
  );

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

    // SOW-14 day rule (D-0011 / QA RISK-02): an exercise appears at most once
    // per day — as a base or as one variant — in every direction.
    test('another slot\'s variant on the same day', () async {
      await add('Shoulder Press (Machine)', 40);
      expect(
        await reasonOf(add('Shoulder Press (Machine)', 35, slot: row.id)),
        VariantConflictReason.variantOfAnotherSlot,
      );
      final db2 = await add('Pendlay Row', 50, slot: row.id);
      expect(
        await reasonOf(
          dao.editVariant(
            id: db2.id,
            exerciseName: 'shoulder press (machine)',
            defaultWeightKg: 1,
          ),
        ),
        VariantConflictReason.variantOfAnotherSlot,
      );
      expect(await dao.listVariants(row.id), hasLength(1));
    });

    test('a new slot whose base is a variant on the day', () async {
      await add('Shoulder Press (Machine)', 40);
      expect(
        await reasonOf(
          dao.addProgramExercise(
            programDayId: dayId,
            exerciseName: 'Shoulder Press (Machine)',
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            defaultWeightKg: 40,
          ),
        ),
        VariantConflictReason.variantOfAnotherSlot,
      );
      expect(await dao.listProgramExercises(dayId), hasLength(2));
    });

    test('renaming a base to another slot\'s variant', () async {
      final machine = await add('Shoulder Press (Machine)', 40);
      final renamed = ProgramExercise(
        id: row.id,
        programDayId: row.programDayId,
        exerciseId: machine.exerciseId,
        position: row.position,
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 60,
      );
      expect(
        await reasonOf(dao.updateProgramExercise(renamed)),
        VariantConflictReason.variantOfAnotherSlot,
      );
      final rows = await dao.listProgramExercises(dayId);
      expect(rows.last.exerciseName, 'Barbell Row', reason: 'nothing written');
      // A write that keeps the exercise (a summary raise) is never refused.
      await dao.updateProgramExercise(row.copyWith(defaultWeightKg: 65));
    });

    test(
      'but still allows two slots sharing a base (1.4.1 behaviour)',
      () async {
        await dao.addProgramExercise(
          programDayId: dayId,
          exerciseName: 'Barbell Row',
          targetSets: 2,
          targetRepsMin: 12,
          targetRepsMax: 15,
          defaultWeightKg: 40,
        );
        expect(await dao.listProgramExercises(dayId), hasLength(3));
      },
    );

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

  group('read guard for days that already conflict (pre-rule data)', () {
    // Written behind the DAO's back, as a 1.4.1 rename would leave it.
    Future<void> rawVariant(String slotId, String exerciseId, int pos) =>
        db.insert('program_exercise_variants', {
          'id': 'raw-$slotId-$pos',
          'program_exercise_id': slotId,
          'exercise_id': exerciseId,
          'position': pos,
          'default_weight': 10.0,
          'weight_step': null,
        });

    test(
      'a variant equal to a base on the day is hidden (the base wins)',
      () async {
        await add('Shoulder Press (Machine)', 40);
        // The slot's own base (1.4.1 renamed the base to its variant) and
        // another slot's base.
        await rawVariant(press.id, press.exerciseId, 5);
        await rawVariant(press.id, row.exerciseId, 6);
        final day = await dao.listVariantsForDay(dayId);
        expect(day[press.id]!.map((v) => v.exerciseName), [
          'Shoulder Press (Machine)',
        ]);
        expect((await dao.listVariants(press.id)).length, 1);
      },
    );

    test('a variant on two slots shows on the first slot only', () async {
      final machine = await add('Shoulder Press (Machine)', 40);
      await rawVariant(row.id, machine.exerciseId, 0);
      final day = await dao.listVariantsForDay(dayId);
      expect(day.keys, [press.id]);
      expect(await dao.listVariants(row.id), isEmpty);
    });
  });

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
