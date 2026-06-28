import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/workout/domain/active_session.dart';
import 'package:ls_workout_tracker/features/workout/presentation/set_log_sheet.dart';
import 'package:ls_workout_tracker/main.dart' show sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';

/// SOW-03 decision #3 / §8: opening the set-log sheet for an exercise with
/// history must land the reps + RIR wheels on the last set's values (not
/// target-mid / 0), so the common "same as last time" log is zero-scroll.
/// Saving without touching a wheel returns those prefilled values verbatim.
void main() {
  const exercise = PlannedExercise(
    programExerciseId: 'pe1',
    exerciseId: 'ex1',
    exerciseName: 'Bench Press',
    targetSets: 3,
    targetRepsMin: 8,
    targetRepsMax: 12,
    defaultWeightKg: 80,
  );

  Future<SetLogResult?> openSheet(
    WidgetTester tester, {
    required int? initialReps,
    required int initialRir,
  }) async {
    SharedPreferences.setMockInitialValues({'settings.unit': 'kg'});
    final prefs = await SharedPreferences.getInstance();
    SetLogResult? captured;
    var done = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          // Host LsTheme ABOVE the Navigator (as the real app does) so the
          // modal bottom sheet — inserted into the Navigator overlay — resolves
          // LsTheme.of(context).
          builder: (context, child) => LsTheme(
            surface: lsDark,
            accent: lsAccentSpec(LsAccent.red),
            brightness: Brightness.dark,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showSetLogSheet(
                      context,
                      exercise: exercise,
                      setNumber: 2,
                      initialReps: initialReps,
                      initialWeightKg: 80,
                      initialRir: initialRir,
                    );
                    done = true;
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE SET'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    return captured;
  }

  testWidgets('prefills reps + RIR from the last set', (tester) async {
    final result = await openSheet(tester, initialReps: 7, initialRir: 2);
    expect(result, isNotNull);
    expect(result!.reps, 7, reason: 'reps wheel started on the last set');
    expect(result.rir, 2, reason: 'RIR wheel started on the last set');
  });

  testWidgets('falls back to target-mid reps + RIR 0 with no history',
      (tester) async {
    // initialReps null → sheet clamps to (8+12)~/2 = 10; initialRir 0 stays 0.
    final result = await openSheet(tester, initialReps: null, initialRir: 0);
    expect(result, isNotNull);
    expect(result!.reps, 10, reason: 'target-mid fallback when no last set');
    expect(result.rir, 0);
  });
}
