import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show sharedPreferencesProvider;

enum WeightUnit {
  kg,
  lb;

  String get short => this == WeightUnit.kg ? 'kg' : 'lb';

  /// Default step in the native unit for the weight picker.
  double get defaultStep => this == WeightUnit.kg ? 0.5 : 1.0;

  double get largeStep => this == WeightUnit.kg ? 1.0 : 2.5;
}

class AppSettings {
  const AppSettings({
    required this.unit,
    required this.weightStep,
    required this.restSeconds,
    required this.liveActivityEnabled,
  });
  final WeightUnit? unit; // null = not yet chosen
  final double weightStep;
  final int restSeconds;
  final bool liveActivityEnabled;

  AppSettings copyWith({
    WeightUnit? unit,
    double? weightStep,
    int? restSeconds,
    bool? liveActivityEnabled,
  }) =>
      AppSettings(
        unit: unit ?? this.unit,
        weightStep: weightStep ?? this.weightStep,
        restSeconds: restSeconds ?? this.restSeconds,
        liveActivityEnabled: liveActivityEnabled ?? this.liveActivityEnabled,
      );
}

class SettingsRepository {
  SettingsRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _kUnit = 'settings.unit';
  static const _kWeightStep = 'settings.weight_step';
  static const _kRestSeconds = 'settings.rest_seconds';
  static const _kLiveActivity = 'settings.live_activity';
  static const int defaultRestSeconds = 90;

  AppSettings read() {
    final unitStr = _prefs.getString(_kUnit);
    final unit = switch (unitStr) {
      'kg' => WeightUnit.kg,
      'lb' => WeightUnit.lb,
      _ => null,
    };
    final step = _prefs.getDouble(_kWeightStep) ??
        (unit?.defaultStep ?? WeightUnit.kg.defaultStep);
    final rest = _prefs.getInt(_kRestSeconds) ?? defaultRestSeconds;
    final liveActivity = _prefs.getBool(_kLiveActivity) ?? true;
    return AppSettings(
      unit: unit,
      weightStep: step,
      restSeconds: rest,
      liveActivityEnabled: liveActivity,
    );
  }

  Future<void> writeUnit(WeightUnit unit) async {
    await _prefs.setString(_kUnit, unit.name);
  }

  Future<void> writeWeightStep(double step) async {
    await _prefs.setDouble(_kWeightStep, step);
  }

  Future<void> writeRestSeconds(int seconds) async {
    await _prefs.setInt(_kRestSeconds, seconds);
  }

  Future<void> writeLiveActivityEnabled(bool enabled) async {
    await _prefs.setBool(_kLiveActivity, enabled);
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});
