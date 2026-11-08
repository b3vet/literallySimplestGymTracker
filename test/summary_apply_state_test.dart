import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
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
