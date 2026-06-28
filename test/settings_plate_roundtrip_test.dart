import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart';

void main() {
  test('plate settings default correctly on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsRepository(prefs).read();
    expect(s.barWeightKg, SettingsRepository.defaultBarWeightKg); // 20.0
    expect(s.plateInventoryKg, SettingsRepository.defaultPlateInventoryKg);
  });

  test('bar weight + inventory round-trip through SharedPreferences (restart)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SettingsRepository(prefs);
    await repo.writeBarWeightKg(15.0);
    await repo.writePlateInventoryKg(<double>[20, 10, 2.5]);

    // Re-read from the same backing store (simulates an app restart).
    final s = SettingsRepository(prefs).read();
    expect(s.barWeightKg, 15.0);
    expect(s.plateInventoryKg, [20.0, 10.0, 2.5]);
  });
}
