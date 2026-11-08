import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/domain/active_session.dart';
import 'package:ls_workout_tracker/features/workout/domain/workout_set.dart';
import 'package:ls_workout_tracker/features/workout/presentation/swap_exercise_button.dart';
import 'package:ls_workout_tracker/main.dart' show sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';

/// SOW-14 / DEC-0007: the variant switch lives in the exercise-options menu
/// behind the tune button (not in a chip row under the title).
class _FakeController extends ActiveWorkoutController {
  _FakeController(this.session);
  final ActiveSession session;
  final calls = <(int, String)>[];

  @override
  Future<ActiveSession?> build() async => session;

  @override
  Future<void> switchVariant(int queueIdx, String exerciseId) async {
    calls.add((queueIdx, exerciseId));
  }
}

const _machine = SlotVariant(
  variantId: 'v1',
  exerciseId: 'machine',
  name: 'Shoulder Press (Machine)',
  defaultWeightKg: 40,
);
const _db = SlotVariant(
  variantId: 'v2',
  exerciseId: 'db',
  name: 'Shoulder Press (DB)',
  defaultWeightKg: 22.5,
);

PlannedExercise _slot({
  String on = 'bar',
  List<SlotVariant> variants = const [_machine, _db],
}) {
  final member = [
    const SlotVariant(
      exerciseId: 'bar',
      name: 'Shoulder Press',
      defaultWeightKg: 60,
    ),
    ...variants,
  ].firstWhere((m) => m.exerciseId == on);
  return PlannedExercise(
    programExerciseId: 'pe1',
    exerciseId: member.exerciseId,
    exerciseName: member.name,
    targetSets: 3,
    targetRepsMin: 8,
    targetRepsMax: 10,
    defaultWeightKg: member.defaultWeightKg,
    isOverridden: on != 'bar',
    previousExerciseId: on != 'bar' ? 'bar' : null,
    baseExerciseId: 'bar',
    baseExerciseName: 'Shoulder Press',
    baseDefaultWeightKg: 60,
    variants: variants,
  );
}

