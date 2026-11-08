import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart'
    show WeightUnit;
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/history/presentation/session_detail_screen.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/share/application/summary_text.dart';
import 'package:ls_workout_tracker/features/share/domain/workout_summary.dart';
import 'package:ls_workout_tracker/features/share/presentation/summary_card.dart';
import 'package:ls_workout_tracker/features/workout/application/pr_detector.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_set.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// DEC-0007 #10: the H4 rule (a first exposure is no PR — it reads FIRST
/// TIME) holds outside the summary too: History detail, the share card and
/// the share text.
void main() {
  WorkoutSet set(String exerciseId, double kg) => WorkoutSet(
        id: '$exerciseId-$kg',
        sessionId: 's',
        exerciseId: exerciseId,
        setIndex: 0,
        reps: 8,
        weightKg: kg,
        rir: 1,
        loggedAt: DateTime(2026, 11, 9, 18),
      );

  WorkoutSummary summary() => WorkoutSummary.fromSession(
        date: DateTime(2026, 11, 9, 18),
        duration: const Duration(minutes: 40),
        sets: [set('bench', 100), set('press', 40)],
        exerciseNames: const {'bench': 'Bench Press', 'press': 'Machine Press'},
        prs: const {
          'bench': ExercisePR(
              exerciseId: 'bench',
              kind: PrKind.weight,
              weightKg: 100,
              reps: 8),
          // What PrDetector reports for a first exposure: a "weight PR".
          'press': ExercisePR(
              exerciseId: 'press',
              kind: PrKind.weight,
              weightKg: 40,
              reps: 8,
              isFirstExposure: true),
        },
      );

  test('fromSession: a first exposure is FIRST TIME and not counted', () {
    final s = summary();
    expect(s.prCount, 1);
    final bench = s.lines.singleWhere((l) => l.exercise == 'Bench Press');
    final press = s.lines.singleWhere((l) => l.exercise == 'Machine Press');
    expect(bench.isPr, isTrue);
    expect(bench.isFirstExposure, isFalse);
    expect(press.isPr, isFalse);
    expect(press.isFirstExposure, isTrue);
  });

  test('share text marks the first exposure, not as a PR', () {
    final text = buildSummaryText(summary(), WeightUnit.kg);
    expect(text, contains('Bench Press    100 kg × 8  (PR)'));
    expect(text, contains('Machine Press  40 kg × 8  (first time)'));
    expect(text, contains('1 PR'));
    expect(text, isNot(contains('2 PRs')));
  });

  testWidgets('share card: FIRST TIME label, one PR badge', (tester) async {
    tester.view.physicalSize =
        const Size(SummaryCard.cardWidth, SummaryCard.cardHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(SummaryCard.cardWidth, SummaryCard.cardHeight),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SummaryCard(
            summary: summary(),
            unit: WeightUnit.kg,
            accent: lsAccents.first,
            boundaryKey: GlobalKey(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('FIRST TIME'), findsOneWidget);
    // The per-row PR badge (the stats row's label reads "PR" too).
    expect(find.text('PR'), findsNWidgets(2));
  });

  group('History detail', () {
    setUpAll(sqfliteFfiInit);

    testWidgets('a first exposure reads FIRST TIME', (tester) async {
      late Database db;
      late String sessionId;
      await tester.runAsync(() async {
        db = await openTestDb();
        final p = ProgramDao(db);
        final w = WorkoutDao(db);
        final program = await p.createProgram('PPL');
        final day = await p.createDay(program.id, 'Push');
        final bench = await p.addProgramExercise(
          programDayId: day.id,
          exerciseName: 'Bench Press',
          targetSets: 1,
          targetRepsMin: 8,
          targetRepsMax: 8,
          defaultWeightKg: 80,
        );
        final press = await p.findOrCreateExercise('Machine Press');
        final earlier = await w.startSession(day.id);
        await w.insertSet(
            sessionId: earlier.id,
            exerciseId: bench.exerciseId,
            setIndex: 0,
            reps: 8,
            weightKg: 80,
            rir: 1);
        await w.completeSession(earlier.id);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final today = await w.startSession(day.id);
        sessionId = today.id;
        await w.insertSet(
            sessionId: today.id,
            exerciseId: bench.exerciseId,
            setIndex: 0,
            reps: 8,
            weightKg: 85,
            rir: 1);
        await w.insertSet(
            sessionId: today.id,
            exerciseId: press.id,
            setIndex: 0,
            reps: 8,
            weightKg: 40,
            rir: 1);
        await w.completeSession(today.id);
      });
      addTearDown(() => tester.runAsync(db.close));
      SharedPreferences.setMockInitialValues({'settings.unit': 'kg'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(ProviderScope(
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
          home: SessionDetailScreen(sessionId: sessionId),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      expect(find.text('MACHINE PRESS'), findsOneWidget);
      expect(find.text('FIRST TIME'), findsOneWidget,
          reason: 'only the new lift; Bench Press has history');
    });
  });
}
