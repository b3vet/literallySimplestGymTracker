import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import 'active_workout_controller.dart';
import 'live_activity_controller.dart';

class RestTimerState {
  const RestTimerState({this.endsAt});
  final DateTime? endsAt;

  bool get running => endsAt != null && endsAt!.isAfter(DateTime.now());

  Duration get remaining {
    if (endsAt == null) return Duration.zero;
    final d = endsAt!.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}

class RestTimerController extends Notifier<RestTimerState> {
  Timer? _expiryTimer;
  bool _disposed = false;

  @override
  RestTimerState build() {
    ref.onDispose(() {
      _expiryTimer?.cancel();
      _disposed = true;
    });
    // Rehydrate a rest that was running when the app was last killed or
    // backgrounded (SOW-03). The countdown is always derived from `endsAt` vs
    // `now`, so a force-kill loses nothing but the in-memory timer.
    final repo = ref.read(settingsRepositoryProvider);
    final ms = repo.readActiveRestEndsAtMs();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (ms > now) {
      final endsAt = DateTime.fromMillisecondsSinceEpoch(ms);
      _rescheduleExpiry(endsAt);
      // Re-push after build settles — _pushToLiveActivity reads
      // activeSessionProvider, which may itself be (re)building right now (so
      // unlike start()/adjust(), which push synchronously, build() defers).
      // Guard the ref against a dispose that lands before the microtask runs.
      Future.microtask(() {
        if (!_disposed) _pushToLiveActivity();
      });
      return RestTimerState(endsAt: endsAt);
    }
    if (ms > 0) {
      // Rest expired while we were gone — clear it so no stale 0:00 shows
      // (decision #6).
      unawaited(repo.writeActiveRestEndsAtMs(null));
    }
    return const RestTimerState();
  }

  void start(int seconds) {
    state = RestTimerState(
      endsAt: DateTime.now().add(Duration(seconds: seconds)),
    );
    _rescheduleExpiry();
    _pushToLiveActivity();
    _persist();
  }

  void dismiss() {
    _expiryTimer?.cancel();
    state = const RestTimerState();
    _pushToLiveActivity();
    _persist();
  }

  void adjust(int deltaSeconds) {
    final now = DateTime.now();
    final base = state.endsAt != null && state.endsAt!.isAfter(now)
        ? state.endsAt!
        : now;
    final next = base.add(Duration(seconds: deltaSeconds));
    if (!next.isAfter(now)) {
      state = const RestTimerState();
      _expiryTimer?.cancel();
    } else {
      state = RestTimerState(endsAt: next);
      _rescheduleExpiry();
    }
    _pushToLiveActivity();
    _persist();
  }

  /// Re-validate the persisted rest against the wall clock on app-resume
  /// (decision #5). A long background can suspend [_expiryTimer]; this restores
  /// the correct state and reschedules expiry the instant we return — covering
  /// the case where `build()` already ran (so a cold relaunch is handled there,
  /// and a warm resume here).
  void rehydrate() {
    final repo = ref.read(settingsRepositoryProvider);
    final ms = repo.readActiveRestEndsAtMs();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (ms > now) {
      final endsAt = DateTime.fromMillisecondsSinceEpoch(ms);
      if (state.endsAt != endsAt) state = RestTimerState(endsAt: endsAt);
      _rescheduleExpiry(endsAt);
      _pushToLiveActivity();
    } else if (state.endsAt != null || ms > 0) {
      // Expired (or cleared elsewhere) while backgrounded — drop the banner.
      _expiryTimer?.cancel();
      state = const RestTimerState();
      _pushToLiveActivity();
      _persist();
    }
  }

  /// Apply a rest end-time that arrived FROM the watch (SOW §6, last-writer-
  /// wins). [endsAtMs] is an absolute epoch; 0 or any past value cancels rest.
  ///
  /// This is an inbound apply: it updates local state + the Live Activity, but
  /// the watch-side echo is suppressed by the sync controller (which ignores
  /// the listener tick this state change triggers) so we don't bounce the same
  /// rest back to the watch.
  void applyRemoteRest(int endsAtMs) {
    final now = DateTime.now();
    if (endsAtMs <= now.millisecondsSinceEpoch) {
      dismiss();
      return;
    }
    state = RestTimerState(
      endsAt: DateTime.fromMillisecondsSinceEpoch(endsAtMs),
    );
    _rescheduleExpiry();
    _pushToLiveActivity();
    _persist();
  }

  /// Fire a one-shot timer at the rest-end so we can push an update to clear
  /// the Live Activity countdown the moment the rest naturally completes.
  /// Without this the lock-screen widget would freeze at "0:00" until the
  /// next start/adjust call. [endsAtOverride] lets `build()`/`rehydrate()`
  /// schedule before `state` is settled.
  void _rescheduleExpiry([DateTime? endsAtOverride]) {
    _expiryTimer?.cancel();
    final endsAt = endsAtOverride ?? state.endsAt;
    if (endsAt == null) return;
    final delay = endsAt.difference(DateTime.now());
    if (delay.isNegative) return;
    _expiryTimer = Timer(delay, _onExpiry);
  }

  void _onExpiry() {
    if (state.endsAt == null) return;
    state = const RestTimerState();
    _pushToLiveActivity();
    _persist();
  }

  /// Mirror the current rest to disk so it survives a force-kill (SOW-03).
  /// Fire-and-forget: the read path (`build`/`rehydrate`) always re-validates
  /// against `now`, so a write that lands late or never is self-healing.
  void _persist() {
    final repo = ref.read(settingsRepositoryProvider);
    final endsAt = state.endsAt;
    if (endsAt != null && endsAt.isAfter(DateTime.now())) {
      unawaited(repo.writeActiveRestEndsAtMs(endsAt.millisecondsSinceEpoch));
    } else {
      unawaited(repo.writeActiveRestEndsAtMs(null));
    }
  }

  void _pushToLiveActivity() {
    final settings = ref.read(settingsProvider);
    if (!settings.liveActivityEnabled) return;
    final session = ref.read(activeSessionProvider).value;
    if (session == null) return;
    final unit = settings.unit ?? WeightUnit.kg;
    final accent = lsAccentSpec(settings.accent);
    ref.read(liveActivityControllerProvider).update(
          session: session,
          unit: unit,
          accent: accent,
          restEndsAt: state.running ? state.endsAt : null,
        );
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(
  RestTimerController.new,
);