void main() {
  late _FakeController fake;

  Future<void> pump(
    WidgetTester tester,
    PlannedExercise slot, {
    List<WorkoutSet> logged = const [],
  }) async {
    SharedPreferences.setMockInitialValues({'settings.unit': 'kg'});
    final prefs = await SharedPreferences.getInstance();
    fake = _FakeController(
      ActiveSession(
        sessionId: 's',
        programDayId: 'd',
        startedAt: DateTime(2026),
        queue: [slot],
        cursor: const Cursor(exerciseIdx: 0, setIdx: 0),
        loggedSets: logged,
      ),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          activeSessionProvider.overrideWith(() => fake),
        ],
        child: MaterialApp(
          builder: (context, child) => LsTheme(
            surface: lsDark,
            accent: lsAccentSpec(LsAccent.red),
            brightness: Brightness.dark,
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SwapExerciseButton(queueIdx: 0, exercise: slot),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Exercise options'));
    await tester.pumpAndSettle();
    expect(find.text('EXERCISE OPTIONS'), findsOneWidget);
  }

  testWidgets('hidden when the slot has no variants', (tester) async {
    await pump(tester, _slot(variants: const []));
    expect(find.text('SWITCH VARIANT'), findsNothing);
    expect(
      find.text('CHANGE EXERCISE'),
      findsOneWidget,
      reason: 'the rest of the menu is unchanged',
    );
    expect(find.text('SKIP EXERCISE'), findsOneWidget);
  });

  testWidgets('hidden on an inserted exercise', (tester) async {
    final s = _slot();
    await pump(
      tester,
      PlannedExercise(
        programExerciseId: s.programExerciseId,
        exerciseId: s.exerciseId,
        exerciseName: s.exerciseName,
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 60,
        isInserted: true,
        baseExerciseId: 'bar',
        variants: const [_machine],
      ),
    );
    expect(find.text('SWITCH VARIANT'), findsNothing);
  });

  testWidgets('lists base + variants with the current one marked', (
    tester,
  ) async {
    await pump(tester, _slot(on: 'machine'));
    expect(find.text('SWITCH VARIANT'), findsOneWidget);
    expect(find.text('NOW: SHOULDER PRESS (MACHINE)'), findsOneWidget);

    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();

    for (final id in ['bar', 'machine', 'db']) {
      expect(find.byKey(ValueKey('variant-row-$id')), findsOneWidget);
    }
    expect(find.text('SHOULDER PRESS'), findsWidgets);
    expect(find.text('SETS DONE COUNT TOWARD EACH PLAN'), findsOneWidget);
    expect(find.text('3×8-10 · 60 KG · BASE'), findsOneWidget);
    expect(find.text('3×8-10 · 40 KG · CURRENT'), findsOneWidget);
    expect(find.text('3×8-10 · 22.5 KG'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('variant-row-machine')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget, reason: 'only one marked');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('variant-row-machine'))),
      isSemantics(isSelected: true),
    );
  });

  testWidgets('selecting one calls the notifier', (tester) async {
    await pump(tester, _slot());
    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('variant-row-db')));
    await tester.pumpAndSettle();
    expect(fake.calls, [(0, 'db')]);
  });

  testWidgets('selecting the current one changes nothing', (tester) async {
    await pump(tester, _slot());
    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('variant-row-bar')));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
  });

  // Review #2: on a slot whose sets are all logged, the switch is shown but
  // disabled — there is nothing left to carry over.
  testWidgets('disabled once the slot is complete', (tester) async {
    await pump(
      tester,
      _slot(),
      logged: [
        for (var i = 0; i < 3; i++)
          WorkoutSet(
            id: 's$i',
            sessionId: 's',
            exerciseId: 'bar',
            setIndex: i,
            reps: 8,
            weightKg: 60,
            rir: 1,
            loggedAt: DateTime(2026),
          ),
      ],
    );
    expect(find.text('SWITCH VARIANT'), findsOneWidget);
    expect(find.text('ALL SETS DONE ON SHOULDER PRESS'), findsOneWidget);
    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();
    expect(find.text('SETS DONE COUNT TOWARD EACH PLAN'), findsNothing);
    expect(fake.calls, isEmpty);
  });

  // QA VAR-15 observation: the picker listed the plan weight, not the one
  // the session runs with.
  testWidgets('picker shows session weights', (tester) async {
    await pump(
      tester,
      _slot().copyWith(
        defaultWeightKg: 62.5, // a "Change exercise" weight edit on the base
        memberWeights: const {'machine': MemberWeight(weightKg: 45)},
      ),
    );
    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();
    expect(find.text('3×8-10 · 62.5 KG · BASE · CURRENT'), findsOneWidget);
    expect(
      find.text('3×8-10 · 45 KG'),
      findsOneWidget,
      reason: 'visited earlier',
    );
    expect(
      find.text('3×8-10 · 22.5 KG'),
      findsOneWidget,
      reason: 'not visited: plan',
    );
  });

  // DEC-0007 #13: each row reads the member's own prescription; a member
  // whose plan the sets done already meet is dimmed and does nothing.
  testWidgets('rows show each member\'s plan; a met plan is dimmed', (
    tester,
  ) async {
    const smith = SlotVariant(
      variantId: 'v3',
      exerciseId: 'smith',
      name: 'Shoulder Press (Smith)',
      defaultWeightKg: 50,
      targetSets: 4,
      targetRepsMin: 6,
      targetRepsMax: 8,
      dropCount: 1,
    );
    const cable = SlotVariant(
      variantId: 'v4',
      exerciseId: 'cable',
      name: 'Shoulder Press (Cable)',
      defaultWeightKg: 20,
      targetSets: 2,
      targetRepsMin: 12,
      targetRepsMax: 12,
    );
    await pump(
      tester,
      _slot(variants: const [smith, cable]),
      logged: [
        for (var i = 0; i < 2; i++)
          WorkoutSet(
            id: 's$i',
            sessionId: 's',
            exerciseId: 'bar',
            setIndex: i,
            reps: 8,
            weightKg: 60,
            rir: 1,
            loggedAt: DateTime(2026),
          ),
      ],
    );
    expect(find.text('NOW: SHOULDER PRESS'), findsOneWidget);
    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();
    expect(find.text('4×6-8 · 50 KG · DROP ×1'), findsOneWidget);
    expect(
      find.text('2×12 · 20 KG · PLAN ALREADY MET'),
      findsOneWidget,
      reason: '2 done on the bar meet the cable\'s 2',
    );
    await tester.tap(find.byKey(const ValueKey('variant-row-cable')));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('variant-row-smith')));
    await tester.pumpAndSettle();
    expect(fake.calls, [(0, 'smith')]);
  });

  testWidgets('the entry is dimmed when no other member has sets left', (
    tester,
  ) async {
    const cable = SlotVariant(
      variantId: 'v4',
      exerciseId: 'cable',
      name: 'Shoulder Press (Cable)',
      defaultWeightKg: 20,
      targetSets: 2,
    );
    await pump(
      tester,
      _slot(variants: const [cable]),
      logged: [
        for (var i = 0; i < 2; i++)
          WorkoutSet(
            id: 's$i',
            sessionId: 's',
            exerciseId: 'bar',
            setIndex: i,
            reps: 8,
            weightKg: 60,
            rir: 1,
            loggedAt: DateTime(2026),
          ),
      ],
    );
    expect(find.text('NO OTHER VARIANT HAS SETS LEFT'), findsOneWidget);
    await tester.tap(find.text('SWITCH VARIANT'));
    await tester.pumpAndSettle();
    expect(find.text('SWITCH VARIANT'), findsOneWidget, reason: 'no picker');
  });

  // QA VAR-14 observation: the dimmed row's subtitle was ellipsized.
  testWidgets('ALL SETS DONE ON <BASE> wraps instead of truncating', (
    tester,
  ) async {
    await pump(
      tester,
      _slot(),
      logged: [
        for (var i = 0; i < 3; i++)
          WorkoutSet(
            id: 's$i',
            sessionId: 's',
            exerciseId: 'bar',
            setIndex: i,
            reps: 8,
            weightKg: 60,
            rir: 1,
            loggedAt: DateTime(2026),
          ),
      ],
    );
    final p = tester.renderObject<RenderParagraph>(
      find.text('ALL SETS DONE ON SHOULDER PRESS'),
    );
    expect(p.didExceedMaxLines, isFalse);
  });

  test('snackbar action reads on the snackbar in both themes', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    for (final (s, b) in [
      (lsDark, Brightness.dark),
      (lsLight, Brightness.light),
    ]) {
      final theme = LsTheme.buildThemeData(
        s: s,
        a: lsAccentSpec(LsAccent.red),
        brightness: b,
      );
      expect(
        contrast(theme.snackBarTheme.actionTextColor!,
            theme.colorScheme.inverseSurface),
        greaterThanOrEqualTo(4.5),
        reason: '$b',
      );
    }
  });
}
