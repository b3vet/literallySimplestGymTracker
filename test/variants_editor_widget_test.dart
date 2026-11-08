import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/programs/presentation/exercise_edit_sheet.dart';
import 'package:ls_workout_tracker/features/programs/presentation/variants_sheet.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// SOW-14 program-side UI: the variant-mode exercise sheet, the VARIANTS row
/// and the variants sheet.
void Function(FlutterErrorDetails)? _origOnError;

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProgramDao dao;
  late String slotId;

  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> seed(WidgetTester tester, {bool withVariant = false}) async {
    await tester.runAsync(() async {
      db = await openTestDb();
      dao = ProgramDao(db);
      final p = await dao.createProgram('P');
      final d = await dao.createDay(p.id, 'Upper');
      final pe = await dao.addProgramExercise(
        programDayId: d.id,
        exerciseName: 'Shoulder Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 50,
      );
      slotId = pe.id;
      if (withVariant) {
        await dao.addVariant(
          programExerciseId: pe.id,
          exerciseName: 'Shoulder Press (Machine)',
          defaultWeightKg: 40,
        );
      }
    });
  }

  /// A host screen with one OPEN button that runs [open].
  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    // The test font (Ahem) draws every glyph as a full em square, so the
    // weight-step chips overflow by a few px in tests only. Ignore overflow
    // reports — and only those.
    _origOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      _origOnError?.call(details);
    };
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
        child: MaterialApp(
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
                  onPressed: () => open(context),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await settleDb(tester);
  }

  Future<void> closeDb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    FlutterError.onError = _origOnError;
    await tester.runAsync(() => db.close());
  }

  testWidgets('variantMode shows only name, weight and step', (tester) async {
    await seed(tester);
    await pumpHost(
      tester,
      (c) => showExerciseEditSheet(
        c,
        unit: WeightUnit.kg,
        initialName: 'Shoulder Press (Machine)',
        initialSets: 3,
        initialRepsMin: 8,
        initialRepsMax: 10,
        initialWeightKg: 40,
        initialWeightStepKg: null,
        variantMode: true,
        variantCount: 3,
      ),
    );

    expect(find.text('EDIT VARIANT'), findsOneWidget);
    expect(find.text('WT'), findsOneWidget);
    expect(find.text('WEIGHT STEP'), findsOneWidget);
    for (final hidden in ['SETS', 'REP MIN', 'REP MAX', 'DROP SET']) {
      expect(find.text(hidden), findsNothing, reason: '$hidden is the slot\'s');
    }
    expect(
      find.textContaining('VARIANTS ·'),
      findsNothing,
      reason: 'no variants of a variant',
    );
    await closeDb(tester);
  });

  testWidgets('the program sheet keeps every field', (tester) async {
    await seed(tester);
    await pumpHost(
      tester,
      (c) => showExerciseEditSheet(
        c,
        unit: WeightUnit.kg,
        initialName: 'Shoulder Press',
        initialSets: 3,
        initialRepsMin: 8,
        initialRepsMax: 10,
        initialWeightKg: 50,
        initialWeightStepKg: null,
        canDelete: true,
        variantCount: 0,
      ),
    );
    for (final shown in ['SETS', 'REP MIN', 'REP MAX', 'WT', 'DROP SET']) {
      expect(find.text(shown), findsOneWidget);
    }
    expect(find.text('VARIANTS · 0'), findsOneWidget);
    await closeDb(tester);
  });

  testWidgets('VARIANTS returns manageVariants with the current values', (
    tester,
  ) async {
    await seed(tester);
    ExerciseEditResult? result;
    await pumpHost(tester, (c) async {
      result = await showExerciseEditSheet(
        c,
        unit: WeightUnit.kg,
        initialName: 'Shoulder Press',
        initialSets: 4,
        initialRepsMin: 6,
        initialRepsMax: 8,
        initialWeightKg: 50,
        initialWeightStepKg: 2.5,
        initialDropCount: 1,
        canDelete: true,
        variantCount: 2,
      );
    });

    final row = find.text('VARIANTS · 2');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.manageVariants, isTrue);
    expect(result!.delete, isFalse);
    expect(result!.name, 'Shoulder Press');
    expect(result!.sets, 4);
    expect(result!.repsMin, 6);
    expect(result!.repsMax, 8);
    expect(result!.weightKg, 50);
    expect(result!.weightStepKg, 2.5);
    expect(result!.dropCount, 1);
    await closeDb(tester);
  });

  testWidgets('variants sheet lists the slot\'s variants and adds one', (
    tester,
  ) async {
    await seed(tester, withVariant: true);
    await pumpHost(
      tester,
      (c) => showVariantsSheet(
        c,
        programExerciseId: slotId,
        baseName: 'Shoulder Press',
      ),
    );

    expect(find.text('VARIANTS'), findsOneWidget);
    expect(find.text('SHOULDER PRESS (MACHINE)'), findsOneWidget);
    expect(find.text('40 KG'), findsOneWidget);

    await tester.tap(find.text('+ ADD VARIANT'));
    await tester.pumpAndSettle();
    expect(find.text('ADD VARIANT'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Shoulder Press (DB)');
    FocusManager.instance.primaryFocus?.unfocus();
    await settleDb(tester);
    await tester.tap(find.text('SAVE'));
    await settleDb(tester);
    await tester.pumpAndSettle();

    expect(find.text('SHOULDER PRESS (DB)'), findsOneWidget);
    final list = (await tester.runAsync(() => dao.listVariants(slotId)))!;
    expect(list.map((v) => v.exerciseName), [
      'Shoulder Press (Machine)',
      'Shoulder Press (DB)',
    ]);
    await closeDb(tester);
  });

  testWidgets('variants sheet explains a rejected variant inline', (
    tester,
  ) async {
    await seed(tester, withVariant: true);
    await pumpHost(
      tester,
      (c) => showVariantsSheet(
        c,
        programExerciseId: slotId,
        baseName: 'Shoulder Press',
      ),
    );
    await tester.tap(find.text('+ ADD VARIANT'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Shoulder Press');
    FocusManager.instance.primaryFocus?.unfocus();
    await settleDb(tester);
    await tester.tap(find.text('SAVE'));
    await settleDb(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining("slot's own exercise"), findsOneWidget);
    final list = (await tester.runAsync(() => dao.listVariants(slotId)))!;
    expect(list.length, 1);
    await closeDb(tester);
  });
}
