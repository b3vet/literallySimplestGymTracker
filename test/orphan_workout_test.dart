import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/home/application/home_provider.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/presentation/program_delete.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/live_activity_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/rest_timer_controller.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_session.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// Review #4 / QA RISK-05: a workout whose program (or day) is deleted while
/// it runs. On a cold start it is closed on resume; in the same process the
/// delete closes it at once. Either way: ended at its last set, rest timer and
/// Live Activity torn down like `finish()`, and the delete dialog warns first.
class _FakeLiveActivity extends LiveActivityController {
  int endAllCalls = 0;
  @override
  Future<void> endAll() async => endAllCalls++;
  @override
  Future<void> end() async {}
}

void main() {
  const kRestKey = 'active_rest_ends_at_ms';
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String programId;
  late String dayId;

  setUp(() async {
    db = await openTestDb();
    dao = ProgramDao(db);
    final p = await dao.createProgram('PPL');
    programId = p.id;
    dayId = (await dao.createDay(p.id, 'Push')).id;
    await dao.addProgramExercise(
      programDayId: dayId,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 10,
      defaultWeightKg: 80,
    );
  });
  tearDown(() async => db.close());

  Future<(ProviderContainer, SharedPreferences, _FakeLiveActivity)>
      container({bool relaunch = false}) async {
    // A relaunch keeps the stored prefs (a persisted rest end-time included).
    if (!relaunch) {
      SharedPreferences.setMockInitialValues({'settings.live_activity': false});
    }
    final prefs = await SharedPreferences.getInstance();
    final la = _FakeLiveActivity();
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      liveActivityControllerProvider.overrideWithValue(la),
    ]);
    addTearDown(c.dispose);
    await c.read(activeSessionProvider.future);
    return (c, prefs, la);
  }

  Future<WorkoutSession> sessionRow(String id) async =>
      (await WorkoutDao(db).findSession(id))!;

  /// Start on the day, log [sets] sets, start a rest. Returns the session id.
  Future<String> startAndLog(ProviderContainer c, int sets) async {
    final ctrl = c.read(activeSessionProvider.notifier);
    await ctrl.start(dayId);
    for (var i = 0; i < sets; i++) {
      await ctrl.logSet(reps: 8, weightKg: 80, rir: 1);
    }
    c.read(restTimerProvider.notifier).start(90);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return c.read(activeSessionProvider).value!.sessionId;
  }

  group('resume after the program was deleted (cold start)', () {
    test('completes it, ended at its last set; rest + Live Activity end',
        () async {
      final (first, prefs, _) = await container();
      final sid = await startAndLog(first, 2);
      final lastSetAt = (await WorkoutDao(db).setsForSession(sid)).last.loggedAt;
      await dao.deleteProgram(programId);
      first.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(prefs.getInt(kRestKey), isNotNull, reason: 'rest was persisted');
      final (c, _, la) = await container(relaunch: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.read(activeSessionProvider).value, isNull);
      final row = await sessionRow(sid);
      expect(row.status, SessionStatus.completed);
      expect(row.endedAt!.millisecondsSinceEpoch,
          lastSetAt.millisecondsSinceEpoch,
          reason: 'not the relaunch time');
      expect(la.endAllCalls, 1);
      expect(prefs.getInt(kRestKey), isNull, reason: 'rest cleared');
      expect(c.read(restTimerProvider).running, isFalse);
    });

    test('Home LAST strip picks up the closed session (QA RISK-05 obs.)',
        () async {
      final (first, prefs, _) = await container();
      final sid = await startAndLog(first, 2);
      await dao.deleteProgram(programId);
      first.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Relaunch: Home reads LAST while the resume is still closing the
      // orphan, so its first answer predates the close.
      final la = _FakeLiveActivity();
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        liveActivityControllerProvider.overrideWithValue(la),
      ]);
      addTearDown(c.dispose);
      c.listen(lastSessionSummaryProvider, (_, _) {});
      final early = c.read(lastSessionSummaryProvider.future);
      await c.read(activeSessionProvider.future);
      await early;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect((await sessionRow(sid)).status, SessionStatus.completed);
      final last = await c.read(lastSessionSummaryProvider.future);
      expect(last?.session.id, sid);
      expect(last?.setCount, 2);
    });

    test('abandons it when nothing was logged', () async {
      final (first, _, _) = await container();
      final sid = await startAndLog(first, 0);
      await dao.deleteDay(dayId);
      first.dispose();

      final (c, _, la) = await container(relaunch: true);
      expect(c.read(activeSessionProvider).value, isNull);
      expect((await sessionRow(sid)).status, SessionStatus.abandoned);
      expect(la.endAllCalls, 1);
    });
  });

  group('closeIfDetached (same process, right after the delete)', () {
    test('closes the workout so RESUME is no longer offered', () async {
      final (c, prefs, la) = await container();
      final sid = await startAndLog(c, 1);
      final lastSetAt = (await WorkoutDao(db).setsForSession(sid)).last.loggedAt;
      expect(await dao.hasActiveWorkout(programId: programId), isTrue);
      expect(await dao.hasActiveWorkout(dayId: dayId), isTrue);

      await dao.deleteDay(dayId);
      expect(
        await c.read(activeSessionProvider.notifier).closeIfDetached(),
        isTrue,
      );
      expect(c.read(activeSessionProvider).value, isNull);
      final row = await sessionRow(sid);
      expect(row.status, SessionStatus.completed);
      expect(row.endedAt!.millisecondsSinceEpoch,
          lastSetAt.millisecondsSinceEpoch);
      expect(la.endAllCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(prefs.getInt(kRestKey), isNull);
      expect(await WorkoutDao(db).findActiveSession(), isNull);
    });

    test('leaves a workout whose day still exists alone', () async {
      final (c, _, la) = await container();
      await startAndLog(c, 1);
      final other = await dao.createProgram('Other');
      await dao.deleteProgram(other.id);
      expect(
        await c.read(activeSessionProvider.notifier).closeIfDetached(),
        isFalse,
      );
      expect(c.read(activeSessionProvider).value, isNotNull);
      expect(la.endAllCalls, 0);
      expect(await dao.hasActiveWorkout(programId: other.id), isFalse);
    });
  });

  group('delete confirmation', () {
    Future<void> pumpAndOpen(
      WidgetTester tester, {
      String? programId,
      String? dayId,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            builder: (context, child) => LsTheme(
              surface: lsDark,
              accent: lsAccentSpec(LsAccent.red),
              brightness: Brightness.dark,
              child: child!,
            ),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => confirmProgramDelete(
                      context,
                      ref,
                      label: 'PPL',
                      programId: programId,
                      dayId: dayId,
                    ),
                    child: const Text('OPEN'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('warns when the running workout is on the program', (
      tester,
    ) async {
      await tester.runAsync(() => WorkoutDao(db).startSession(dayId));
      await pumpAndOpen(tester, programId: programId);
      expect(find.text('DELETE?'), findsOneWidget);
      expect(find.text(deleteEndsWorkoutWarning('program')), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
    });

    testWidgets('…and on the day', (tester) async {
      await tester.runAsync(() => WorkoutDao(db).startSession(dayId));
      await pumpAndOpen(tester, dayId: dayId);
      expect(find.text(deleteEndsWorkoutWarning('day')), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
    });

    testWidgets('no warning without a running workout', (tester) async {
      await pumpAndOpen(tester, programId: programId);
      expect(find.text('DELETE?'), findsOneWidget);
      expect(find.textContaining('in progress'), findsNothing);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
    });
  });
}
