import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/features/workout/domain/active_session.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_set.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-14: switching a slot between its base and its variants mid-workout.
void main() {
  setUpAll(sqfliteFfiInit);

  group('carryOverTargetSets', () {
    const bar = SlotVariant(
      variantId: null,
      exerciseId: 'bar',
      name: 'Bar',
      defaultWeightKg: 60,
    );
    const machine = SlotVariant(
      variantId: 'v1',
      exerciseId: 'machine',
      name: 'Machine',
      defaultWeightKg: 40,
    );
    const db = SlotVariant(
      variantId: 'v2',
      exerciseId: 'db',
      name: 'DB',
      defaultWeightKg: 20,
    );

    PlannedExercise slot({required String on, required int target}) =>
        PlannedExercise(
          programExerciseId: 'pe',
          exerciseId: on,
          exerciseName: on,
          targetSets: target,
          targetRepsMin: 8,
          targetRepsMax: 10,
          defaultWeightKg: 60,
          baseExerciseId: bar.exerciseId,
          baseExerciseName: bar.name,
          baseDefaultWeightKg: bar.defaultWeightKg,
          variants: const [machine, db],
        );

    var seq = 0;
    List<WorkoutSet> sets(Map<String, int> done) => [
      for (final e in done.entries)
        for (var i = 0; i < e.value; i++)
          WorkoutSet(
            id: 's${seq++}',
            sessionId: 'x',
            exerciseId: e.key,
            setIndex: 0,
            reps: 8,
            weightKg: 50,
            rir: 1,
            loggedAt: DateTime(2026),
          ),
    ];

    test('nothing done: the full plan moves over', () {
      expect(carryOverTargetSets(slot(on: 'bar', target: 3), 'machine', []), 3);
    });

    test('one done on the base: the variant gets the rest', () {
      expect(
        carryOverTargetSets(
          slot(on: 'bar', target: 3),
          'machine',
          sets({'bar': 1}),
        ),
        2,
      );
    });

    test('and back again: the base target counts its own set', () {
      // 1 on bar, then machine (target 2) with 1 done, back to bar.
      expect(
        carryOverTargetSets(
          slot(on: 'machine', target: 2),
          'bar',
          sets({'bar': 1, 'machine': 1}),
        ),
        2,
        reason: 'bar: 1 done + 1 left; machine: 1 done → 3 total',
      );
    });

    test('a set added on the variant travels with the slot', () {
      // Plan 3, 1 on bar → machine target 2, + add set → 3, back to bar.
      expect(
        carryOverTargetSets(
          slot(on: 'machine', target: 3),
          'bar',
          sets({'bar': 1}),
        ),
        4,
      );
    });

    test('three-way: sets on every member count once', () {
      expect(
        carryOverTargetSets(
          slot(on: 'machine', target: 2),
          'db',
          sets({'bar': 1, 'machine': 1}),
        ),
        1,
      );
    });

    test('never below one set', () {
      expect(
        carryOverTargetSets(
          slot(on: 'bar', target: 1),
          'machine',
          sets({'bar': 1}),
        ),
        1,
      );
    });

    test('a drop set counts once', () {
      final drop = [
        for (var i = 0; i < 3; i++)
          WorkoutSet(
            id: 'd$i',
            sessionId: 'x',
            exerciseId: 'bar',
            setIndex: i,
            reps: 8,
            weightKg: 50.0 - i * 10,
            rir: 0,
            loggedAt: DateTime(2026),
            setGroup: 'g',
            groupSeq: i,
          ),
      ];
      expect(
        carryOverTargetSets(slot(on: 'bar', target: 3), 'machine', drop),
        2,
      );
    });
  });

  // Review #7: a variant equal to the base (1.4.1 renamed the base to it) or
  // repeated must not produce a dead duplicate row in the picker.
  test('members list each exercise once, the base first', () {
    const dup = SlotVariant(
      variantId: 'v9',
      exerciseId: 'bar',
      name: 'Bar',
      defaultWeightKg: 10,
    );
    const machine = SlotVariant(
      variantId: 'v1',
      exerciseId: 'machine',
      name: 'Machine',
      defaultWeightKg: 40,
    );
    const slot = PlannedExercise(
      programExerciseId: 'pe',
      exerciseId: 'bar',
      exerciseName: 'Bar',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
      defaultWeightKg: 60,
      baseExerciseId: 'bar',
      baseExerciseName: 'Bar',
      baseDefaultWeightKg: 60,
      variants: [dup, machine, machine],
    );
    expect(slot.members.map((m) => m.exerciseId), ['bar', 'machine']);
    expect(slot.members.first.isBase, isTrue);
    expect(slot.members.first.defaultWeightKg, 60);
  });

  group('switchVariant', () {
    late Database db;
    late String dayId;
    late String slotId;
    late String barId;
    late String machineId;
    late String dbId;

    setUp(() async {
      db = await openTestDb();
      final dao = ProgramDao(db);
      final p = await dao.createProgram('P');
      dayId = (await dao.createDay(p.id, 'Push')).id;
      final pe = await dao.addProgramExercise(
        programDayId: dayId,
        exerciseName: 'Shoulder Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 60,
        weightStepKg: 2.5,
      );
      await dao.addProgramExercise(
        programDayId: dayId,
        exerciseName: 'Lateral Raise',
        targetSets: 2,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 10,
      );
      slotId = pe.id;
      barId = pe.exerciseId;
      machineId = (await dao.addVariant(
        programExerciseId: pe.id,
        exerciseName: 'Shoulder Press (Machine)',
        defaultWeightKg: 40,
        weightStepKg: 5,
      )).exerciseId;
      dbId = (await dao.addVariant(
        programExerciseId: pe.id,
        exerciseName: 'Shoulder Press (DB)',
        defaultWeightKg: 22.5,
      )).exerciseId;
    });
    tearDown(() async => db.close());

    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({'settings.live_activity': false});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c.dispose);
      await c.read(activeSessionProvider.future);
      return c;
    }

    Future<ProviderContainer> started() async {
      final c = await container();
      await c.read(activeSessionProvider.notifier).start(dayId);
      return c;
    }

    ActiveSession session(ProviderContainer c) =>
        c.read(activeSessionProvider).value!;

    Future<void> log(ProviderContainer c, double kg) => c
        .read(activeSessionProvider.notifier)
        .logSet(reps: 8, weightKg: kg, rir: 1);

    test('start loads the slot\'s variants; other slots have none', () async {
      final c = await started();
      final s = session(c);
      expect(s.queue.first.hasVariants, isTrue);
      expect(s.queue.first.members.map((m) => m.name), [
        'Shoulder Press',
        'Shoulder Press (Machine)',
        'Shoulder Press (DB)',
      ]);
      expect(s.queue.first.activeMember!.isBase, isTrue);
      expect(s.queue.last.hasVariants, isFalse);
    });

    test(
      'switching applies the variant\'s weight + step, keeps reps',
      () async {
        final c = await started();
        await c
            .read(activeSessionProvider.notifier)
            .switchVariant(0, machineId);
        final slot = session(c).queue.first;
        expect(slot.exerciseId, machineId);
        expect(slot.exerciseName, 'Shoulder Press (Machine)');
        expect(slot.defaultWeightKg, 40);
        expect(slot.weightStepKg, 5);
        expect(slot.targetSets, 3);
        expect(slot.targetRepsMin, 8);
        expect(slot.targetRepsMax, 10);
        expect(slot.isOverridden, isTrue);
        expect(slot.previousExerciseId, barId);
        expect(slot.baseExerciseId, barId, reason: 'the base is remembered');
        expect(session(c).cursor.exerciseIdx, 0, reason: 'cursor stays');

        await c.read(activeSessionProvider.notifier).switchVariant(0, dbId);
        expect(
          session(c).queue.first.weightStepKg,
          2.5,
          reason: 'a variant without a step uses the slot\'s',
        );
      },
    );

    test('the switch persists and a resume rebuilds it', () async {
      final c = await started();
      await log(c, 60); // 1 on the bar
      await c.read(activeSessionProvider.notifier).switchVariant(0, machineId);
      final sessionId = session(c).sessionId;

      final overrides = await WorkoutDao(db).overridesForSession(sessionId);
      expect(overrides.single.exerciseId, machineId);
      expect(overrides.single.targetSets, 2);

      final relaunched = await container();
      final resumed = session(relaunched);
      final slot = resumed.queue.first;
      expect(slot.exerciseId, machineId);
      expect(slot.targetSets, 2);
      expect(slot.defaultWeightKg, 40);
      expect(slot.hasVariants, isTrue, reason: 'variants reload on resume');
      expect(slot.baseExerciseId, barId);
      expect(resumed.cursor.exerciseIdx, 0);
      expect(resumed.cursor.setIdx, 0, reason: 'nothing on the machine yet');
    });

    test('finishing the variant\'s sets advances the cursor', () async {
      final c = await started();
      await log(c, 60);
      await c.read(activeSessionProvider.notifier).switchVariant(0, machineId);
      await log(c, 40);
      expect(session(c).cursor.exerciseIdx, 0);
      await log(c, 40);
      expect(session(c).cursor.exerciseIdx, 1, reason: '1 bar + 2 machine = 3');

      final relaunched = await container();
      expect(
        session(relaunched).cursor.exerciseIdx,
        1,
        reason: 'cursorAfter agrees on resume',
      );
    });

    test('back to the base with nothing logged drops the override', () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.switchVariant(0, machineId);
      await ctrl.switchVariant(0, barId);
      final slot = session(c).queue.first;
      expect(slot.exerciseId, barId);
      expect(slot.isOverridden, isFalse, reason: 'tune button back to neutral');
      expect(slot.previousExerciseId, isNull);
      expect(slot.defaultWeightKg, 60);
      expect(slot.targetSets, 3);
      expect(
        await WorkoutDao(db).overridesForSession(session(c).sessionId),
        isEmpty,
      );
    });

    test(
      'back to the base after logging on the variant keeps the override',
      () async {
        final c = await started();
        final ctrl = c.read(activeSessionProvider.notifier);
        await ctrl.switchVariant(0, machineId);
        await log(c, 40);
        await ctrl.switchVariant(0, barId);
        final slot = session(c).queue.first;
        expect(slot.exerciseId, barId);
        expect(slot.targetSets, 2);
        expect(slot.isOverridden, isTrue);
        expect(
          slot.previousExerciseId,
          machineId,
          reason: 'drives the PREVIOUSLY 1 SET ON … banner',
        );
        expect(slot.defaultWeightKg, 60);
      },
    );

    test('ignores slots without variants and unknown exercises', () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      final before = session(c);
      await ctrl.switchVariant(1, machineId);
      await ctrl.switchVariant(0, 'not-a-member');
      await ctrl.switchVariant(0, barId); // already on the base
      expect(identical(session(c), before), isTrue);
    });

    test('a revert to plan keeps the slot\'s variants', () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.substituteExercise(
        queueIdx: 0,
        exerciseName: 'Cable Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 30,
      );
      expect(session(c).queue.first.hasVariants, isTrue);
      expect(
        session(c).queue.first.activeMember,
        isNull,
        reason: 'swapped outside the slot',
      );
      await ctrl.revertSubstitution(0);
      expect(session(c).queue.first.members.length, 3);
      expect(slotId, session(c).queue.first.programExerciseId);
    });
  });
}
