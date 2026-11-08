import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/presentation/day_editor_screen.dart';
import 'package:ls_workout_tracker/features/programs/presentation/program_editor_screen.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-13 entry points: the duplicate icon in the program and day editors.
/// DB work runs on a real isolate, so every wait for it goes through
/// `tester.runAsync`.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String programId;
  late String dayId;

  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpAt(WidgetTester tester, String location) async {
    SharedPreferences.setMockInitialValues({'settings.unit': 'kg'});
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/programs/:pid',
          builder: (_, s) =>
              ProgramEditorScreen(programId: s.pathParameters['pid']!),
          routes: [
            GoRoute(
              path: 'days/:did',
              builder: (_, s) => DayEditorScreen(
                programId: s.pathParameters['pid']!,
                dayId: s.pathParameters['did']!,
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => LsTheme(
            surface: lsDark,
            accent: lsAccentSpec(LsAccent.red),
            brightness: Brightness.dark,
            child: child!,
          ),
        ),
      ),
    );
    await settleDb(tester);
  }

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await openTestDb();
      dao = ProgramDao(db);
      final p = await dao.createProgram('Strength');
      programId = p.id;
      final d = await dao.createDay(p.id, 'Push');
      dayId = d.id;
      await dao.addProgramExercise(
        programDayId: d.id,
        exerciseName: 'Bench Press',
        targetSets: 3,
        targetRepsMin: 5,
        targetRepsMax: 8,
        defaultWeightKg: 80,
      );
    });
  }

  Future<void> closeDb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.close());
  }

  testWidgets('program editor: icon present; cancel creates nothing', (
    tester,
  ) async {
    await seed(tester);
    await pumpAt(tester, '/programs/$programId');

    final icon = find.bySemanticsLabel('Duplicate program');
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('DUPLICATE PROGRAM'), findsOneWidget);
    expect(find.text('Strength COPY'), findsOneWidget, reason: 'prefilled');

    await tester.tap(find.text('CANCEL'));
    await settleDb(tester);
    final programs = await tester.runAsync(() => dao.listPrograms());
    expect(programs!.length, 1);
    await closeDb(tester);
  });

  testWidgets('program editor: save copies and opens the copy', (tester) async {
    await seed(tester);
    await pumpAt(tester, '/programs/$programId');

    await tester.tap(find.bySemanticsLabel('Duplicate program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await settleDb(tester);
    await tester.pumpAndSettle(); // finish the replace transition

    final programs = (await tester.runAsync(() => dao.listPrograms()))!;
    expect(programs.map((p) => p.name).toSet(), {'Strength', 'Strength COPY'});
    expect(
      find.text('Strength COPY'),
      findsOneWidget,
      reason: 'the editor now shows the copy',
    );
    expect(find.textContaining("don't touch STRENGTH"), findsOneWidget);
    await closeDb(tester);
  });

  testWidgets('day editor: icon present; cancel creates nothing', (
    tester,
  ) async {
    await seed(tester);
    await pumpAt(tester, '/programs/$programId/days/$dayId');

    final icon = find.bySemanticsLabel('Duplicate day');
    expect(icon, findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.text('DUPLICATE DAY'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await settleDb(tester);
    final days = await tester.runAsync(() => dao.listDays(programId));
    expect(days!.length, 1);
    await closeDb(tester);
  });

  testWidgets('day editor: save appends a copy and opens it', (tester) async {
    await seed(tester);
    await pumpAt(tester, '/programs/$programId/days/$dayId');

    await tester.tap(find.bySemanticsLabel('Duplicate day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await settleDb(tester);
    await tester.pumpAndSettle(); // finish the replace transition

    final days = (await tester.runAsync(() => dao.listDays(programId)))!;
    expect(days.map((d) => d.name), ['Push', 'Push COPY']);
    expect(find.text('Push COPY'), findsOneWidget);
    expect(
      find.text('BENCH PRESS'),
      findsOneWidget,
      reason: 'the copy carries the slot',
    );
    await closeDb(tester);
  });
}
