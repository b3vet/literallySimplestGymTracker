import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart'
    show WeightUnit;
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/share/domain/workout_summary.dart';
import 'package:ls_workout_tracker/features/share/presentation/summary_card.dart';

/// Builds a [WorkoutSummary] with [count] exercise lines. Every line carries a
/// PR (worst case for vertical fit) and a wide weight value (worst case for
/// horizontal fit), so a clean render here covers the overflow-prone cases.
WorkoutSummary _summary(int count) {
  final lines = <TopSetLine>[
    for (var i = 0; i < count; i++)
      TopSetLine(
        // Long name to stress the row's Expanded/ellipsis name column.
        exercise: 'Bulgarian Split Squat (Rear-Foot Elevated) #${i + 1}',
        reps: 12,
        weightKg: 142.5,
        isPr: true,
      ),
  ];
  return WorkoutSummary(
    programName: 'Push Pull Legs',
    dayName: 'Heavy Lower Body Day',
    date: DateTime(2026, 6, 23, 18, 30),
    duration: const Duration(hours: 1, minutes: 12),
    exerciseCount: count,
    // Seven-figure tonnage stresses the stats-row numeral FittedBox.
    tonnageKg: 1234567,
    prCount: count,
    lines: lines,
  );
}

Future<void> _pumpCard(WidgetTester tester, int count) async {
  // Lay out at the production card size so overflow (if any) actually triggers.
  tester.view.physicalSize = const Size(
    SummaryCard.cardWidth,
    SummaryCard.cardHeight,
  );
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(
        size: Size(SummaryCard.cardWidth, SummaryCard.cardHeight),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SummaryCard(
          summary: _summary(count),
          unit: WeightUnit.kg,
          accent: lsAccents.first,
          boundaryKey: GlobalKey(),
        ),
      ),
    ),
  );
}

void main() {
  group('SummaryCard renders at 1080x1350 without overflow', () {
    for (final count in [1, 6, 12, 20]) {
      testWidgets('$count exercises', (tester) async {
        await _pumpCard(tester, count);
        // A RenderFlex overflow (vertical or horizontal) surfaces as a thrown
        // exception captured here; null means a clean layout.
        expect(tester.takeException(), isNull);
      });
    }
  });
}
