import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/data/workout_dao.dart';
import 'package:ls_workout_tracker/features/workout/presentation/summary_screen.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// Summary screen widget tests (D-0011).
///
/// QA VAR-08: the summary's variant raise card ellipsized the variant name and
/// the proposed weight ("SHOULDER PRESS (…", "40 → 42…", or "42.5 →" with the
/// value gone). Rendered with the app's real fonts (the default test font
/// draws every glyph as a full em square, far wider than condensed Antonio)
/// on a 390pt-wide screen, in both themes, with a normal and a long name:
/// no overflow, no paragraph cut short, and the proposed weight on screen.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(rootBundle.load('assets/fonts/$f.ttf'));
      }
      await loader.load();
    }

    await load('Antonio', ['Antonio-Regular', 'Antonio-SemiBold', 'Antonio-Bold']);
    await load('JetBrainsMono', [
      'JetBrainsMono-Regular',
      'JetBrainsMono-Medium',
      'JetBrainsMono-SemiBold',
      'JetBrainsMono-Bold',
    ]);
    await load('IBMPlexSans', [
      'IBMPlexSans-Regular',
      'IBMPlexSans-Medium',
      'IBMPlexSans-SemiBold',
      'IBMPlexSans-Bold',
    ]);
  });

  late Database db;

  /// A day whose base slot has [variantName] as a variant at 40 kg; an earlier
  /// session on it, then today's at 42.5 kg — a VARIANT TARGET 40 → 42.5 card.
  Future<String> seed(WidgetTester tester, String variantName) async {
    return (await tester.runAsync(() async {
      db = await openTestDb();
      final p = ProgramDao(db);
      final w = WorkoutDao(db);
      final prog = await p.createProgram('Push Pull Legs Copy');
      final day = await p.createDay(prog.id, 'Push');
      final slot = await p.addProgramExercise(
        programDayId: day.id,
        exerciseName: 'Overhead Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 12,
        defaultWeightKg: 35,
      );
      final v = await p.addVariant(
        programExerciseId: slot.id,
        exerciseName: variantName,
        defaultWeightKg: 40,
      );
      Future<String> session(double kg) async {
        final s = await w.startSession(day.id);
        for (var i = 0; i < 2; i++) {
          await w.insertSet(
            sessionId: s.id,
            exerciseId: v.exerciseId,
            setIndex: i,
            reps: 10,
            weightKg: kg,
            rir: 1,
          );
        }
        await w.completeSession(s.id);
        return s.id;
      }

      await session(40);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return session(42.5);
    }))!;
  }

  Future<void> pump(
    WidgetTester tester,
    String sessionId, {
    required bool light,
  }) async {
    // 390pt wide; tall enough that the whole (lazy) list is built.
    tester.view.physicalSize = const Size(390 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'settings.unit': 'kg'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/summary',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: Text('HOME')),
              ),
              GoRoute(
                path: '/summary',
                builder: (_, _) => SummaryScreen(sessionId: sessionId),
              ),
            ],
          ),
          builder: (context, child) => LsTheme(
            surface: light ? lsLight : lsDark,
            accent: lsAccentSpec(LsAccent.red),
            brightness: light ? Brightness.light : Brightness.dark,
            child: child!,
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2)); // count-up animations
  }

  /// Every paragraph that belongs to the program-update card or the lift
  /// card's inline action, i.e. that mentions the variant or a target.
  Iterable<RenderParagraph> cardParagraphs(WidgetTester tester, String name) =>
      tester.renderObjectList<RenderParagraph>(find.byType(RichText)).where(
        (p) {
          final text = p.text.toPlainText().replaceAll(' ', ' ');
          return text.contains(name.toUpperCase()) ||
              text.contains('TARGET') ||
              text.contains('VARIANT') ||
              text.contains('42.5');
        },
      );

  for (final light in [false, true]) {
    for (final name in [
      'Shoulder Press (Machine)',
      'Single-Arm Landmine Shoulder Press (Machine)',
    ]) {
      testWidgets(
        'variant raise card fits: ${light ? 'light' : 'dark'}, "$name"',
        (tester) async {
          final sid = await seed(tester, name);
          await pump(tester, sid, light: light);

          expect(tester.takeException(), isNull, reason: 'no overflow');
          expect(find.text('UPDATE YOUR PROGRAM'), findsOneWidget);
          expect(find.text('VARIANT TARGET'), findsOneWidget);
          // The proposed weight is on screen, whole, on the card.
          expect(
            find.textContaining('40 → 42.5 KG', findRichText: true),
            findsOneWidget,
          );
          final paragraphs = cardParagraphs(tester, name).toList();
          expect(paragraphs, isNotEmpty);
          for (final p in paragraphs) {
            expect(
              p.didExceedMaxLines,
              isFalse,
              reason: 'cut short: "${p.text.toPlainText()}"',
            );
          }
          // The card's name is not ellipsized: it either fits or wraps.
          expect(find.text(name.toUpperCase()), findsWidgets);

          // Applied: "UPDATED" joins the name, the value line keeps the weight.
          await tester.tap(find.text('VARIANT TARGET'));
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          expect(find.text('UPDATED'), findsOneWidget);
          expect(find.text('42.5\u00A0KG'), findsWidgets);
          for (final p in cardParagraphs(tester, name)) {
            expect(p.didExceedMaxLines, isFalse,
                reason: 'cut short after apply: "${p.text.toPlainText()}"');
          }
          await tester.pump(const Duration(seconds: 10)); // snackbar out

          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() => db.close());
        },
      );
    }
  }

  // QA observation (D-0011): after APPLY ALL the UNDO snackbar was still on
  // the NEXT workout's screen minutes later — Flutter keeps a snackbar with an
  // action until it's tapped — where UNDO would silently revert this
  // session's program updates.
  group('UNDO snackbar', () {
    Future<void> apply(WidgetTester tester) async {
      await tester.tap(find.text('VARIANT TARGET'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('UNDO'), findsOneWidget);
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
    }

    testWidgets('times out like a normal snackbar, VoiceOver on too', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final sid = await seed(tester, 'Shoulder Press (Machine)');
      await pump(tester, sid, light: false);
      await apply(tester);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await done(tester);
    });

    testWidgets('leaving the summary takes it along', (tester) async {
      final sid = await seed(tester, 'Shoulder Press (Machine)');
      await pump(tester, sid, light: false);
      await apply(tester);
      await tester.tap(find.bySemanticsLabel('Done').first);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100)); // 1 s < 5 s
      }
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('UNDO'), findsNothing);
      await done(tester);
    });
  });
}
