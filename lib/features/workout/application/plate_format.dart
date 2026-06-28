import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../../../core/util/weight.dart';
import '../domain/plate_math.dart';

/// Formats a [PlateResult] into the plate-breakdown strings shown under the
/// weight picker, on the active-workout card, and (mirrored in Swift) on the
/// watch. Plate values render in the user's display [unit]; the math itself is
/// always kg (see plate_math.dart). Keep this in sync with `PlateMath.swift`'s
/// formatter so phone and watch read identically.
class PlateFormat {
  /// The full one-line string: `"20 + 15 + 5"`, `"BAR ONLY"`, `"EMPTY BAR"`, or
  /// `"≈ 97.5  25 + 10 + 2.5 + 1.25"`. [compact] drops the spaces around `+`
  /// for the narrow watch surface (`"20+15+5"`).
  static String line(PlateResult r, WeightUnit unit, {bool compact = false}) {
    if (r.belowBar) return 'EMPTY BAR';
    if (r.barOnly) return 'BAR ONLY';
    final plates = plates_(r, unit, compact: compact);
    if (r.exact) return plates;
    final approx = approxTotal(r, unit);
    return compact ? '≈$approx $plates' : '≈ $approx  $plates';
  }

  /// Just the `+`-joined plate list (no approx prefix, no bar-only fallback).
  static String plates_(PlateResult r, WeightUnit unit, {bool compact = false}) {
    final sep = compact ? '+' : ' + ';
    return r.perSide.map((kg) => plateNum(kg, unit)).join(sep);
  }

  /// A bare numeric value in the display unit, no unit suffix. kg keeps
  /// fractional precision (`20`, `2.5`, `1.25`); lb rounds to whole.
  static String plateNum(double kg, WeightUnit unit) =>
      _fmtNum(_displayValue(kg, unit), unit);

  /// The "≈ total" value (display unit, no suffix). Derived from the DISPLAYED
  /// bar + plate values so it always equals the sum of the plates shown — this
  /// avoids an lb-rounding artefact where independently-rounded plates wouldn't
  /// sum to a separately-rounded total. For kg the plates are exact so this
  /// equals the achievable total.
  static String approxTotal(PlateResult r, WeightUnit unit) =>
      _fmtNum(_displayedTotal(r, unit), unit);

  /// Magnitude of how far the achievable total is from the request, in the
  /// display unit (no sign — the caller prefixes `−`). Only meaningful when the
  /// result is not exact.
  static String deltaNum(PlateResult r, WeightUnit unit) =>
      _fmtNum(_displayValue(r.deltaKg.abs(), unit), unit);

  /// Eyebrow label, e.g. `"PER SIDE · BAR 20"` (bar weight in display unit).
  static String eyebrow(double barKg, WeightUnit unit) =>
      'PER SIDE · BAR ${plateNum(barKg, unit)}';

  // ── internals ──────────────────────────────────────────────────────────────

  /// The value as DISPLAYED: kg keeps fractional precision; lb rounds to whole.
  static double _displayValue(double kg, WeightUnit unit) {
    final v = WeightConv.fromKg(kg, unit);
    return unit == WeightUnit.lb ? v.roundToDouble() : v;
  }

  /// Achievable total computed from the DISPLAYED bar + plate values.
  static double _displayedTotal(PlateResult r, WeightUnit unit) {
    final bar = _displayValue(r.barKg, unit);
    final plates = r.perSide.fold<double>(0, (a, kg) => a + _displayValue(kg, unit));
    return bar + 2 * plates;
  }

  static String _fmtNum(double v, WeightUnit unit) {
    if (unit == WeightUnit.lb) return v.round().toString();
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    var s = v.toStringAsFixed(2);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }
}
