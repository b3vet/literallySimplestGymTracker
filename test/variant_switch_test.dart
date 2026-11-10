import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_provider.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/rest_timer_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/summary_controller.dart'
    show attributeToSlots;
import 'package:ls_workout_tracker/features/workout/application/watch_snapshot.dart';
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

    /// The slot runs as [on] with [target] sets now; the base plans [base]
    /// sets, and the machine / DB variants plan their own when given (else
    /// they inherit the base's).
    PlannedExercise slot({
      required String on,
      required int target,
      int base = 3,
      int? machineSets,
      int? dbSets,
    }) => PlannedExercise(
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
      baseTargetSets: base,
      baseTargetRepsMin: 8,
      baseTargetRepsMax: 10,
      baseDropCount: 0,
      variants: [
        SlotVariant(
          variantId: machine.variantId,
          exerciseId: machine.exerciseId,
          name: machine.name,
          defaultWeightKg: machine.defaultWeightKg,
          targetSets: machineSets,
        ),
        SlotVariant(
          variantId: db.variantId,
          exerciseId: db.exerciseId,
          name: db.name,
          defaultWeightKg: db.defaultWeightKg,
          targetSets: dbSets,
        ),
      ],
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

    // DEC-0007 #13: M's own plan governs, so a session "Add set" stays with
    // the member it was made on (it used to travel: 4 here).
    test('a set added on the variant stays there: the bar plan governs', () {
      // Plan 3, 1 on bar → machine target 2, + add set → 3, back to bar.
      expect(
        carryOverTargetSets(
          slot(on: 'machine', target: 3),
          'bar',
          sets({'bar': 1}),
        ),
        3,
        reason: 'bar: 3 planned, 1 done → 2 left; the 1 done stays counted',
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

    // Review #2: the old floor of 1 added a set on every round trip of a
    // complete slot (plan 3, all done → machine 1 → bar 4).
    test('a complete slot moves nothing over, and a round trip keeps 3', () {
      final done = sets({'bar': 3});
      final toMachine =
          carryOverTargetSets(slot(on: 'bar', target: 3), 'machine', done);
      expect(toMachine, 0);
      final back = carryOverTargetSets(
        slot(on: 'machine', target: toMachine),
        'bar',
        done,
      );
      expect(back, 3);
      // …and again: no drift.
      expect(
        carryOverTargetSets(
          slot(on: 'bar', target: back),
          'db',
          done,
        ),
        0,
      );
    });

    test('over target on the current member: keep what the new one has', () {
      // 4 logged on a 3-set bar, 1 on the machine from earlier.
      expect(
        carryOverTargetSets(
          slot(on: 'bar', target: 3),
          'machine',
          sets({'bar': 4, 'machine': 1}),
        ),
        1,
      );
    });

    group('members with their own set counts (DEC-0007 #13)', () {
      // max(doneOn(M), M.targetSets − Σ doneOn(others))
      final table = <(String, PlannedExercise, String, Map<String, int>, int)>[
        (
          'base 3 → variant 4 after 1 on the base',
          slot(on: 'bar', target: 3, machineSets: 4),
          'machine',
          {'bar': 1},
          3,
        ),
        (
          'base 4 → variant 2 after 3 on the base: complete',
          slot(on: 'bar', target: 4, base: 4, machineSets: 2),
          'machine',
          {'bar': 3},
          0,
        ),
        (
          'variant 4 with 2 done → base 3 (1 done there)',
          slot(on: 'machine', target: 3, machineSets: 4),
          'bar',
          {'bar': 1, 'machine': 2},
          1,
        ),
        (
          'base 3 → variant 2, nothing done',
          slot(on: 'bar', target: 3, machineSets: 2),
          'machine',
          {},
          2,
        ),
        (
          'and back to the base: its own 3, not the variant\'s 2',
          slot(on: 'machine', target: 2, machineSets: 2),
          'bar',
          {},
          3,
        ),
        (
          'variant 2 → variant 5 (DB) across three members',
          slot(on: 'machine', target: 1, machineSets: 2, dbSets: 5),
          'db',
          {'bar': 1, 'machine': 1},
          3,
        ),
        (
          'an inheriting variant takes the base plan (4)',
          slot(on: 'bar', target: 4, base: 4),
          'machine',
          {'bar': 1},
          3,
        ),
        (
          'over the new plan already: keep what the new member has',
          slot(on: 'bar', target: 3, machineSets: 2),
          'machine',
          {'bar': 2, 'machine': 1},
          1,
        ),
      ];
      for (final (name, s, to, done, want) in table) {
        test(name, () {
          expect(carryOverTargetSets(s, to, sets(done)), want);
        });
      }

      test('complete under the new member\'s plan: the switch is refused', () {
        final s = slot(on: 'bar', target: 4, base: 4, machineSets: 2);
        final done = sets({'bar': 3});
        final m = s.members.firstWhere((m) => m.exerciseId == 'machine');
        expect(s.canSwitchTo(m, done), isFalse);
        expect(s.canSwitchTo(s.members.last, done), isTrue, reason: 'DB: 4');
        expect(s.canSwitchVariant(done), isTrue);
        expect(
          slot(
            on: 'bar',
            target: 4,
            base: 4,
            machineSets: 2,
            dbSets: 3,
          ).canSwitchVariant(done),
          isFalse,
          reason: 'no other member has a set left under its plan',
        );
      });

      // SOW-14 §3 #6, the per-member rule (D-0016 review #3): a complete
      // running member doesn't block a member with sets left under its plan.
      test('base 2, variant 4, 2 done on the base: the switch is allowed', () {
        final s = slot(on: 'bar', target: 2, base: 2, machineSets: 4);
        final done = sets({'bar': 2});
        expect(s.isCompleteIn(done), isTrue);
        final m = s.members.firstWhere((m) => m.exerciseId == 'machine');
        expect(s.canSwitchTo(m, done), isTrue);
        expect(s.canSwitchVariant(done), isTrue);
        expect(carryOverTargetSets(s, 'machine', done), 2, reason: '4 − 2');
        expect(
          s.canSwitchTo(s.members.last, done),
          isFalse,
          reason: 'the DB inherits 2: met',
        );
        // On the variant, the base stays refused: no inflation.
        final on = slot(on: 'machine', target: 2, base: 2, machineSets: 4);
        expect(on.canSwitchTo(on.members.first, done), isFalse);
        expect(carryOverTargetSets(on, 'bar', done), 2, reason: 'no drift');
      });

      test('round trips never drift', () {
        final done = sets({'bar': 1, 'machine': 1});
        var s = slot(on: 'bar', target: 3, machineSets: 4);
        for (var i = 0; i < 3; i++) {
          final toMachine = carryOverTargetSets(s, 'machine', done);
          expect(toMachine, 3);
          s = slot(on: 'machine', target: toMachine, machineSets: 4);
          final back = carryOverTargetSets(s, 'bar', done);
          expect(back, 2);
          s = slot(on: 'bar', target: back, machineSets: 4);
        }
      });
    });

    // D-0016 review #1: a "Change exercise" swap the slot has since left
    // still counts — the override row names it only in ran_exercise_ids.
    test('sets on an exercise the slot left still count', () {
      // Bar → Cable (2 logged) → Machine (target 1) → back to Bar.
      final s = slot(on: 'machine', target: 1).copyWith(
        previousExerciseId: 'cable',
        ranExerciseIds: ['bar', 'cable'],
      );
      final done = sets({'cable': 2});
      expect(s.slotDoneSets(done), 2);
      expect(carryOverTargetSets(s, 'bar', done), 1);
      expect(carryOverTargetSets(s, 'db', done), 1);
      // The row before v9 knew only its two links: Machine and the base.
      final after = slot(on: 'bar', target: 1).copyWith(
        previousExerciseId: 'machine',
        ranExerciseIds: ['bar', 'cable', 'machine'],
      );
      expect(after.ranBefore, ['cable', 'machine']);
      expect(after.earlierSets(done), [('cable', 2)]);
      expect(carryOverTargetSets(after, 'machine', done), 1);
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

    // Review #3: the numbers alone used to decide. Plan 3 → machine 3, + add
    // set → 4, log 1 on the machine → back to the bar: a machine set exists,
    // so the override (and its lineage) must stay. Since DEC-0007 #13 the bar
    // runs its own plan: 3 − 1 done elsewhere = 2 (the machine's Add set
    // stays with the machine).
    test('back to the base keeps the override when a variant has a set, '
        'after an Add set on the variant', () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.switchVariant(0, machineId);
      await ctrl.addSetToCurrent();
      await log(c, 40);
      await ctrl.switchVariant(0, barId);
      final slot = session(c).queue.first;
      expect(slot.targetSets, 2);
      expect(slot.isOverridden, isTrue);
      expect(slot.previousExerciseId, machineId);
      final o = (await WorkoutDao(db).overridesForSession(session(c).sessionId))
          .single;
      expect(o.exerciseId, barId);
      expect(o.previousExerciseId, machineId);
    });

    test('a Change-exercise weight edit on the base survives a round trip',
        () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.substituteExercise(
        queueIdx: 0,
        exerciseName: 'Shoulder Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 65,
        weightStepKg: 2.5,
      );
      await ctrl.switchVariant(0, machineId);
      expect(session(c).queue.first.defaultWeightKg, 40);
      await ctrl.switchVariant(0, barId);
      final slot = session(c).queue.first;
      expect(slot.exerciseId, barId);
      expect(slot.defaultWeightKg, 65, reason: 'the edit, not the plan\'s 60');
      expect(slot.isOverridden, isTrue, reason: 'still differs from the plan');
      final o = (await WorkoutDao(db).overridesForSession(session(c).sessionId))
          .single;
      expect(o.defaultWeightKg, 65);

      // …and a variant's own edit comes back too.
      await ctrl.switchVariant(0, machineId);
      await ctrl.substituteExercise(
        queueIdx: 0,
        exerciseName: 'Shoulder Press (Machine)',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 45,
        weightStepKg: 5,
      );
      await ctrl.switchVariant(0, barId);
      await ctrl.switchVariant(0, machineId);
      expect(session(c).queue.first.defaultWeightKg, 45);
    });

    test('a complete slot ignores the switch: plan 3, all done, round trip',
        () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      for (var i = 0; i < 3; i++) {
        await log(c, 60);
      }
      expect(session(c).cursor.exerciseIdx, 1);
      await ctrl.goToExerciseIndex(0); // go back to the finished slot
      await ctrl.switchVariant(0, machineId);
      await ctrl.switchVariant(0, barId);
      final slot = session(c).queue.first;
      expect(slot.exerciseId, barId);
      expect(slot.targetSets, 3, reason: 'still 3 total, no inflation');
      expect(slot.isOverridden, isFalse);
      expect(
        await WorkoutDao(db).overridesForSession(session(c).sessionId),
        isEmpty,
      );
    });

    // D-0016 review #1 (regression): sets done on a swapped-in non-member
    // dropped out of the slot count once the slot moved on — base Bar plan 3
    // → Change exercise to Cable → 2 on Cable → Machine (1, right) → Bar
    // gave 3, deleted the override, lost the banner and the summary link.
    Future<String> barCableMachineBar(
      ProviderContainer c, {
      Future<ProviderContainer> Function()? resumeAfterMachine,
    }) async {
      var ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.substituteExercise(
        queueIdx: 0,
        exerciseName: 'Cable Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 30,
      );
      final cableId = session(c).queue.first.exerciseId;
      await log(c, 30);
      await log(c, 30);
      await ctrl.switchVariant(0, machineId);
      expect(session(c).queue.first.targetSets, 1, reason: '3 − 2 on Cable');
      if (resumeAfterMachine != null) {
        c = await resumeAfterMachine();
        ctrl = c.read(activeSessionProvider.notifier);
        expect(session(c).queue.first.exerciseId, machineId);
        expect(session(c).queue.first.targetSets, 1);
      }
      await ctrl.switchVariant(0, barId);
      return cableId;
    }

    Future<void> expectBarAfterCable(
      ProviderContainer c,
      String cableId,
    ) async {
      final s = session(c);
      final slot = s.queue.first;
      expect(slot.exerciseId, barId);
      expect(slot.targetSets, 1, reason: 'bar 3 − 2 on Cable − 0 on Machine');
      expect(slot.isOverridden, isTrue, reason: 'the override is kept');
      expect(slot.slotDoneSets(s.loggedSets), 2);
      expect(
        slot.earlierSets(s.loggedSets),
        [(cableId, 2)],
        reason: 'PREVIOUSLY 2 SETS ON CABLE PRESS',
      );
      final o = (await WorkoutDao(db).overridesForSession(s.sessionId)).single;
      expect(o.exerciseId, barId);
      expect(o.targetSets, 1);
      expect(o.ranExerciseIds, containsAll([barId, cableId, machineId]));

      // The summary still links the Cable sets to the slot (SAVE AS VARIANT).
      final dao = ProgramDao(db);
      final attribution = attributeToSlots(
        exerciseIds: [cableId],
        slots: await dao.listProgramExercises(dayId),
        variantsBySlot: await dao.listVariantsForDay(dayId),
        overrides: await WorkoutDao(db).overridesForSession(s.sessionId),
      );
      expect(attribution[cableId]?.slot.pe.id, slotId);
      expect(attribution[cableId]?.variant, isNull, reason: 'a swap');

      // One set on the bar finishes the slot.
      await log(c, 60);
      expect(session(c).cursor.exerciseIdx, 1, reason: '2 Cable + 1 Bar');
    }

    test('Bar → Change exercise to Cable, 2 logged → Machine → Bar: Bar '
        'target 1, override and banner kept', () async {
      final c = await started();
      final cableId = await barCableMachineBar(c);
      await expectBarAfterCable(c, cableId);
    });

    test('…and the same across resumes', () async {
      final c = await started();
      final cableId = await barCableMachineBar(
        c,
        resumeAfterMachine: container,
      );
      final resumed = await container();
      await expectBarAfterCable(resumed, cableId);
      expect(
        session(await container()).cursor.exerciseIdx,
        1,
        reason: 'cursorAfter agrees on the next resume',
      );
    });

    // QA VAR-04: the first lookup of a variant without history cached `null`
    // for the whole process, so its repeat chip never showed up later.
    test('last-set lookups refresh after a set, a finish and an abandon',
        () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.switchVariant(0, machineId);
      expect(await c.read(lastSetForExerciseProvider(machineId).future), isNull);
      expect(
        await c.read(lastWeightForExerciseProvider(machineId).future),
        isNull,
      );
      await log(c, 42.5);
      expect(
        (await c.read(lastSetForExerciseProvider(machineId).future))?.weightKg,
        42.5,
        reason: 'refreshed after logging',
      );
      await ctrl.finish();

      // Next workout, same process: the variant now has history.
      expect(await c.read(lastSetForExerciseProvider(dbId).future), isNull);
      await ctrl.start(dayId);
      await ctrl.switchVariant(0, dbId);
      await log(c, 20);
      await ctrl.abandon();
      expect(
        (await c.read(lastSetForExerciseProvider(dbId).future))?.weightKg,
        20,
      );
      expect(await c.read(lastWeightForExerciseProvider(dbId).future), 20);
      expect(
        (await c.read(lastSetForExerciseProvider(machineId).future))?.weightKg,
        42.5,
      );
    });

    test('ignores slots without variants and unknown exercises', () async {
      final c = await started();
      final ctrl = c.read(activeSessionProvider.notifier);
      final before = session(c);
      await ctrl.switchVariant(1, machineId);
      await ctrl.switchVariant(0, 'not-a-member');
      await ctrl.switchVariant(0, barId); // already on the base
      expect(identical(session(c), before), isTrue);
    });

    // Review #5: the override used to be deleted before the plan lookup threw
    // a StateError, leaving the DB and memory out of sync.
    test('a revert whose slot was deleted mid-workout changes nothing',
        () async {
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
      await ProgramDao(db).deleteProgramExercise(slotId);
      final before = session(c);
      await ctrl.revertSubstitution(0); // no StateError
      expect(identical(session(c), before), isTrue, reason: 'memory as is');
      final o = await WorkoutDao(db).overridesForSession(before.sessionId);
      expect(o.single.exerciseName, 'Cable Press', reason: 'DB as is');
      expect(session(c).queue.first.exerciseName, 'Cable Press');
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

  // DEC-0007 #13: a variant with its own sets, reps and drops.
  group('switchVariant with per-variant prescriptions', () {
    late Database db;
    late String dayId;
    late String barId;
    late String smithId;
    late String cableId;

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
      barId = pe.exerciseId;
      smithId = (await dao.addVariant(
        programExerciseId: pe.id,
        exerciseName: 'Shoulder Press (Smith)',
        defaultWeightKg: 50,
        weightStepKg: 5,
        targetSets: 4,
        targetRepsMin: 6,
        targetRepsMax: 8,
        dropCount: 1,
      )).exerciseId;
      cableId = (await dao.addVariant(
        programExerciseId: pe.id,
        exerciseName: 'Shoulder Press (Cable)',
        defaultWeightKg: 20,
        targetSets: 2,
        targetRepsMin: 12,
        targetRepsMax: 15,
        dropCount: 0,
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

    ActiveSession session(ProviderContainer c) =>
        c.read(activeSessionProvider).value!;

    Future<void> logBar(ProviderContainer c) => c
        .read(activeSessionProvider.notifier)
        .logSet(reps: 8, weightKg: 60, rir: 1);

    Future<void> logDropSet(ProviderContainer c) => c
        .read(activeSessionProvider.notifier)
        .logSetGroup(const [
          SetEntry(reps: 7, weightKg: 50, rir: 1),
          SetEntry(reps: 8, weightKg: 35),
        ]);

    test('the variant\'s own sets, reps and drops apply; the watch snapshot '
        'and a resume agree', () async {
      final c = await container();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.start(dayId);
      await logBar(c); // 1 of the bar's 3
      await ctrl.switchVariant(0, smithId);

      final slot = session(c).queue.first;
      expect(slot.exerciseId, smithId);
      expect(slot.targetSets, 3, reason: 'smith 4 − 1 done on the bar');
      expect(slot.targetRepsMin, 6);
      expect(slot.targetRepsMax, 8);
      expect(slot.dropCount, 1);
      expect(slot.isDropSet, isTrue, reason: 'the log sheet logs a drop set');
      expect(slot.defaultWeightKg, 50);
      expect(slot.weightStepKg, 5);
      expect(session(c).cursor.exerciseIdx, 0);
      expect(session(c).cursor.setIdx, 0, reason: 'nothing on the smith yet');

      final o = (await WorkoutDao(
        db,
      ).overridesForSession(session(c).sessionId)).single;
      expect(
        [o.targetSets, o.targetRepsMin, o.targetRepsMax, o.dropCount],
        [3, 6, 8, 1],
      );

      // The watch counts and logs off the snapshot: the variant's numbers.
      final snap = buildWatchSnapshot(
        session: session(c),
        rest: const RestTimerState(),
        settings: c.read(settingsProvider),
      );
      final w = snap.queue.first;
      expect(w.exerciseId, smithId);
      expect(w.name, 'Shoulder Press (Smith)');
      expect(
        [w.targetSets, w.targetRepsMin, w.targetRepsMax, w.dropCount],
        [3, 6, 8, 1],
      );
      expect(snap.cursorExerciseIdx, 0);

      // A resume rebuilds the same slot.
      final resumed = session(await container()).queue.first;
      expect(
        [
          resumed.exerciseId,
          resumed.targetSets,
          resumed.targetRepsMin,
          resumed.targetRepsMax,
          resumed.dropCount,
        ],
        [smithId, 3, 6, 8, 1],
      );

      // 3 drop sets (a drop set counts once) finish the slot.
      for (var i = 0; i < 3; i++) {
        await logDropSet(c);
      }
      expect(session(c).cursor.exerciseIdx, 1, reason: '1 bar + 3 smith');
      expect(cursorAfter(session(c).queue, session(c).loggedSets).exerciseIdx, 1);
      expect(
        buildWatchSnapshot(
          session: session(c),
          rest: const RestTimerState(),
          settings: c.read(settingsProvider),
        ).cursorExerciseIdx,
        1,
      );
    });

    test('back to the base: its own reps and drops; nothing logged off the '
        'base drops the override', () async {
      final c = await container();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.start(dayId);
      await ctrl.switchVariant(0, smithId);
      expect(session(c).queue.first.targetSets, 4);
      await ctrl.switchVariant(0, barId);
      final slot = session(c).queue.first;
      expect(
        [
          slot.targetSets,
          slot.targetRepsMin,
          slot.targetRepsMax,
          slot.dropCount,
          slot.defaultWeightKg,
          slot.weightStepKg,
        ],
        [3, 8, 10, 0, 60, 2.5],
      );
      expect(slot.isOverridden, isFalse);
      expect(
        await WorkoutDao(db).overridesForSession(session(c).sessionId),
        isEmpty,
      );
    });

    // SOW-14 §3 #6, the per-member rule (D-0016 review #3).
    test('a complete base switches to a bigger variant; no inflation, no '
        'drift, and a resume agrees', () async {
      final c = await container();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.start(dayId);
      for (var i = 0; i < 3; i++) {
        await logBar(c);
      }
      expect(session(c).cursor.exerciseIdx, 1, reason: 'bar 3 of 3');
      await ctrl.goToExerciseIndex(0);
      await ctrl.switchVariant(0, smithId);
      var slot = session(c).queue.first;
      expect(slot.exerciseId, smithId, reason: 'allowed: smith plans 4');
      expect(slot.targetSets, 1, reason: 'smith 4 − 3 on the bar');

      // Back to the bar or on to the cable: both plans are met — refused.
      final before = session(c);
      await ctrl.switchVariant(0, barId);
      await ctrl.switchVariant(0, cableId);
      expect(identical(session(c), before), isTrue);
      expect(slot.canSwitchVariant(before.loggedSets), isFalse);

      await logDropSet(c);
      expect(session(c).cursor.exerciseIdx, 1, reason: '3 bar + 1 smith');
      final resumed = session(await container());
      slot = resumed.queue.first;
      expect([slot.exerciseId, slot.targetSets], [smithId, 1]);
      expect(resumed.cursor.exerciseIdx, 1);
    });

    test('a smaller variant plan: on the cable 2 after 1 on the bar, and a '
        'plan already met is refused', () async {
      final c = await container();
      final ctrl = c.read(activeSessionProvider.notifier);
      await ctrl.start(dayId);
      await logBar(c);
      await ctrl.switchVariant(0, cableId);
      expect(session(c).queue.first.targetSets, 1, reason: 'cable 2 − 1');
      expect(session(c).queue.first.targetRepsMin, 12);
      await ctrl.switchVariant(0, barId);
      expect(session(c).queue.first.targetSets, 3, reason: 'bar: own 3');
      await logBar(c); // 2 done on the bar: the cable's 2 are met

      final before = session(c);
      final slot = before.queue.first;
      final cable = slot.members.firstWhere((m) => m.exerciseId == cableId);
      expect(slot.canSwitchTo(cable, before.loggedSets), isFalse);
      await ctrl.switchVariant(0, cableId);
      expect(identical(session(c), before), isTrue, reason: 'ignored');

      await ctrl.switchVariant(0, smithId);
      expect(session(c).queue.first.targetSets, 2, reason: 'smith 4 − 2');
    });
  });
}
