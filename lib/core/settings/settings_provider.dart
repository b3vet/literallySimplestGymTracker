import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart' show LsAccent;
import 'settings_repository.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.read(settingsRepositoryProvider).read();
  }

  Future<void> setUnit(WeightUnit unit) async {
    await ref.read(settingsRepositoryProvider).writeUnit(unit);
    state = state.copyWith(unit: unit, weightStep: unit.defaultStep);
    await ref.read(settingsRepositoryProvider).writeWeightStep(unit.defaultStep);
  }

  Future<void> setWeightStep(double step) async {
    await ref.read(settingsRepositoryProvider).writeWeightStep(step);
    state = state.copyWith(weightStep: step);
  }

  Future<void> setRestSeconds(int seconds) async {
    await ref.read(settingsRepositoryProvider).writeRestSeconds(seconds);
    state = state.copyWith(restSeconds: seconds);
  }

  Future<void> setLiveActivityEnabled(bool enabled) async {
    await ref.read(settingsRepositoryProvider).writeLiveActivityEnabled(enabled);
    state = state.copyWith(liveActivityEnabled: enabled);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(settingsRepositoryProvider).writeThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setAccent(LsAccent accent) async {
    await ref.read(settingsRepositoryProvider).writeAccent(accent);
    state = state.copyWith(accent: accent);
  }

  Future<void> setOnboardingComplete(bool complete) async {
    await ref.read(settingsRepositoryProvider).writeOnboardingComplete(complete);
    state = state.copyWith(onboardingComplete: complete);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
