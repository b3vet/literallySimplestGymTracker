import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show sharedPreferencesProvider;
import '../theme/app_theme.dart' show LsAccent;

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
    required this.themeMode,
    required this.accent,
    required this.onboardingComplete,
  });
  final WeightUnit? unit; // null = not yet chosen
  final double weightStep;
  final int restSeconds;
  final bool liveActivityEnabled;
  final ThemeMode themeMode;
  final LsAccent accent;



  /// Whether the first-run onboarding wizard has been completed. Gates the
  /// app's initial route (see `app_router.dart`). Set `true` at the moment the
  /// chosen starting program is seeded — never before — so an interrupted
  /// first run always re-enters the wizard with no half-built program.
  final bool onboardingComplete;

  AppSettings copyWith({
    WeightUnit? unit,
    double? weightStep,
    int? restSeconds,
    bool? liveActivityEnabled,
    ThemeMode? themeMode,
    LsAccent? accent,
    bool? onboardingComplete,
  }) =>
      AppSettings(
        unit: unit ?? this.unit,
        weightStep: weightStep ?? this.weightStep,
        restSeconds: restSeconds ?? this.restSeconds,
        liveActivityEnabled: liveActivityEnabled ?? this.liveActivityEnabled,
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );
}

class SettingsRepository {
  SettingsRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _kUnit = 'settings.unit';
  static const _kWeightStep = 'settings.weight_step';
  static const _kRestSeconds = 'settings.rest_seconds';
  static const _kLiveActivity = 'settings.live_activity';
  static const _kThemeMode = 'settings.theme_mode';
  static const _kAccent = 'settings.accent';
  static const _kOnboardingComplete = 'settings.onboarding_complete';
  /// Removed in 1.4.1 with the plate calculator. Kept only so [read] can purge
  /// the stored values — leaving them behind would strand a few bytes per user
  /// forever and confuse anyone reading the prefs later.
  static const _kLegacyBarWeight = 'settings.bar_weight_kg';
  static const _kLegacyPlateInv = 'settings.plate_inventory_kg';

  /// Session-scoped, NOT a user setting — deliberately has no `settings.`
  /// prefix and is never read into [AppSettings]. Holds the absolute epoch-ms
  /// end time of the in-progress rest so it survives a force-kill (SOW-03).
  static const _kActiveRestEndsAtMs = 'active_rest_ends_at_ms';
  static const int defaultRestSeconds = 90;

  /// Erase settings that no longer exist. Fire-and-forget: `read()` is
  /// synchronous and callers don't await this, and a failed purge is harmless
  /// because nothing reads these keys any more.
  void _purgeRemovedSettings() {
    if (_prefs.containsKey(_kLegacyBarWeight)) _prefs.remove(_kLegacyBarWeight);
    if (_prefs.containsKey(_kLegacyPlateInv)) _prefs.remove(_kLegacyPlateInv);
  }

  AppSettings read() {
    _purgeRemovedSettings();
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
    final mode = switch (_prefs.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark, // default
    };
    final accentName = _prefs.getString(_kAccent);
    final accent = LsAccent.values.firstWhere(
      (a) => a.name == accentName,
      orElse: () => LsAccent.red,
    );
    // Legacy fallback: builds that predate the onboarding flag already chose a
    // unit, so treat "unit set" as "onboarding done" when the explicit flag is
    // absent. New installs (no unit, no flag) correctly read as incomplete.
    final onboardingComplete =
        _prefs.getBool(_kOnboardingComplete) ?? (unit != null);
    return AppSettings(
      unit: unit,
      weightStep: step,
      restSeconds: rest,
      liveActivityEnabled: liveActivity,
      themeMode: mode,
      accent: accent,
      onboardingComplete: onboardingComplete,
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

  Future<void> writeThemeMode(ThemeMode mode) async {
    final str = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_kThemeMode, str);
  }

  Future<void> writeAccent(LsAccent accent) async {
    await _prefs.setString(_kAccent, accent.name);
  }

  Future<void> writeOnboardingComplete(bool complete) async {
    await _prefs.setBool(_kOnboardingComplete, complete);
  }



  /// The persisted active-rest end time in epoch ms, or `0` if none. The caller
  /// validates against `now`: a value in the past means the rest expired while
  /// the app was gone and the key should be cleared (SOW-03 decision #6).
  int readActiveRestEndsAtMs() => _prefs.getInt(_kActiveRestEndsAtMs) ?? 0;

  /// Persist the active-rest end time, or clear the key when [ms] is null/≤0.
  Future<void> writeActiveRestEndsAtMs(int? ms) async {
    if (ms != null && ms > 0) {
      await _prefs.setInt(_kActiveRestEndsAtMs, ms);
    } else {
      await _prefs.remove(_kActiveRestEndsAtMs);
    }
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});
