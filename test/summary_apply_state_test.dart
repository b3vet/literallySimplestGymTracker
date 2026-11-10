import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/history/application/history_provider.dart'
    show sessionDetailProvider;
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/domain/program_exercise_variant.dart';
import 'package:ls_workout_tracker/features/share/domain/workout_summary.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart'
    show sessionPrsProvider;
import 'package:ls_workout_tracker/features/workout/application/pr_detector.dart';
import 'package:ls_workout_tracker/features/workout/application/summary_controller.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/main.dart' show databaseProvider;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

Future<Database> _openInMemory() => openTestDb();

/// A completed session on a 3-exercise day, plus one substituted lift that
/// isn't in the plan. Every planned lift is loaded above its target, so all
/// three qualify for RAISE and the extra one qualifies for ADD.
Future<({String sessionId, String dayId})> _seed(Database db) async {
  final pDao = ProgramDao(db);
  final wDao = WorkoutDao(db);

  final program = await pDao.createProgram('Test Program');
  final day = await pDao.createDay(program.id, 'Push');
  for (final n in ['Bench Press', 'Overhead Press', 'Incline Press']) {
    await pDao.addProgramExercise(
      programDayId: day.id,
      exerciseName: n,
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 50,
    );
  }
  final planned = await pDao.listProgramExercises(day.id);
  final substituted = await pDao.findOrCreateExercise('Cable Fly');

  final session = await wDao.startSession(day.id);
  for (final v in planned) {
    for (var i = 0; i < 3; i++) {
      await wDao.insertSet(
        sessionId: session.id,
        exerciseId: v.pe.exerciseId,
        setIndex: i,
        reps: 6,
        weightKg: 80,
        rir: 2,
      );
    }
  }
  for (var i = 0; i < 3; i++) {
    await wDao.insertSet(
      sessionId: session.id,
      exerciseId: substituted.id,
      setIndex: i,
      reps: 12,
      weightKg: 22.5,
      rir: 1,
    );
  }
  await wDao.completeSession(session.id);
  return (sessionId: session.id, dayId: day.id);
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProviderContainer container;
  late String sessionId;
  late String dayId;

  setUp(() async {
    db = await _openInMemory();
    final seeded = await _seed(db);
    sessionId = seeded.sessionId;
    dayId = seeded.dayId;
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<List<ProgramUpdate>> updates() =>
      container.read(programUpdatesProvider(sessionId).future);

  ProgramUpdatesController ctrl() =>
      container.read(programUpdatesProvider(sessionId).notifier);

  test('offers a raise for each in-plan lift and an add for the substitute',
      () async {
    final list = await updates();
    expect(list.length, 4);
    expect(
      list.where((u) => u.kind == ProgramUpdateKind.raise).length,
      3,
    );
    final add = list.singleWhere((u) => u.kind == ProgramUpdateKind.add);
    expect(add.exerciseName, 'Cable Fly');
    expect(list.every((u) => !u.applied), isTrue);
  });

  // The regression this file exists for: the applied flag used to live in the
  // per-card widget State, inside a lazily-built ListView. Applying one card
  // then scrolling to another destroyed the first card's element and silently
  // reset it to "not applied" — even though the program had already changed.
  test('applying one update leaves the others untouched and keeps its own flag',
      () async {
    final before = await updates();
    final first = before.first;
    final second = before[1];

    await ctrl().applyOne(first.exerciseId);
    var list = await updates();
    expect(list.firstWhere((u) => u.exerciseId == first.exerciseId).applied,
        isTrue);
    expect(list.firstWhere((u) => u.exerciseId == second.exerciseId).applied,
        isFalse);

    // Apply a second one — the first must STAY applied.
    await ctrl().applyOne(second.exerciseId);
    list = await updates();
    expect(list.firstWhere((u) => u.exerciseId == first.exerciseId).applied,
        isTrue,
        reason: 'applying another update must not reset the first');
    expect(list.firstWhere((u) => u.exerciseId == second.exerciseId).applied,
        isTrue);
    expect(ctrl().appliedCount, 2);
    expect(ctrl().pendingCount, 2);
  });

  test('a raise writes the new target and undo restores the old one', () async {
    final pDao = ProgramDao(db);
    final raise = (await updates())
        .firstWhere((u) => u.kind == ProgramUpdateKind.raise);

    await ctrl().applyOne(raise.exerciseId);
    var plan = await pDao.listProgramExercises(dayId);
    expect(
      plan.firstWhere((v) => v.pe.exerciseId == raise.exerciseId).pe
          .defaultWeightKg,
      80,
    );

    await ctrl().undoOne(raise.exerciseId);
    plan = await pDao.listProgramExercises(dayId);
    expect(
      plan.firstWhere((v) => v.pe.exerciseId == raise.exerciseId).pe
          .defaultWeightKg,
      50,
    );
    expect(
      (await updates())
          .firstWhere((u) => u.exerciseId == raise.exerciseId)
          .applied,
      isFalse,
    );
  });

  test('an add creates the program row and undo deletes exactly that row',
      () async {
    final pDao = ProgramDao(db);
    final add =
        (await updates()).singleWhere((u) => u.kind == ProgramUpdateKind.add);

    await ctrl().applyOne(add.exerciseId);
    expect((await pDao.listProgramExercises(dayId)).length, 4);
    final applied =
        (await updates()).singleWhere((u) => u.exerciseId == add.exerciseId);
    expect(applied.applied, isTrue);
    expect(applied.createdProgramExerciseId, isNotNull);

    await ctrl().undoOne(add.exerciseId);
    expect((await pDao.listProgramExercises(dayId)).length, 3);
    expect(
      (await updates()).singleWhere((u) => u.exerciseId == add.exerciseId)
          .createdProgramExerciseId,
      isNull,
    );
  });

  test('applyAll / undoAll move every row and report how many changed',
      () async {
    final pDao = ProgramDao(db);
    expect(await ctrl().applyAll(), 4);
    expect((await updates()).every((u) => u.applied), isTrue);
    expect((await pDao.listProgramExercises(dayId)).length, 4);

    // A second applyAll is a no-op, not a double-write.
    expect(await ctrl().applyAll(), 0);

    expect(await ctrl().undoAll(), 4);
    expect((await updates()).every((u) => !u.applied), isTrue);
    final plan = await pDao.listProgramExercises(dayId);
    expect(plan.length, 3);
    expect(plan.every((v) => v.pe.defaultWeightKg == 50), isTrue);
  });

  test('summary derives the session totals the screen renders', () async {
    final s = await container.read(sessionSummaryProvider(sessionId).future);
    expect(s, isNotNull);
    expect(s!.exerciseCount, 4);
    expect(s.setCount, 12);
    // 3 lifts × 3 sets × 80kg × 6 reps + 3 × 22.5kg × 12 reps
    expect(s.totalVolumeKg, closeTo(3 * 3 * 80 * 6 + 3 * 22.5 * 12, 0.001));
    expect(s.dayName, 'Push');
    expect(s.programName, 'Test Program');
    expect(s.hasPrevSession, isFalse);
    // First session ever: PR surfaces are suppressed rather than marking
    // every lift a record.
    expect(s.isFirstEverSession, isTrue);
    expect(s.prCount, 0);
  });

  group('variants (SOW-14)', () {
    late String vSessionId;
    late String vDayId;
    late String pressSlotId;
    late String rowSlotId;
    late String machineVariantId;
    late String dbVariantId;
    late Map<String, String> ex; // name → exercise id

    Future<void> logSets(
      WorkoutDao w,
      String sessionId,
      String exerciseId,
      double kg, {
      int n = 2,
    }) async {
      for (var i = 0; i < n; i++) {
        await w.insertSet(
          sessionId: sessionId,
          exerciseId: exerciseId,
          setIndex: i,
          reps: 8,
          weightKg: kg,
          rir: 1,
        );
      }
    }

    /// Upper day: Shoulder Press (60) with variants Machine (40) and DB
    /// (22.5); Row (60). An earlier session gives Machine/DB/Cable Row a
    /// history. Today: press beats target; machine beats ITS target; DB stays
    /// under its target; Row was swapped for Cable Row with "Change exercise";
    /// Curl was inserted.
    setUp(() async {
      final pDao = ProgramDao(db);
      final wDao = WorkoutDao(db);
      final p = await pDao.createProgram('Upper/Lower');
      vDayId = (await pDao.createDay(p.id, 'Upper')).id;
      final press = await pDao.addProgramExercise(
        programDayId: vDayId,
        exerciseName: 'Shoulder Press',
        targetSets: 2,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 60,
      );
      final row = await pDao.addProgramExercise(
        programDayId: vDayId,
        exerciseName: 'Row',
        targetSets: 2,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 60,
      );
      pressSlotId = press.id;
      rowSlotId = row.id;
      // DEC-0007 #13: the machine has its own prescription; DB inherits.
      final machine = await pDao.addVariant(
        programExerciseId: press.id,
        exerciseName: 'Shoulder Press (Machine)',
        defaultWeightKg: 40,
        weightStepKg: 5,
        targetSets: 3,
        targetRepsMin: 6,
        targetRepsMax: 8,
        dropCount: 1,
      );
      final dbv = await pDao.addVariant(
        programExerciseId: press.id,
        exerciseName: 'Shoulder Press (DB)',
        defaultWeightKg: 22.5,
      );
      machineVariantId = machine.id;
      dbVariantId = dbv.id;
      final cable = await pDao.findOrCreateExercise('Cable Row');
      final curl = await pDao.findOrCreateExercise('Curl');
      ex = {
        'press': press.exerciseId,
        'row': row.exerciseId,
        'machine': machine.exerciseId,
        'db': dbv.exerciseId,
        'cable': cable.id,
        'curl': curl.id,
      };

      final earlier = await wDao.startSession(vDayId);
      await logSets(wDao, earlier.id, ex['machine']!, 40);
      await logSets(wDao, earlier.id, ex['db']!, 25);
      await logSets(wDao, earlier.id, ex['cable']!, 50);
      await wDao.completeSession(earlier.id);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final today = await wDao.startSession(vDayId);
      vSessionId = today.id;
      await logSets(wDao, today.id, ex['press']!, 62.5);
      await logSets(wDao, today.id, ex['machine']!, 45);
      await logSets(wDao, today.id, ex['db']!, 20);
      await wDao.upsertOverride(
        sessionId: today.id,
        programExerciseId: row.id,
        exerciseId: cable.id,
        previousExerciseId: row.exerciseId,
        // The swap's session prescription (≠ what was logged: 2 × 8).
        targetSets: 3,
        targetRepsMin: 10,
        targetRepsMax: 12,
        defaultWeightKg: 50,
        dropCount: 1,
      );
      await logSets(wDao, today.id, cable.id, 55);
      await wDao.insertSessionExercise(
        sessionId: today.id,
        exerciseId: curl.id,
        targetSets: 2,
        targetRepsMin: 10,
        targetRepsMax: 12,
        defaultWeightKg: 12,
        orderPos: 5,
      );
      await logSets(wDao, today.id, curl.id, 12);
      await wDao.completeSession(today.id);
    });

    Future<List<ProgramUpdate>> vUpdates() =>
        container.read(programUpdatesProvider(vSessionId).future);
    ProgramUpdatesController vCtrl() =>
        container.read(programUpdatesProvider(vSessionId).notifier);
    ProgramUpdate kindOf(List<ProgramUpdate> l, String key) =>
        l.singleWhere((u) => u.exerciseId == ex[key]);

    test('each exercise gets the right kind', () async {
      final list = await vUpdates();
      expect(kindOf(list, 'press').kind, ProgramUpdateKind.raise);
      final m = kindOf(list, 'machine');
      expect(m.kind, ProgramUpdateKind.raiseVariant,
          reason: 'a variant is never offered ADD TO DAY');
      expect(m.currentTargetKg, 40);
      expect(m.proposedTargetKg, 45);
      expect(m.slotName, 'Shoulder Press');
      final c = kindOf(list, 'cable');
      expect(c.kind, ProgramUpdateKind.addVariant,
          reason: 'H3: a Change-exercise swap is saved as a variant');
      expect(c.programExerciseId, rowSlotId);
      expect(c.slotName, 'Row');
      expect(kindOf(list, 'curl').kind, ProgramUpdateKind.add,
          reason: 'an inserted exercise is still ADD TO DAY');
      expect(list.where((u) => u.exerciseId == ex['db']), isEmpty,
          reason: 'under its own target, no PR: nothing to offer');
    });

    test('the summary marks variants and keeps them in plan', () async {
      final s = await container.read(sessionSummaryProvider(vSessionId).future);
      final m = s!.exercises.singleWhere((e) => e.exerciseId == ex['machine']);
      expect(m.isVariant, isTrue);
      expect(m.inPlan, isTrue);
      expect(m.variantOfName, 'Shoulder Press');
      expect(m.planVariant!.defaultWeightKg, 40);
      expect(m.variantSlotPe!.id, pressSlotId);
      final c = s.exercises.singleWhere((e) => e.exerciseId == ex['cable']);
      expect(c.isVariant, isFalse);
      expect(c.inPlan, isFalse);
      expect(c.substituteSlotPe!.id, rowSlotId);
    });

    test('raiseVariant changes the variant row only; undo restores it',
        () async {
      final pDao = ProgramDao(db);
      await vCtrl().applyOne(ex['machine']!);
      var variants = await pDao.listVariants(pressSlotId);
      expect(
        variants.singleWhere((v) => v.variant.id == machineVariantId)
            .variant.defaultWeightKg,
        45,
      );
      expect(
        variants.singleWhere((v) => v.variant.id == dbVariantId)
            .variant.defaultWeightKg,
        22.5,
      );
      final base = (await pDao.listProgramExercises(vDayId))
          .singleWhere((v) => v.pe.id == pressSlotId);
      expect(base.pe.defaultWeightKg, 60, reason: 'the base never moves');

      await vCtrl().undoOne(ex['machine']!);
      variants = await pDao.listVariants(pressSlotId);
      expect(
        variants.singleWhere((v) => v.variant.id == machineVariantId)
            .variant.defaultWeightKg,
        40,
      );
      expect(kindOf(await vUpdates(), 'machine').applied, isFalse);
    });

    test('a variant\'s summary target is its own prescription; the DB '
        'variant inherits the slot\'s', () async {
      final s = await container.read(sessionSummaryProvider(vSessionId).future);
      final m = s!.exercises.singleWhere((e) => e.exerciseId == ex['machine']);
      final mp = m.variantPlan!;
      expect(
        [mp.targetSets, mp.targetRepsMin, mp.targetRepsMax, mp.dropCount],
        [3, 6, 8, 1],
      );
      expect(mp.defaultWeightKg, 40);
      final d = s.exercises.singleWhere((e) => e.exerciseId == ex['db']);
      final dp = d.variantPlan!;
      expect(
        [dp.targetSets, dp.targetRepsMin, dp.targetRepsMax, dp.dropCount],
        [2, 8, 10, 0],
        reason: 'NULLs inherit the slot',
      );
      expect(dp.defaultWeightKg, 22.5);
    });

    test('raiseVariant moves the weight only; undo restores every field',
        () async {
      final pDao = ProgramDao(db);
      Future<List<Object?>> machineRow() async {
        final v = (await pDao.listVariants(pressSlotId))
            .singleWhere((v) => v.variant.id == machineVariantId)
            .variant;
        return [
          v.exerciseId,
          v.position,
          v.defaultWeightKg,
          v.weightStepKg,
          v.targetSets,
          v.targetRepsMin,
          v.targetRepsMax,
          v.dropCount,
        ];
      }

      final before = await machineRow();
      await vCtrl().applyOne(ex['machine']!);
      expect(await machineRow(), [...before.take(2), 45.0, ...before.skip(3)]);
      await vCtrl().undoOne(ex['machine']!);
      expect(await machineRow(), before);
    });

    test('SAVE AS VARIANT stores the swap\'s session prescription', () async {
      await vCtrl().applyOne(ex['cable']!);
      final v = (await ProgramDao(db).listVariants(rowSlotId)).single.variant;
      expect(
        [v.targetSets, v.targetRepsMin, v.targetRepsMax, v.dropCount],
        [3, 10, 12, 1],
        reason: 'the override row\'s targets',
      );
      expect(v.defaultWeightKg, 55, reason: 'today\'s top weight');
    });

    test('SAVE AS VARIANT falls back to what was done once the slot moved on',
        () async {
      // Back on the row afterwards: the override now runs the base and only
      // remembers the cable as its previous exercise.
      await WorkoutDao(db).upsertOverride(
        sessionId: vSessionId,
        programExerciseId: rowSlotId,
        exerciseId: ex['row']!,
        previousExerciseId: ex['cable'],
        targetSets: 2,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 60,
      );
      final u = kindOf(await vUpdates(), 'cable');
      expect(u.kind, ProgramUpdateKind.addVariant);
      expect(
        [u.targetSets, u.targetRepsMin, u.targetRepsMax, u.dropCount],
        [2, 8, 8, 0],
        reason: '2 sets of 8 logged, no drops',
      );
    });

    test('addVariant creates the variant; undo deletes exactly that row',
        () async {
      final pDao = ProgramDao(db);
      await vCtrl().applyOne(ex['cable']!);
      var rowVariants = await pDao.listVariants(rowSlotId);
      expect(rowVariants.single.exerciseName, 'Cable Row');
      expect(rowVariants.single.variant.defaultWeightKg, 55);
      final applied = kindOf(await vUpdates(), 'cable');
      expect(applied.applied, isTrue);
      expect(applied.createdVariantId, rowVariants.single.variant.id);
      expect((await pDao.listProgramExercises(vDayId)).length, 2,
          reason: 'no slot was added');

      await vCtrl().undoOne(ex['cable']!);
      rowVariants = await pDao.listVariants(rowSlotId);
      expect(rowVariants, isEmpty);
      expect((await pDao.listVariants(pressSlotId)).length, 2,
          reason: 'other variants untouched');
      expect(kindOf(await vUpdates(), 'cable').createdVariantId, isNull);
    });

    test('H4: first exposure reads FIRST TIME, not a PR', () async {
      final prs = await container.read(sessionPrsProvider(vSessionId).future);
      expect(prs[ex['press']]!.isFirstExposure, isTrue,
          reason: 'never logged before today');
      expect(prs[ex['press']]!.kind, PrKind.weight,
          reason: 'the detector itself is unchanged (dao_test still holds)');
      expect(prs[ex['machine']]!.isFirstExposure, isFalse);

      final s = await container.read(sessionSummaryProvider(vSessionId).future);
      final press = s!.exercises.singleWhere((e) => e.exerciseId == ex['press']);
      expect(press.pr, isNull);
      expect(press.isPr, isFalse);
      expect(press.isFirstExposure, isTrue);
      final machine =
          s.exercises.singleWhere((e) => e.exerciseId == ex['machine']);
      expect(machine.isPr, isTrue, reason: '45 beats its earlier 40');
      expect(machine.isFirstExposure, isFalse);
      expect(s.prCount, 2,
          reason: 'machine 45 > 40 and cable 55 > 50; press is not counted');
    });

    test('DEC-0007 #10: History detail and its share card follow the summary',
        () async {
      // History detail builds its share card straight from the detector, as
      // SessionDetailScreen does — it must agree with the summary.
      final prs = await container.read(sessionPrsProvider(vSessionId).future);
      final detail =
          await container.read(sessionDetailProvider(vSessionId).future);
      final share = WorkoutSummary.fromSession(
        date: detail!.session.startedAt,
        duration: detail.session.duration,
        sets: detail.sets,
        exerciseNames: detail.exerciseNames,
        prs: prs,
      );
      final press =
          share.lines.singleWhere((l) => l.exercise == 'Shoulder Press');
      expect(press.isPr, isFalse, reason: 'first exposure: no PR badge');
      expect(press.isFirstExposure, isTrue);
      final machine = share.lines
          .singleWhere((l) => l.exercise == 'Shoulder Press (Machine)');
      expect(machine.isPr, isTrue);
      expect(machine.isFirstExposure, isFalse);
      final s = await container.read(sessionSummaryProvider(vSessionId).future);
      expect(share.prCount, s!.prCount);
    });

    test('H4: a first exposure still offers a raise when it beats the target',
        () async {
      // Press: first time today, 62.5 > 60 target.
      expect(kindOf(await vUpdates(), 'press').kind, ProgramUpdateKind.raise);
    });

    test('H4: a first exposure under its target offers nothing', () async {
      // A new variant with no history, logged under its target: before H4
      // the guaranteed weight PR would have offered a raise.
      final pDao = ProgramDao(db);
      final wDao = WorkoutDao(db);
      final band = await pDao.addVariant(
        programExerciseId: pressSlotId,
        exerciseName: 'Band Press',
        defaultWeightKg: 30,
      );
      final s = await wDao.startSession(vDayId);
      await logSets(wDao, s.id, band.exerciseId, 20);
      await wDao.completeSession(s.id);
      final list =
          await container.read(programUpdatesProvider(s.id).future);
      expect(list.where((u) => u.exerciseId == band.exerciseId), isEmpty);
      final summary = await container.read(sessionSummaryProvider(s.id).future);
      expect(summary!.exercises.single.isFirstExposure, isTrue);
      expect(summary.exercises.single.pr, isNull);
    });

    // SOW-14 day rule (D-0011): persisting an inserted exercise to the plan
    // is refused when it has become a variant on the day since.
    test('ADD TO DAY is refused once the exercise is a variant on the day',
        () async {
      expect(kindOf(await vUpdates(), 'curl').kind, ProgramUpdateKind.add);
      final pDao = ProgramDao(db);
      await pDao.addVariant(
        programExerciseId: rowSlotId,
        exerciseName: 'Curl',
        defaultWeightKg: 10,
      );
      final conflict = await vCtrl().applyOne(ex['curl']!);
      expect(conflict?.reason, VariantConflictReason.variantOfAnotherSlot);
      expect(kindOf(await vUpdates(), 'curl').applied, isFalse);
      expect((await pDao.listProgramExercises(vDayId)).length, 2);
      expect(await vCtrl().applyAll(), 3, reason: 'the refused one is skipped');
      expect(kindOf(await vUpdates(), 'curl').applied, isFalse);
    });

    test('applyAll / undoAll count the new kinds', () async {
      expect(await vCtrl().applyAll(), 4);
      expect((await vUpdates()).every((u) => u.applied), isTrue);
      expect(await vCtrl().applyAll(), 0);
      expect(await vCtrl().undoAll(), 4);
      final pDao = ProgramDao(db);
      expect(await pDao.listVariants(rowSlotId), isEmpty);
      expect(
        (await pDao.listVariants(pressSlotId))
            .map((v) => v.variant.defaultWeightKg),
        [40, 22.5],
      );
      expect((await pDao.listProgramExercises(vDayId)).length, 2);
    });
  });

  group('attributeToSlots', () {
    test('this session\'s override decides between two slots', () async {
      final pDao = ProgramDao(db);
      final p = await pDao.createProgram('X');
      final d = await pDao.createDay(p.id, 'D');
      Future<String> slot(String n) async => (await pDao.addProgramExercise(
            programDayId: d.id,
            exerciseName: n,
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            defaultWeightKg: 50,
          ))
              .id;
      final a = await slot('Incline Press');
      final b = await slot('Flat Press');
      final va = await pDao.addVariant(
          programExerciseId: a, exerciseName: 'Machine Press', defaultWeightKg: 30);
      // The DAO now refuses a variant shared by two slots of one day (SOW-14
      // day rule), so the pure function is fed the pre-rule shape directly.
      await expectLater(
        pDao.addVariant(
            programExerciseId: b,
            exerciseName: 'Machine Press',
            defaultWeightKg: 50),
        throwsA(isA<VariantConflict>()),
      );
      final vb = ProgramExerciseVariant(
        id: 'vb',
        programExerciseId: b,
        exerciseId: va.exerciseId,
        position: 0,
        defaultWeightKg: 50,
      );
      final slots = await pDao.listProgramExercises(d.id);
      final variants = {
        ...await pDao.listVariantsForDay(d.id),
        b: [ProgramExerciseVariantView(variant: vb, exerciseName: 'Machine Press')],
      };

      final noOverride = attributeToSlots(
        exerciseIds: [va.exerciseId],
        slots: slots,
        variantsBySlot: variants,
        overrides: const [],
      );
      expect(noOverride[va.exerciseId]!.variant!.id, va.id,
          reason: 'first slot in day order');

      final w = WorkoutDao(db);
      final s = await w.startSession(d.id);
      await w.upsertOverride(
        sessionId: s.id,
        programExerciseId: b,
        exerciseId: vb.exerciseId,
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
      final withOverride = attributeToSlots(
        exerciseIds: [va.exerciseId],
        slots: slots,
        variantsBySlot: variants,
        overrides: await w.overridesForSession(s.id),
      );
      expect(withOverride[va.exerciseId]!.variant!.id, vb.id);
      expect(withOverride[va.exerciseId]!.slot.pe.id, b);
    });
  });

  // Review #6: B → X → Y → Z with "Change exercise" leaves only Z (exercise)
  // and Y (previous) on the override row; X used to fall through to ADD TO
  // DAY instead of SAVE AS VARIANT.
  group('attributeToSlots: a swap chain', () {
    late String dayId;
    late String rowSlot;
    late String pressSlot;
    late Map<String, String> ex;
    late WorkoutDao w;
    late String sid;

    setUp(() async {
      final pDao = ProgramDao(db);
      w = WorkoutDao(db);
      final p = await pDao.createProgram('Chain');
      dayId = (await pDao.createDay(p.id, 'D')).id;
      Future<String> slot(String n) async => (await pDao.addProgramExercise(
            programDayId: dayId,
            exerciseName: n,
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 10,
            defaultWeightKg: 50,
          ))
              .id;
      rowSlot = await slot('Row');
      pressSlot = await slot('Press');
      ex = {
        for (final n in ['Row', 'Cable Row', 'T-Bar Row', 'Seal Row', 'Curl'])
          n: (await pDao.findOrCreateExercise(n)).id,
      };
      sid = (await w.startSession(dayId)).id;
      // Row → Cable Row → T-Bar Row → Seal Row: the row keeps the last two.
      await w.upsertOverride(
        sessionId: sid,
        programExerciseId: rowSlot,
        exerciseId: ex['Seal Row']!,
        previousExerciseId: ex['T-Bar Row'],
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
    });

    Future<Map<String, SlotAttribution>> attribute() async {
      final pDao = ProgramDao(db);
      return attributeToSlots(
        exerciseIds: [ex['Cable Row']!, ex['T-Bar Row']!, ex['Seal Row']!],
        slots: await pDao.listProgramExercises(dayId),
        variantsBySlot: await pDao.listVariantsForDay(dayId),
        overrides: await w.overridesForSession(sid),
      );
    }

    test('every link lands on the swapped slot', () async {
      final a = await attribute();
      for (final n in ['Cable Row', 'T-Bar Row', 'Seal Row']) {
        expect(a[ex[n]]?.slot.pe.id, rowSlot, reason: n);
        expect(a[ex[n]]!.variant, isNull);
      }
    });

    test('ambiguous with two swapped slots: the lost link stays ADD',
        () async {
      await w.upsertOverride(
        sessionId: sid,
        programExerciseId: pressSlot,
        exerciseId: ex['Curl']!,
        previousExerciseId: null,
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
      final a = await attribute();
      expect(a[ex['Cable Row']], isNull);
      expect(a[ex['T-Bar Row']]?.slot.pe.id, rowSlot);
    });

    test('not when an inserted exercise was swapped too', () async {
      final id = await w.insertSessionExercise(
        sessionId: sid,
        exerciseId: ex['Curl']!,
        targetSets: 2,
        targetRepsMin: 10,
        targetRepsMax: 12,
        defaultWeightKg: 10,
        orderPos: 5,
      );
      await w.upsertOverride(
        sessionId: sid,
        programExerciseId: id,
        exerciseId: ex['Curl']!,
        previousExerciseId: ex['Row'],
        targetSets: 2,
        targetRepsMin: 10,
        targetRepsMax: 12,
        defaultWeightKg: 10,
        inserted: true,
        orderPos: 5,
      );
      expect((await attribute())[ex['Cable Row']], isNull);
    });
  });

  group('classifyProgress', () {
    test('heavier wins', () {
      expect(
        classifyProgress(
            topWeightKg: 100, topReps: 5, prevTopWeightKg: 95, prevTopReps: 8),
        ProgressDelta.up,
      );
    });
    test('at equal weight, reps decide', () {
      expect(
        classifyProgress(
            topWeightKg: 100, topReps: 6, prevTopWeightKg: 100, prevTopReps: 5),
        ProgressDelta.up,
      );
      expect(
        classifyProgress(
            topWeightKg: 100, topReps: 4, prevTopWeightKg: 100, prevTopReps: 5),
        ProgressDelta.down,
      );
      expect(
        classifyProgress(
            topWeightKg: 100, topReps: 5, prevTopWeightKg: 100, prevTopReps: 5),
        ProgressDelta.matched,
      );
    });
    test('no previous data reads as new', () {
      expect(
        classifyProgress(
            topWeightKg: 100, topReps: 5, prevTopWeightKg: null, prevTopReps: null),
        ProgressDelta.fresh,
      );
    });
  });
}
