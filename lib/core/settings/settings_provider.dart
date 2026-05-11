import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
