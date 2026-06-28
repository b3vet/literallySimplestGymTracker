import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/features/workout/application/rest_timer_controller.dart';
import 'package:ls_workout_tracker/main.dart' show sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';

/// SOW-03 core fix: the rest timer's absolute end-time is mirrored to
/// SharedPreferences on every state change and rehydrated on launch/resume, so
/// a force-kill mid-rest recovers to the exact remaining time. These tests pin
/// the persistence contract; the on-device Live Activity behaviour is covered
/// by the SOW §8 manual matrix (M1–M11), which widget tests can't reach.
void main() {
  const kKey = 'active_rest_ends_at_ms';

  // liveActivityEnabled:false keeps _pushToLiveActivity short-circuiting before
  // it touches the session / native plugin, isolating the controller's logic.
  Future<SharedPreferences> prefsWith([Map<String, Object> extra = const {}]) {
    SharedPreferences.setMockInitialValues({
      'settings.live_activity': false,
      ...extra,
    });
    return SharedPreferences.getInstance();
  }

  ProviderContainer container(SharedPreferences prefs) {
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  // Let fire-and-forget pref writes and the build()-restore microtask settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  int futureMs([int seconds = 120]) =>
      DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch;
  int pastMs([int seconds = 5]) =>
      DateTime.now().subtract(Duration(seconds: seconds)).millisecondsSinceEpoch;

  test('start() persists a future end-time and runs', () async {
    final prefs = await prefsWith();
    final c = container(prefs);
    c.read(restTimerProvider.notifier).start(90);
    await settle();

    expect(c.read(restTimerProvider).running, isTrue);
    final ms = prefs.getInt(kKey);
    expect(ms, isNotNull);
    expect(ms! > DateTime.now().millisecondsSinceEpoch, isTrue);
  });

  test('build() restores a still-running rest from the pref', () async {
    final ends = futureMs();
    final prefs = await prefsWith({kKey: ends});
    final c = container(prefs);

    final state = c.read(restTimerProvider); // triggers build()
    expect(state.running, isTrue);
    expect(state.endsAt!.millisecondsSinceEpoch, ends);
    await settle();
  });

  test('build() clears a rest that expired while the app was gone', () async {
    final prefs = await prefsWith({kKey: pastMs()});
    final c = container(prefs);

    final state = c.read(restTimerProvider);
    expect(state.running, isFalse);
    expect(state.endsAt, isNull);
    await settle();
    expect(prefs.getInt(kKey), isNull, reason: 'no stale 0:00 ghost');
  });

  test('dismiss() clears the persisted rest', () async {
    final prefs = await prefsWith();
    final c = container(prefs);
    c.read(restTimerProvider.notifier).start(90);
    await settle();
    expect(prefs.getInt(kKey), isNotNull);

    c.read(restTimerProvider.notifier).dismiss();
    await settle();
    expect(prefs.getInt(kKey), isNull);
    expect(c.read(restTimerProvider).running, isFalse);
  });

  test('adjust() persists the extended end-time', () async {
    final prefs = await prefsWith();
    final c = container(prefs);
    c.read(restTimerProvider.notifier).start(60);
    await settle();
    final before = prefs.getInt(kKey)!;

    c.read(restTimerProvider.notifier).adjust(30);
    await settle();
    final after = prefs.getInt(kKey)!;
    expect(after - before, inInclusiveRange(28000, 32000)); // ~+30s
  });

  test('applyRemoteRest persists a future end-time, clears a past one',
      () async {
    final prefs = await prefsWith();
    final c = container(prefs);

    final ends = futureMs(60);
    c.read(restTimerProvider.notifier).applyRemoteRest(ends);
    await settle();
    expect(prefs.getInt(kKey), ends);
    expect(c.read(restTimerProvider).running, isTrue);

    // A past (or 0) end-time means the watch cancelled rest.
    c.read(restTimerProvider.notifier).applyRemoteRest(pastMs(1));
    await settle();
    expect(prefs.getInt(kKey), isNull);
    expect(c.read(restTimerProvider).running, isFalse);
  });

  test('rehydrate() drops a rest that expired while backgrounded', () async {
    final prefs = await prefsWith();
    final c = container(prefs);
    c.read(restTimerProvider.notifier).start(60);
    await settle();
    expect(c.read(restTimerProvider).running, isTrue);

    // Simulate the rest ending during a long background suspension.
    await prefs.setInt(kKey, pastMs(1));
    c.read(restTimerProvider.notifier).rehydrate();
    await settle();
    expect(c.read(restTimerProvider).running, isFalse);
    expect(prefs.getInt(kKey), isNull);
  });

  test('rehydrate() restores state if the in-memory timer was lost', () async {
    // Pref says a rest is active, but the controller's state is empty (mimics a
    // warm resume where build() already returned empty earlier).
    final ends = futureMs(90);
    final prefs = await prefsWith({kKey: ends});
    final c = container(prefs);
    // Read once so the provider exists; then overwrite the pref to a *different*
    // future value and rehydrate — state must track the pref.
    c.read(restTimerProvider);
    final later = futureMs(300);
    await prefs.setInt(kKey, later);

    c.read(restTimerProvider.notifier).rehydrate();
    await settle();
    expect(c.read(restTimerProvider).running, isTrue);
    expect(c.read(restTimerProvider).endsAt!.millisecondsSinceEpoch, later);
  });
}
