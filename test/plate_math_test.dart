import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/workout/domain/plate_math.dart';

void main() {
  // Canonical commercial-gym kg set (the shipped default inventory).
  const full = <double>[25, 20, 15, 10, 5, 2.5, 1.25];

  group('solvePlates — exact targets', () {
    test('100kg / 20kg bar -> greedy-minimal [25, 15] per side', () {
      // 40 per side. Greedy-descending with a 25 available is [25, 15] (2
      // plates) — strictly fewer plates than [20, 15, 5], so it is the correct
      // loadout. (The SOW draft hand-wrote [20,15,5]; that is suboptimal.)
      final r = solvePlates(targetKg: 100, barKg: 20, inventoryKg: full);
      expect(r.exact, isTrue);
      expect(r.perSide, [25.0, 15.0]);
      expect(r.achievableTotalKg, closeTo(100, 1e-9));
      expect(r.deltaKg, closeTo(0, 1e-9));
      expect(r.barOnly, isFalse);
    });

    test('60kg / 20kg bar -> [20] per side', () {
      final r = solvePlates(targetKg: 60, barKg: 20, inventoryKg: full);
      expect(r.exact, isTrue);
      expect(r.perSide, [20.0]);
    });

    test('25kg / 20kg bar -> [2.5] per side (2.5*2 + 20 = 25)', () {
      final r = solvePlates(targetKg: 25, barKg: 20, inventoryKg: full);
      expect(r.exact, isTrue);
      expect(r.perSide, [2.5]);
    });

    test('equal plates stack: 70kg / 20kg bar -> [25] per side? no -> 25 per '
        'side = 70; 120kg -> [25,25] per side', () {
      expect(solvePlates(targetKg: 70, barKg: 20, inventoryKg: full).perSide,
          [25.0]); // (70-20)/2 = 25
      expect(solvePlates(targetKg: 120, barKg: 20, inventoryKg: full).perSide,
          [25.0, 25.0]); // (120-20)/2 = 50 = 25+25
    });
  });

  group('solvePlates — bar boundary', () {
    test('target == bar -> BAR ONLY, exact, empty plates, zero delta', () {
      final r = solvePlates(targetKg: 20, barKg: 20, inventoryKg: full);
      expect(r.barOnly, isTrue);
      expect(r.belowBar, isFalse);
      expect(r.exact, isTrue);
      expect(r.perSide, isEmpty);
      expect(r.deltaKg, closeTo(0, 1e-9));
    });

    test('target < bar -> EMPTY BAR: barOnly, belowBar, not exact, POSITIVE '
        'delta (the empty bar over-shoots the request)', () {
      // CORRECTION vs SOW draft: loading the empty 20kg bar for a 15kg request
      // is an over-shoot, so deltaKg is +5, not negative.
      final r = solvePlates(targetKg: 15, barKg: 20, inventoryKg: full);
      expect(r.barOnly, isTrue);
      expect(r.belowBar, isTrue);
      expect(r.exact, isFalse);
      expect(r.deltaKg, closeTo(5, 1e-9));
    });
  });

  group('solvePlates — closest achievable (never overshoot)', () {
    test('98kg unreachable -> 97.5 total, delta -0.5, greedy [25,10,2.5,1.25]',
        () {
      final r = solvePlates(targetKg: 98, barKg: 20, inventoryKg: full);
      expect(r.exact, isFalse);
      expect(r.achievableTotalKg, closeTo(97.5, 1e-9)); // 38.75 per side
      expect(r.perSide, [25.0, 10.0, 2.5, 1.25]);
      expect(r.deltaKg, closeTo(-0.5, 1e-9)); // under target, never over
    });

    test('never returns a lone single-side plate (per-side list is symmetric)',
        () {
      final r = solvePlates(targetKg: 22.5, barKg: 20, inventoryKg: [1.25]);
      expect(r.perSide, [1.25]); // 1.25 per side * 2 + 20 = 22.5
      expect(r.exact, isTrue);
    });
  });

  group('solvePlates — capped inventory', () {
    test('capped inventory cannot reach target -> closest below, not a crash',
        () {
      final r = solvePlates(
        targetKg: 100,
        barKg: 20,
        inventoryKg: <double>[25, 20],
        maxPairs: {25.0: 1, 20.0: 1},
      );
      // (100-20)/2 = 40 needed per side. With one pair each of 25 and 20:
      // greedy takes 25 (rem 15), 20 doesn't fit (>15) -> [25] = 35kg side ->
      // 70kg total. Honest nearest-below, never overshoot.
      expect(r.exact, isFalse);
      expect(r.perSide, isNotEmpty);
      expect(r.perSide, [25.0]);
      expect(r.achievableTotalKg, closeTo(70, 1e-9));
      expect(r.deltaKg, lessThan(0));
    });
  });

  group('solvePlates — non-canonical inventories (DP finds exact, not greedy)',
      () {
    // These are the cases a naive greedy-descending solver gets WRONG (it
    // takes the largest plate first and then misses the exact combo). The
    // bounded DP must find the exact loadout. A user can reach a non-canonical
    // inventory by de-selecting plates in the settings editor.
    test('{25,20,15} @ 90kg -> exact [20,15] (greedy would return [25]=70)', () {
      final r = solvePlates(
          targetKg: 90, barKg: 20, inventoryKg: <double>[25, 20, 15]);
      expect(r.exact, isTrue);
      expect(r.achievableTotalKg, closeTo(90, 1e-9));
      expect(r.perSide, [20.0, 15.0]); // 35 per side
    });

    test('{19,10} @ 60kg -> exact [10,10] (greedy would return [19]=58)', () {
      final r =
          solvePlates(targetKg: 60, barKg: 20, inventoryKg: <double>[19, 10]);
      expect(r.exact, isTrue);
      expect(r.perSide, [10.0, 10.0]); // 20 per side
    });

    test('{6,5} @ 40kg -> exact [5,5] (greedy would return [6]=32)', () {
      final r =
          solvePlates(targetKg: 40, barKg: 20, inventoryKg: <double>[6, 5]);
      expect(r.exact, isTrue);
      expect(r.perSide, [5.0, 5.0]); // 10 per side
    });

    test('capped {25:1} + uncapped {20,15} @ 90kg -> exact [20,15]', () {
      final r = solvePlates(
        targetKg: 90,
        barKg: 20,
        inventoryKg: <double>[25, 20, 15],
        maxPairs: {25.0: 1},
      );
      expect(r.exact, isTrue);
      expect(r.perSide, [20.0, 15.0]);
    });

    test('truly unreachable non-canonical -> honest nearest-below', () {
      // {25,20} @ 97kg: per side 38.5. Reachable per-side <= 38.5: 25, 20,
      // 25+? (25+20=45>38.5), 20+? -> max is 25. So 25/side -> 70 total.
      final r =
          solvePlates(targetKg: 97, barKg: 20, inventoryKg: <double>[25, 20]);
      expect(r.exact, isFalse);
      expect(r.achievableTotalKg, lessThan(97));
      expect(r.deltaKg, lessThan(0)); // never overshoot
    });
  });

  group('solvePlates — robustness', () {
    test('empty inventory -> bar only', () {
      final r = solvePlates(targetKg: 100, barKg: 20, inventoryKg: const []);
      expect(r.barOnly, isTrue);
      expect(r.achievableTotalKg, closeTo(20, 1e-9));
    });

    test('unsorted / duplicate inventory is handled', () {
      final r = solvePlates(
          targetKg: 100, barKg: 20, inventoryKg: <double>[5, 25, 15, 25, 20, 10]);
      expect(r.perSide, [25.0, 15.0]); // de-duped + sorted internally
      expect(r.exact, isTrue);
    });

    test('inventory is stored in kg regardless of display unit', () {
      // The solver only ever sees kg; lb is a display concern (plate_format).
      final r = solvePlates(targetKg: 60, barKg: 20, inventoryKg: full);
      expect(r.perSide, [20.0]);
    });
  });
}
