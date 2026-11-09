import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_provider.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/presentation/program_delete.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/live_activity_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/rest_timer_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/summary_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/watch_snapshot.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/features/workout/domain/active_session.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_session.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-15: deleting an exercise from a day while a workout runs on it. The
/// workout keeps going without the slot; sets already logged stay; nothing
/// downstream (cursor, watch, Live Activity, summary suggestions) keeps
/// pointing at the deleted slot.
class _FakeLiveActivity extends LiveActivityController {
  final updates = <ActiveSession>[];
  @override
  Future<void> start({
    required ActiveSession session,
    required WeightUnit unit,
    required LsAccentSpec accent,
    DateTime? restEndsAt,
  }) async {}
  @override
  Future<void> update({
    required ActiveSession session,
    required WeightUnit unit,
    required LsAccentSpec accent,
    DateTime? restEndsAt,
  }) async =>
      updates.add(session);
  var ends = 0;
  @override
  Future<void> end() async => ends++;
  @override
  Future<void> endAll() async => ends++;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String dayId;
  late String pressSlot; // Shoulder Press, with two variants
  late String raiseSlot; // Lateral Raise
  late String curlSlot; // Curl
  late String pressId;
  late String machineId;
  late String raiseId;

  setUp(() async {
    db = await openTestDb();
    dao = ProgramDao(db);
    final p = await dao.createProgram('P');
    dayId = (await dao.createDay(p.id, 'Push')).id;
    Future<String> add(String name, int sets) async => (await dao
            .addProgramExercise(
              programDayId: dayId,
              exerciseName: name,
              targetSets: sets,
              targetRepsMin: 8,
              targetRepsMax: 10,
              defaultWeightKg: 20,
            ))
        .id;
    pressSlot = await add('Shoulder Press', 2);
    raiseSlot = await add('Lateral Raise', 2);
    curlSlot = await add('Curl', 2);
    pressId = (await dao.findProgramExercise(pressSlot))!.exerciseId;
    raiseId = (await dao.findProgramExercise(raiseSlot))!.exerciseId;
    machineId = (await dao.addVariant(
      programExerciseId: pressSlot,
      exerciseName: 'Shoulder Press (Machine)',
      defaultWeightKg: 40,
    ))
        .exerciseId;
    await dao.addVariant(
      programExerciseId: pressSlot,
      exerciseName: 'Shoulder Press (DB)',
      defaultWeightKg: 15,
    );
  });
  tearDown(() async => db.close());

