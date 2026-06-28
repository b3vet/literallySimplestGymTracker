// Pure plate-loading math for a barbell. No Flutter imports — fully unit-testable.
//
// All weights are in KILOGRAMS (the app's canonical/DB unit, see weight.dart).
// Display-unit (kg/lb) conversion is a separate formatting concern — see
// `application/plate_format.dart`. Keeping the math unit-agnostic means the
// watch (Swift) can mirror it line-for-line from the same kg inputs.

/// Result of solving how to load a barbell to a target weight.
class PlateResult {
  /// Plates for ONE side, largest-first (kg). Whole pairs only — every entry is
  /// mirrored on the other side, so we never tell a lifter to put a lone plate
  /// on one end. Empty when only the bar is loaded.
  final List<double> perSide;

  /// The total barbell weight actually achievable with [perSide]:
  /// `barKg + 2 * sum(perSide)`. Equals [requestedTargetKg] when [exact].
  final double achievableTotalKg;

  /// The weight the caller asked for.
  final double requestedTargetKg;

  /// The bar weight used (kg).
  final double barKg;

  const PlateResult({
    required this.perSide,
    required this.achievableTotalKg,
    required this.requestedTargetKg,
    required this.barKg,
  });

  static const double _eps = 1e-6;

  /// True when the achievable total hits the requested target exactly.
  bool get exact => (achievableTotalKg - requestedTargetKg).abs() < _eps;

  /// True when nothing is loaded beyond the bar.
  bool get barOnly => perSide.isEmpty;

  /// True when the requested target is strictly below the empty bar — you can't
  /// load a barbell lighter than its own bar, so the UI shows "EMPTY BAR".
  bool get belowBar => requestedTargetKg < barKg - _eps;

  /// Signed difference between what you'll actually load and what you asked for.
  /// Negative ⇒ under target (couldn't quite reach it); positive ⇒ over target
  /// (e.g. the empty bar alone already exceeds a below-bar request). Zero when
  /// [exact].
  double get deltaKg => achievableTotalKg - requestedTargetKg;
}

/// Solve the per-side plate breakdown to load a barbell to [targetKg].
///
/// - [barKg]: the empty bar weight (kg).
/// - [inventoryKg]: available plate denominations (kg). Order is irrelevant;
///   de-duplicated internally. Each denomination is available in unlimited
///   pairs unless capped via [maxPairs].
/// - [maxPairs]: optional cap on how many PAIRS of a denomination exist, keyed
///   by the denomination's kg value. Absent denominations are unlimited.
///
/// Returns the loadout whose total is the **nearest achievable at or below**
/// [targetKg] — exact when reachable — using the **fewest plates**, largest
/// first (locked decisions §7/§8: "never suggest more than asked", honest-by-
/// design). This is a true bounded search (a min-plate subset-sum over the
/// per-side half-target), so it never misses an exact or nearest-below loadout
/// even for non-canonical or capped inventories — unlike a naive greedy pass.
PlateResult solvePlates({
  required double targetKg,
  required double barKg,
  required List<double> inventoryKg,
  Map<double, int>? maxPairs,
}) {
  const eps = 1e-6;

  // At or below the bar: nothing to load. (belowBar / exact getters
  // disambiguate "EMPTY BAR" vs "BAR ONLY" downstream.)
  if (targetKg <= barKg + eps) {
    return PlateResult(
      perSide: const <double>[],
      achievableTotalKg: barKg,
      requestedTargetKg: targetKg,
      barKg: barKg,
    );
  }

  final perSideTarget = (targetKg - barKg) / 2.0;

  // Work in integer CENTI-KG (×100) to avoid float drift — every plate the app
  // offers is an exact 0.01 kg multiple. `t` is the per-side target in centi-kg.
  final t = (perSideTarget * 100).round();
  if (t <= 0) {
    return PlateResult(
      perSide: const <double>[],
      achievableTotalKg: barKg,
      requestedTargetKg: targetKg,
      barKg: barKg,
    );
  }

  // Denominations as centi-kg ints (deduped, descending, only those that fit).
  final denomKg = inventoryKg.where((d) => d > eps).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  final denomCenti = <int>[];
  final centiToKg = <int, double>{};
  for (final d in denomKg) {
    final c = (d * 100).round();
    if (c > 0 && c <= t && !centiToKg.containsKey(c)) {
      denomCenti.add(c);
      centiToKg[c] = d;
    }
  }

  // Min-plates DP: best[s] = fewest plates to reach EXACTLY s centi-kg per side.
  const big = 1 << 30;
  final best = List<int>.filled(t + 1, big);
  best[0] = 0;
  for (final c in denomCenti) {
    final cap = maxPairs?[centiToKg[c]];
    if (cap == null) {
      // Unbounded — relax forward.
      for (var s = c; s <= t; s++) {
        if (best[s - c] + 1 < best[s]) best[s] = best[s - c] + 1;
      }
    } else {
      // Bounded to `cap` pairs — `cap` rounds of 0/1 relaxation (s descending).
      for (var k = 0; k < cap; k++) {
        for (var s = t; s >= c; s--) {
          if (best[s - c] + 1 < best[s]) best[s] = best[s - c] + 1;
        }
      }
    }
  }

  // Largest reachable per-side sum at or below the target (always ≥ 0).
  var bestS = 0;
  for (var s = t; s >= 0; s--) {
    if (best[s] < big) {
      bestS = s;
      break;
    }
  }

  // Reconstruct a fewest-plate, largest-first loadout for bestS, respecting
  // remaining pair caps so a capped denomination is never over-placed.
  final remaining = <int, int>{
    for (final c in denomCenti) c: maxPairs?[centiToKg[c]] ?? big,
  };
  final used = <double>[];
  var s = bestS;
  while (s > 0) {
    var picked = false;
    for (final c in denomCenti) {
      if (c <= s && (remaining[c] ?? 0) > 0 && best[s - c] == best[s] - 1) {
        used.add(centiToKg[c]!);
        remaining[c] = remaining[c]! - 1;
        s -= c;
        picked = true;
        break;
      }
    }
    if (!picked) break; // unreachable in practice; guards against an infinite loop
  }

  return PlateResult(
    perSide: used,
    achievableTotalKg: barKg + 2 * (bestS / 100.0),
    requestedTargetKg: targetKg,
    barKg: barKg,
  );
}
