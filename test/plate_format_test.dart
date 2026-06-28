import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart'
    show WeightUnit;
import 'package:ls_workout_tracker/features/workout/application/plate_format.dart';
import 'package:ls_workout_tracker/features/workout/domain/plate_math.dart';

// Construct results directly so formatting is tested independently of solving.
PlateResult _exact(List<double> perSide, double total, double bar) => PlateResult(
      perSide: perSide,
      achievableTotalKg: total,
      requestedTargetKg: total,
      barKg: bar,
    );

void main() {
  group('PlateFormat.line — kg', () {
    test('exact -> "20 + 15 + 5"', () {
      final r = _exact([20, 15, 5], 100, 20);
      expect(PlateFormat.line(r, WeightUnit.kg), '20 + 15 + 5');
    });

    test('fractional plates keep precision -> "2.5 + 1.25"', () {
      final r = _exact([2.5, 1.25], 27.5, 20);
      expect(PlateFormat.line(r, WeightUnit.kg), '2.5 + 1.25');
    });

    test('bar only', () {
      final r = _exact(const [], 20, 20);
      expect(PlateFormat.line(r, WeightUnit.kg), 'BAR ONLY');
    });

    test('below bar -> EMPTY BAR', () {
      final r = PlateResult(
          perSide: const [],
          achievableTotalKg: 20,
          requestedTargetKg: 15,
          barKg: 20);
      expect(PlateFormat.line(r, WeightUnit.kg), 'EMPTY BAR');
    });

    test('closest -> "≈ 97.5  25 + 10 + 2.5 + 1.25"', () {
      final r = PlateResult(
          perSide: const [25, 10, 2.5, 1.25],
          achievableTotalKg: 97.5,
          requestedTargetKg: 98,
          barKg: 20);
      expect(PlateFormat.line(r, WeightUnit.kg), '≈ 97.5  25 + 10 + 2.5 + 1.25');
    });

    test('compact (watch) drops spaces -> "20+15+5"', () {
      final r = _exact([20, 15, 5], 100, 20);
      expect(PlateFormat.line(r, WeightUnit.kg, compact: true), '20+15+5');
    });
  });

  group('PlateFormat.line — lb (plates stored in kg, displayed converted)', () {
    test('whole-rounded lb values', () {
      // 20kg≈44, 15kg≈33, 5kg≈11 lb.
      final r = _exact([20, 15, 5], 100, 20);
      expect(PlateFormat.line(r, WeightUnit.lb), '44 + 33 + 11');
    });

    test('closest: ≈ total is consistent with the shown plates (lb)', () {
      // The ≈ total must equal bar + 2*sum(displayed plates), not an
      // independently-rounded kg→lb total. Plates 25→55,10→22,2.5→6,1.25→3;
      // bar 20→44; total = 44 + 2*(55+22+6+3) = 216.
      final r = PlateResult(
          perSide: const [25, 10, 2.5, 1.25],
          achievableTotalKg: 97.5,
          requestedTargetKg: 98,
          barKg: 20);
      expect(PlateFormat.line(r, WeightUnit.lb), '≈ 216  55 + 22 + 6 + 3');
    });
  });

  group('PlateFormat.deltaNum', () {
    test('reports the magnitude under target in the display unit', () {
      final r = PlateResult(
          perSide: const [25, 10, 2.5, 1.25],
          achievableTotalKg: 97.5,
          requestedTargetKg: 98,
          barKg: 20);
      expect(PlateFormat.deltaNum(r, WeightUnit.kg), '0.5'); // |97.5 - 98|
    });
  });

  group('PlateFormat.eyebrow', () {
    test('kg', () {
      expect(PlateFormat.eyebrow(20, WeightUnit.kg), 'PER SIDE · BAR 20');
    });
    test('lb shows converted bar', () {
      expect(PlateFormat.eyebrow(20, WeightUnit.lb), 'PER SIDE · BAR 44');
    });
  });
}
