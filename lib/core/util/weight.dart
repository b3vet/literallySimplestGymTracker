import '../settings/settings_repository.dart';

class WeightConv {
  static const double _lbPerKg = 2.2046226218;

  /// Convert a value the user typed in their chosen unit into kg (DB unit).
  static double toKg(double displayValue, WeightUnit unit) =>
      unit == WeightUnit.kg ? displayValue : displayValue / _lbPerKg;

  /// Convert stored kg into the user's chosen display unit.
  static double fromKg(double kg, WeightUnit unit) =>
      unit == WeightUnit.kg ? kg : kg * _lbPerKg;

  /// Human-readable string in the user's unit ("80 kg" / "176 lb").
  static String format(double kg, WeightUnit unit) {
    final v = fromKg(kg, unit);
    if (unit == WeightUnit.kg) {
      return v == v.roundToDouble()
          ? '${v.toStringAsFixed(0)} kg'
          : '${v.toStringAsFixed(1)} kg';
    }
    return '${v.round()} lb';
  }
}