  Future<(ProviderContainer, _FakeLiveActivity)> container({
    bool liveActivity = false,
  }) async {
    SharedPreferences.setMockInitialValues(
        {'settings.live_activity': liveActivity});
    final prefs = await SharedPreferences.getInstance();
    final la = _FakeLiveActivity();
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      liveActivityControllerProvider.overrideWithValue(la),
    ]);
    addTearDown(c.dispose);
    await c.read(activeSessionProvider.future);
    return (c, la);
  }

  ActiveSession session(ProviderContainer c) =>
      c.read(activeSessionProvider).value!;
  ActiveWorkoutController ctrl(ProviderContainer c) =>
      c.read(activeSessionProvider.notifier);
  Future<void> log(ProviderContainer c, [int n = 1]) async {
    for (var i = 0; i < n; i++) {
      await ctrl(c).logSet(reps: 8, weightKg: 20, rir: 1);
    }
  }

  /// The UI's path: what the row button, the swipe and the edit sheet run.
  Future<void> deleteSlot(ProviderContainer c, String slotId) =>
      deleteExerciseConfirmed(c, programExerciseId: slotId, dayId: dayId);

  List<String> names(ProviderContainer c) =>
      [for (final pe in session(c).queue) pe.exerciseName];

  group('DAO', () {
    test('cascades the variants; keeps sets; no marker without a workout',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await log(c, 2);
      final sid = session(c).sessionId;
      await ctrl(c).finish();

      await dao.deleteProgramExercise(pressSlot);
      expect(await dao.findProgramExercise(pressSlot), isNull);
      final variants = await db.query('program_exercise_variants',
          where: 'program_exercise_id = ?', whereArgs: [pressSlot]);
      expect(variants, isEmpty);
      expect((await WorkoutDao(db).setsForSession(sid)).length, 2);
      expect(await WorkoutDao(db).overridesForSession(sid), isEmpty,
          reason: 'the session was not running');
    });

    test('marks the running workout\'s slot dropped (new row)', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      expect(await dao.hasActiveWorkoutOnSlot(raiseSlot), isTrue);
      await dao.deleteProgramExercise(raiseSlot);
      final o = (await WorkoutDao(db).overridesForSession(
              session(c).sessionId))
          .single;
      expect(o.programExerciseId, raiseSlot);
      expect(o.exerciseId, raiseId);
      expect(o.skipped, isTrue);
      expect(o.inserted, isFalse);
    });

    test('…and keeps an existing override, marked skipped', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).switchVariant(0, machineId);
      await dao.deleteProgramExercise(pressSlot);
      final o = (await WorkoutDao(db).overridesForSession(
              session(c).sessionId))
          .single;
      expect(o.exerciseId, machineId);
      expect(o.previousExerciseId, pressId);
      expect(o.skipped, isTrue);
    });

    test('hasActiveWorkoutOnSlot is false without a workout on the day',
        () async {
      expect(await dao.hasActiveWorkoutOnSlot(raiseSlot), isFalse);
      final other = await dao.createDay(
          (await dao.findDay(dayId))!.programId, 'Pull');
      final row = await dao.addProgramExercise(
        programDayId: other.id,
        exerciseName: 'Row',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
      await WorkoutDao(db).startSession(dayId);
      expect(await dao.hasActiveWorkoutOnSlot(row.id), isFalse);
      expect(await dao.hasActiveWorkoutOnSlot(raiseSlot), isTrue);
    });
  });

  group('live workout', () {
    // Characterization of the bug: before SOW-15 the queue kept the deleted
    // slot until the next cold start.
    test('the deleted slot leaves the queue at once', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await deleteSlot(c, curlSlot);
      expect(names(c), ['Shoulder Press', 'Lateral Raise']);
    });

    test('deleting the current exercise moves to the next one', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await log(c, 2); // press done → cursor on Lateral Raise
      await log(c); // 1 of 2 on the raise
      expect(session(c).cursor.exerciseIdx, 1);
      await deleteSlot(c, raiseSlot);
      expect(names(c), ['Shoulder Press', 'Curl']);
      expect(session(c).cursor.exerciseIdx, 1);
      expect(session(c).currentExercise!.exerciseName, 'Curl');
      expect(session(c).cursor.setIdx, 0);
      expect(
        session(c).loggedSets.where((s) => s.exerciseId == raiseId).length,
        1,
        reason: 'the set already logged stays',
      );
    });

    test('deleting an earlier exercise keeps the current one current',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await log(c, 2);
      await log(c); // on the raise, 1 logged
      await deleteSlot(c, pressSlot);
      expect(names(c), ['Lateral Raise', 'Curl']);
      expect(session(c).currentExercise!.exerciseName, 'Lateral Raise');
      expect(session(c).cursor.exerciseIdx, 0);
    });

    test('deleting the current last exercise falls back to sets left',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).goToExerciseIndex(2); // on Curl, press still open
      await deleteSlot(c, curlSlot);
      expect(session(c).currentExercise!.exerciseName, 'Shoulder Press');
    });

    test('deleting the last remaining exercise: still open, finish works',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await log(c);
      final sid = session(c).sessionId;
      await deleteSlot(c, raiseSlot);
      await deleteSlot(c, curlSlot);
      await deleteSlot(c, pressSlot);
      expect(session(c).queue, isEmpty);
      expect(session(c).isFinished, isTrue);
      expect(session(c).currentExercise, isNull);
      expect((await WorkoutDao(db).findSession(sid))!.status,
          SessionStatus.active);
      await ctrl(c).goNext(); // no crash on an empty queue
      await ctrl(c).skipCurrentExercise();
      expect(await ctrl(c).finish(), sid);
      expect((await WorkoutDao(db).findSession(sid))!.status,
          SessionStatus.completed);
      expect((await WorkoutDao(db).setsForSession(sid)).length, 1);
    });

    // D-0017 review #2: the next slot after the deleted current one was
    // already complete — the cursor must not land on it (Curl at set 3/2).
    test('deleting the current exercise skips a completed next slot',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).goToExerciseIndex(2);
      await log(c, 2); // Curl done
      await ctrl(c).goToExerciseIndex(1); // back on the raise; press untouched
      expect(session(c).currentExercise!.exerciseName, 'Lateral Raise');
      await deleteSlot(c, raiseSlot);
      expect(names(c), ['Shoulder Press', 'Curl']);
      expect(session(c).currentExercise!.exerciseName, 'Shoulder Press');
      expect(session(c).cursor.setIdx, 0);
    });

    // D-0017 review #5: with nothing logged, an emptied workout used to stay
    // open and FINISH saved an empty completed workout in History, while a
    // cold start abandoned it. Now it is abandoned at once, as on resume.
    test('deleting every exercise with nothing logged abandons the workout',
        () async {
      final (c, la) = await container(liveActivity: true);
      await ctrl(c).start(dayId);
      final sid = session(c).sessionId;
      await deleteSlot(c, raiseSlot);
      await deleteSlot(c, curlSlot);
      expect(c.read(activeSessionProvider).value, isNotNull);
      expect(la.ends, 0);
      await deleteSlot(c, pressSlot);
      expect(c.read(activeSessionProvider).value, isNull);
      expect((await WorkoutDao(db).findSession(sid))!.status,
          SessionStatus.abandoned);
      expect(await WorkoutDao(db).findActiveSession(), isNull);
      expect(la.ends, greaterThan(0), reason: 'the Live Activity ends');
      expect(await ctrl(c).finish(), isNull,
          reason: 'nothing left to save as a completed workout');
    });

    test('…but an inserted exercise keeps it open', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).insertExercise(
        name: 'Face Pull',
        targetSets: 2,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 10,
      );
      for (final s in [pressSlot, raiseSlot, curlSlot]) {
        await deleteSlot(c, s);
      }
      expect(names(c), ['Face Pull']);
      expect(c.read(activeSessionProvider).value, isNotNull);
    });

    test('a variant switched in: the slot leaves; its sets stay', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).switchVariant(0, machineId);
      await log(c);
      await deleteSlot(c, pressSlot);
      expect(names(c), ['Lateral Raise', 'Curl']);
      expect(session(c).currentExercise!.exerciseName, 'Lateral Raise');
      expect(
        session(c).loggedSets.single.exerciseId,
        machineId,
      );
    });

    test('a swapped slot ("Change exercise") leaves too', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).substituteExercise(
        queueIdx: 1,
        exerciseName: 'Cable Raise',
        targetSets: 2,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 5,
      );
      await deleteSlot(c, raiseSlot);
      expect(names(c), ['Shoulder Press', 'Curl']);
    });

    test('an inserted exercise stays', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).insertExercise(
        name: 'Face Pull',
        targetSets: 2,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 10,
      );
      await deleteSlot(c, pressSlot);
      expect(names(c), ['Face Pull', 'Lateral Raise', 'Curl']);
    });

    // The delete renumbers the day's slots; an inserted exercise's key is
    // remapped with them, so it keeps its place now, on resume, and for a
    // later insert.
    test('an inserted exercise keeps its place across the renumbering',
        () async {
      final (first, _) = await container();
      await ctrl(first).start(dayId);
      await log(first, 2); // Press done → cursor on Lateral Raise
      await ctrl(first).insertExercise(
        name: 'Face Pull',
        targetSets: 2,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 10,
      ); // between Lateral Raise and Curl
      await deleteSlot(first, pressSlot);
      expect(names(first), ['Lateral Raise', 'Face Pull', 'Curl']);
      expect([for (final s in session(first).queue) s.position], [0, 0.5, 1]);
      await log(first, 2); // Lateral Raise done → cursor on Face Pull
      await ctrl(first).insertExercise(
        name: 'Dip',
        targetSets: 2,
        targetRepsMin: 8,
        targetRepsMax: 12,
        defaultWeightKg: 0,
      ); // after Face Pull, before Curl
      expect(names(first), ['Lateral Raise', 'Face Pull', 'Dip', 'Curl']);
      first.dispose();

      final (c, _) = await container();
      expect(names(c), ['Lateral Raise', 'Face Pull', 'Dip', 'Curl']);
    });

    test('a delete on another day changes nothing', () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      final other = await dao.createDay(
          (await dao.findDay(dayId))!.programId, 'Pull');
      final row = await dao.addProgramExercise(
        programDayId: other.id,
        exerciseName: 'Row',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
      final before = session(c);
      await deleteExerciseConfirmed(c,
          programExerciseId: row.id, dayId: other.id);
      expect(identical(session(c), before), isTrue);
    });

    test('watch snapshot and Live Activity drop the slot', () async {
      final (c, la) = await container(liveActivity: true);
      await ctrl(c).start(dayId);
      await deleteSlot(c, raiseSlot);
      final snap = buildWatchSnapshot(
        session: session(c),
        rest: c.read(restTimerProvider),
        settings: c.read(settingsProvider),
      );
      expect(snap.queue.map((e) => e.programExerciseId),
          [pressSlot, curlSlot]);
      expect(snap.cursorExerciseIdx, 0);
      expect(la.updates.last.queue.map((e) => e.programExerciseId),
          [pressSlot, curlSlot]);
    });

    test('a resume does not bring the slot back; the marker is ignored',
        () async {
      final (first, _) = await container();
      await ctrl(first).start(dayId);
      await ctrl(first).switchVariant(0, machineId);
      await log(first);
      await deleteSlot(first, pressSlot);
      first.dispose();

      final (c, _) = await container();
      expect(names(c), ['Lateral Raise', 'Curl']);
      expect(session(c).currentExercise!.exerciseName, 'Lateral Raise');
      expect(session(c).loggedSets.length, 1);
    });

    // The bug found while characterizing (SOW-15 §5): with the day's last
    // exercise deleted mid-workout, a cold start used to ABANDON the session,
    // dropping its logged sets out of History, PRs and Stats.
    test('a resume after the last exercise was deleted keeps the workout',
        () async {
      final (first, _) = await container();
      await ctrl(first).start(dayId);
      await log(first, 2);
      final sid = session(first).sessionId;
      for (final s in [pressSlot, raiseSlot, curlSlot]) {
        await deleteSlot(first, s);
      }
      first.dispose();

      final (c, _) = await container();
      expect(c.read(activeSessionProvider).value, isNotNull);
      expect(session(c).queue, isEmpty);
      expect(session(c).isFinished, isTrue);
      expect(session(c).loggedSets.length, 2);
      expect((await WorkoutDao(db).findSession(sid))!.status,
          SessionStatus.active);
      await ctrl(c).finish();
      expect((await WorkoutDao(db).findSession(sid))!.status,
          SessionStatus.completed);
    });

    test('…but abandons an empty one, as before', () async {
      final (first, _) = await container();
      await ctrl(first).start(dayId);
      final sid = session(first).sessionId;
      for (final s in [pressSlot, raiseSlot, curlSlot]) {
        await deleteSlot(first, s);
      }
      first.dispose();
      final (c, _) = await container();
      expect(c.read(activeSessionProvider).value, isNull);
      expect((await WorkoutDao(db).findSession(sid))!.status,
          SessionStatus.abandoned);
    });
  });

  group('summary', () {
    test('no ADD TO DAY for the deleted exercise; its sets are listed',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await log(c, 2); // press
      await log(c); // raise
      await deleteSlot(c, raiseSlot);
      await ctrl(c).insertExercise(
        name: 'Face Pull',
        targetSets: 1,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 10,
      );
      // Inserted after the current exercise (Curl, once the raise is gone).
      await ctrl(c).goToExerciseIndex(names(c).indexOf('Face Pull'));
      expect(session(c).currentExercise!.exerciseName, 'Face Pull');
      await log(c);
      final sid = (await ctrl(c).finish())!;

      final s = await c.read(sessionSummaryProvider(sid).future);
      final raise = s!.exercises.singleWhere((e) => e.exerciseId == raiseId);
      expect(raise.setCount, 1);
      expect(raise.inPlan, isFalse);
      expect(raise.droppedFromDay, isTrue);
      final updates = await c.read(programUpdatesProvider(sid).future);
      expect(updates.where((u) => u.exerciseId == raiseId), isEmpty);
      expect(
        updates.where((u) =>
            u.exerciseName == 'Face Pull' && u.kind == ProgramUpdateKind.add),
        hasLength(1),
        reason: 'an inserted exercise still offers ADD TO DAY',
      );
    });

    test('a deleted slot that ran a variant: no SAVE AS VARIANT / ADD',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).switchVariant(0, machineId);
      await log(c);
      await deleteSlot(c, pressSlot);
      final sid = (await ctrl(c).finish())!;
      final updates = await c.read(programUpdatesProvider(sid).future);
      expect(updates.where((u) => u.exerciseId == machineId), isEmpty);
      expect(updates.where((u) => u.programExerciseId == pressSlot), isEmpty);
    });

    // D-0017 review #1: with another slot swapped ("Change exercise"), the
    // swap-chain fallback used to attribute the deleted slot's exercise to
    // that slot and offer SAVE AS VARIANT: Lateral Raise → Curl.
    test('a deleted slot is not attributed to another swapped slot',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await ctrl(c).goToExerciseIndex(1);
      await log(c); // 1 set of the raise
      await ctrl(c).substituteExercise(
        queueIdx: 2,
        exerciseName: 'Cable Curl',
        targetSets: 2,
        targetRepsMin: 10,
        targetRepsMax: 12,
        defaultWeightKg: 10,
      );
      await deleteSlot(c, raiseSlot);
      final sid = (await ctrl(c).finish())!;

      final s = await c.read(sessionSummaryProvider(sid).future);
      final raise = s!.exercises.singleWhere((e) => e.exerciseId == raiseId);
      expect(raise.setCount, 1);
      expect(raise.inPlan, isFalse);
      expect(raise.substituteSlotPe, isNull);
      expect(raise.droppedFromDay, isTrue);
      final updates = await c.read(programUpdatesProvider(sid).future);
      expect(updates.where((u) => u.exerciseId == raiseId), isEmpty);
      expect(updates.where((u) => u.kind == ProgramUpdateKind.addVariant),
          isEmpty);
    });

    test('droppedSlotExerciseIds reads the marker; inserted ids excluded',
        () async {
      final (c, _) = await container();
      await ctrl(c).start(dayId);
      await deleteSlot(c, raiseSlot);
      final sid = session(c).sessionId;
      final slots = await dao.listProgramExercises(dayId);
      final overrides = await WorkoutDao(db).overridesForSession(sid);
      expect(
        droppedSlotExerciseIds(slots: slots, overrides: overrides),
        {raiseId},
      );
      await ctrl(c).insertExercise(
        name: 'Lateral Raise',
        targetSets: 1,
        targetRepsMin: 12,
        targetRepsMax: 15,
        defaultWeightKg: 10,
      );
      expect(
        droppedSlotExerciseIds(
          slots: slots,
          overrides: await WorkoutDao(db).overridesForSession(sid),
        ),
        isEmpty,
      );
    });
  });
}
