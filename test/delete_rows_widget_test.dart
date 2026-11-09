import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/presentation/day_editor_screen.dart';
import 'package:ls_workout_tracker/features/programs/presentation/program_delete.dart';
import 'package:ls_workout_tracker/features/programs/presentation/program_editor_screen.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-15: the visible delete control on day and exercise rows in EDIT mode,
/// DELETE DAY in the day editor, and the confirmations that spell out what
/// goes. DB work runs on a real isolate, so every wait for it goes through
/// `tester.runAsync`.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String programId;
  late String pushId;
  late String pullId;
  late String benchSlot;

  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<GoRouter> pumpAt(WidgetTester tester, String location) async {
    // A phone-sized screen (the edit sheet's chips overflow at 800 × 600).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full em square, so button labels
    // and the edit sheet's chips overflow by a few px in tests only (as in
    // program_duplicate_widget_test). Ignore overflow reports — only those.
    final origOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      origOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = origOnError);
    SharedPreferences.setMockInitialValues({
      'settings.unit': 'kg',
      'settings.live_activity': false,
    });
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
    return router;
  }

  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await openTestDb();
      dao = ProgramDao(db);
      final p = await dao.createProgram('Strength');
      programId = p.id;
      pushId = (await dao.createDay(p.id, 'Push')).id;
      pullId = (await dao.createDay(p.id, 'Pull')).id;
      Future<String> add(String day, String name) async =>
          (await dao.addProgramExercise(
            programDayId: day,
            exerciseName: name,
            targetSets: 3,
            targetRepsMin: 5,
            targetRepsMax: 8,
            defaultWeightKg: 80,
          ))
              .id;
      benchSlot = await add(pushId, 'Bench Press');
      await add(pushId, 'Dips');
      await add(pullId, 'Row');
      for (final v in ['Bench Press (Smith)', 'Bench Press (DB)']) {
        await dao.addVariant(
          programExerciseId: benchSlot,
          exerciseName: v,
          defaultWeightKg: 60,
        );
      }
    });
  }

  Future<void> closeDb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.close());
  }

  Future<void> tapEdit(WidgetTester tester) async {
    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'DELETE'));
    await settleDb(tester);
  }

  group('program editor', () {
    testWidgets('no delete button outside EDIT; EDIT shows one per day', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId');
      expect(find.bySemanticsLabel('Delete Push'), findsNothing);
      expect(find.bySemanticsLabel('Delete Pull'), findsNothing);
      expect(find.text('RENAME PROGRAM'), findsNothing);

      await tapEdit(tester);
      expect(find.bySemanticsLabel('Delete Push'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete Pull'), findsOneWidget);
      expect(find.text('RENAME PROGRAM'), findsOneWidget,
          reason: 'rename moved into EDIT mode');
      final size = tester.getSize(find.bySemanticsLabel('Delete Push'));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Delete Push'), findsNothing);
      await closeDb(tester);
    });

    testWidgets('the button confirms with the consequences, then deletes', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId');
      await tapEdit(tester);
      await tester.tap(find.bySemanticsLabel('Delete Push'));
      await settleDb(tester);
      expect(find.text('DELETE?'), findsOneWidget);
      expect(find.text('2 exercises will be removed.'), findsOneWidget);
      expect(find.text(deleteKeepsHistoryLine), findsOneWidget);
      expect(find.textContaining('in progress'), findsNothing);

      await tester.tap(find.text('CANCEL'));
      await settleDb(tester);
      expect((await tester.runAsync(() => dao.listDays(programId)))!.length,
          2);

      await tester.tap(find.bySemanticsLabel('Delete Push'));
      await settleDb(tester);
      await confirm(tester);
      final days = await tester.runAsync(() => dao.listDays(programId));
      expect(days!.map((d) => d.name), ['Pull']);
      expect(find.text('PUSH'), findsNothing);
      await closeDb(tester);
    });

    testWidgets('swipe-to-delete still works in EDIT mode', (tester) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId');
      await tapEdit(tester);
      await tester.drag(find.text('PULL'), const Offset(-500, 0));
      await settleDb(tester);
      expect(find.text('1 exercise will be removed.'), findsOneWidget);
      await confirm(tester);
      final days = await tester.runAsync(() => dao.listDays(programId));
      expect(days!.map((d) => d.name), ['Push']);
      await closeDb(tester);
    });
  });

  group('day editor', () {
    testWidgets('no delete controls outside EDIT; EDIT shows them', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId/days/$pushId');
      expect(find.bySemanticsLabel('Delete Bench Press'), findsNothing);
      expect(find.text('DELETE DAY'), findsNothing);

      await tapEdit(tester);
      expect(find.bySemanticsLabel('Delete Bench Press'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete Dips'), findsOneWidget);
      expect(find.text('DELETE DAY'), findsOneWidget);
      expect(find.text('RENAME DAY'), findsOneWidget);
      await closeDb(tester);
    });

    testWidgets('exercise: variants named, then deleted with them', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId/days/$pushId');
      await tapEdit(tester);
      await tester.tap(find.bySemanticsLabel('Delete Bench Press'));
      await settleDb(tester);
      expect(find.text('Also deletes its 2 variants.'), findsOneWidget);
      expect(find.text(deleteKeepsHistoryLine), findsOneWidget);
      expect(find.text(deleteDropsExerciseWarning), findsNothing);
      await confirm(tester);
      final left = await tester.runAsync(() => dao.listProgramExercises(pushId));
      expect(left!.map((v) => v.exerciseName), ['Dips']);
      final variants =
          await tester.runAsync(() => dao.listVariantsForDay(pushId));
      expect(variants, isEmpty);
      expect(find.text('BENCH PRESS'), findsNothing);
      await closeDb(tester);
    });

    testWidgets('exercise: warns when the workout in progress is on the day', (
      tester,
    ) async {
      await seed(tester);
      await tester.runAsync(() => WorkoutDao(db).startSession(pushId));
      await pumpAt(tester, '/programs/$programId/days/$pushId');
      await tapEdit(tester);
      await tester.tap(find.bySemanticsLabel('Delete Dips'));
      await settleDb(tester);
      expect(find.text(deleteDropsExerciseWarning), findsOneWidget);
      expect(find.textContaining('variant'), findsNothing);
      await tester.tap(find.text('CANCEL'));
      await settleDb(tester);
      await closeDb(tester);
    });

    testWidgets('the edit sheet DELETE goes through the same confirm', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId/days/$pushId');
      await tester.tap(find.text('DIPS'));
      await settleDb(tester);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'DELETE'));
      await tester.tap(find.widgetWithText(TextButton, 'DELETE'));
      await settleDb(tester);
      expect(find.text('DELETE?'), findsOneWidget,
          reason: 'used to delete with no confirm');
      expect(find.text(deleteKeepsHistoryLine), findsOneWidget);
      await tester.tap(find.text('CANCEL'));
      await settleDb(tester);
      expect(
        (await tester.runAsync(() => dao.listProgramExercises(pushId)))!
            .length,
        2,
      );
      await closeDb(tester);
    });

    testWidgets('DELETE DAY: confirm, delete, back to the program editor', (
      tester,
    ) async {
      await seed(tester);
      await tester.runAsync(() => WorkoutDao(db).startSession(pushId));
      final router = await pumpAt(tester, '/programs/$programId');
      router.push('/programs/$programId/days/$pushId');
      await settleDb(tester);
      // The program editor below has its own EDIT; tap the day editor's.
      await tester.tap(find.descendant(
        of: find.byType(DayEditorScreen),
        matching: find.text('EDIT'),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('DELETE DAY'));
      await tester.tap(find.text('DELETE DAY'));
      await settleDb(tester);
      expect(find.text('2 exercises will be removed.'), findsOneWidget);
      expect(find.text(deleteEndsWorkoutWarning('day')), findsOneWidget);
      await confirm(tester);
      await settleDb(tester);
      expect(find.byType(DayEditorScreen), findsNothing);
      expect(find.byType(ProgramEditorScreen), findsOneWidget);
      expect(find.text('PUSH'), findsNothing);
      expect(find.text('PULL'), findsOneWidget);
      final days = await tester.runAsync(() => dao.listDays(programId));
      expect(days!.map((d) => d.name), ['Pull']);
      expect(await tester.runAsync(() => WorkoutDao(db).findActiveSession()),
          isNull,
          reason: 'the workout on the day was closed');
      await closeDb(tester);
    });

    testWidgets('deleting the last exercise leaves the empty state', (
      tester,
    ) async {
      await seed(tester);
      await pumpAt(tester, '/programs/$programId/days/$pullId');
      await tapEdit(tester);
      await tester.tap(find.bySemanticsLabel('Delete Row'));
      await settleDb(tester);
      await confirm(tester);
      expect(find.text('Tap + EXERCISE to plan your first lift.'),
          findsOneWidget);
      expect(find.text('DELETE DAY'), findsOneWidget,
          reason: 'still in EDIT mode on an empty day');
      await closeDb(tester);
    });
  });
}
