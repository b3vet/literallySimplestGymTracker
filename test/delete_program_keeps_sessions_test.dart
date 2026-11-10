import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/history/application/history_provider.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/presentation/program_delete.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_session.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// DEC-0007 H5: deleting a program or a day that has logged workouts keeps the
/// workouts and detaches them from the program. Before 1.5.0 the delete threw:
/// `workout_sessions.program_day_id` references `program_days(id)` with no
/// `ON DELETE`, and foreign keys are on. Copying a program (SOW-13) makes
/// "copy it, then delete the old one" the obvious next move.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao pDao;
  late WorkoutDao wDao;
  late String programId;
  late String dayId;
  late String otherDayId;
  late String exerciseId;

  setUp(() async {
    db = await openTestDb();
    pDao = ProgramDao(db);
    wDao = WorkoutDao(db);
    final p = await pDao.createProgram('PPL');
    programId = p.id;
    dayId = (await pDao.createDay(p.id, 'Push')).id;
    otherDayId = (await pDao.createDay(p.id, 'Pull')).id;
    await pDao.addProgramExercise(
      programDayId: dayId,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 5,
      targetRepsMax: 8,
      defaultWeightKg: 60,
    );
    exerciseId = (await pDao.listProgramExercises(dayId)).first.pe.exerciseId;
  });

  tearDown(() async => db.close());

  Future<String> logCompleted(String onDay) async {
    final s = await wDao.startSession(onDay);
    await wDao.insertSet(
      sessionId: s.id,
      exerciseId: exerciseId,
      setIndex: 0,
      reps: 5,
      weightKg: 60,
      rir: 2,
    );
    await wDao.completeSession(s.id);
    return s.id;
  }

  test(
    'deleting a program keeps its workouts, detached, with every set',
    () async {
      final a = await logCompleted(dayId);
      final b = await logCompleted(otherDayId);

      await pDao.deleteProgram(programId);

      expect(await pDao.listPrograms(), isEmpty);
      expect(await pDao.listDays(programId), isEmpty, reason: 'days cascade');
      for (final id in [a, b]) {
        final s = await wDao.findSession(id);
        expect(s, isNotNull, reason: 'workout kept');
        expect(s!.programDayId, isNull, reason: 'detached from the program');
        expect(s.status, SessionStatus.completed);
        expect((await wDao.setsForSession(id)).length, 1, reason: 'sets kept');
      }
    },
  );

  test('deleting a day detaches only that day\'s workouts', () async {
    final onPush = await logCompleted(dayId);
    final onPull = await logCompleted(otherDayId);

    await pDao.deleteDay(dayId);

    expect((await wDao.findSession(onPush))!.programDayId, isNull);
    expect((await wDao.findSession(onPull))!.programDayId, otherDayId);
    expect((await pDao.listDays(programId)).map((d) => d.id), [otherDayId]);
    expect(
      await pDao.listProgramExercises(dayId),
      isEmpty,
      reason: 'slots cascade',
    );
  });

  test('History lists a detached workout as a plain workout', () async {
    final id = await logCompleted(dayId);
    await pDao.deleteProgram(programId);

    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    final rows = await c.read(historyListProvider.future);
    final row = rows.singleWhere((r) => r.session.id == id);
    expect(row.dayName, isNull);
    expect(row.programName, isNull);
    expect(row.setCount, 1);
    expect(row.topExerciseName, 'Bench Press');

    final detail = await c.read(sessionDetailProvider(id).future);
    expect(detail!.dayName, isNull);
    expect(detail.sets.length, 1);
  });

  // QA after D-0017: History kept the deleted day's label until relaunch.
  group('History refreshes after the delete flows', () {
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
      return c;
    }

    Future<void> expectLabelled(ProviderContainer c, String id,
        {required String? day, required String? program}) async {
      final row = (await c.read(historyListProvider.future))
          .singleWhere((r) => r.session.id == id);
      expect(row.dayName, day);
      expect(row.programName, program);
      expect((await c.read(sessionDetailProvider(id).future))!.dayName, day);
    }

    test('day delete', () async {
      final id = await logCompleted(dayId);
      final c = await container();
      await expectLabelled(c, id, day: 'Push', program: 'PPL');

      await deleteDayConfirmed(c, programId: programId, dayId: dayId);
      await expectLabelled(c, id, day: null, program: null);
    });

    test('program delete', () async {
      final id = await logCompleted(otherDayId);
      final c = await container();
      await expectLabelled(c, id, day: 'Pull', program: 'PPL');

      // As the programs list does it.
      await pDao.deleteProgram(programId);
      await closeWorkoutAfterDelete(c);
      await expectLabelled(c, id, day: null, program: null);
    });
  });

  group('an active workout whose day was deleted', () {
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
      return c;
    }

    test(
      'is completed on resume when it has sets, so they reach History',
      () async {
        final s = await wDao.startSession(dayId);
        await wDao.insertSet(
          sessionId: s.id,
          exerciseId: exerciseId,
          setIndex: 0,
          reps: 5,
          weightKg: 60,
          rir: 2,
        );
        await pDao.deleteProgram(programId);

        final c = await container();
        expect(await c.read(activeSessionProvider.future), isNull);
        expect((await wDao.findSession(s.id))!.status, SessionStatus.completed);
        expect(
          await wDao.findActiveSession(),
          isNull,
          reason: 'nothing left to block the next workout',
        );
      },
    );

    test('is abandoned on resume when nothing was logged', () async {
      final s = await wDao.startSession(dayId);
      await pDao.deleteDay(dayId);

      final c = await container();
      expect(await c.read(activeSessionProvider.future), isNull);
      expect((await wDao.findSession(s.id))!.status, SessionStatus.abandoned);
    });
  });
}
