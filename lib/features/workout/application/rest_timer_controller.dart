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

  @override
  RestTimerState build() {
    ref.onDispose(() => _expiryTimer?.cancel());
    return const RestTimerState();
  }

  void start(int seconds) {
    state = RestTimerState(
      endsAt: DateTime.now().add(Duration(seconds: seconds)),
    );
    _rescheduleExpiry();
    _pushToLiveActivity();
  }

  void dismiss() {
    _expiryTimer?.cancel();
    state = const RestTimerState();
    _pushToLiveActivity();
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
  }

  /// Fire a one-shot timer at the rest-end so we can push an update to clear
  /// the Live Activity countdown the moment the rest naturally completes.
  /// Without this the lock-screen widget would freeze at "0:00" until the
  /// next start/adjust call.
  void _rescheduleExpiry() {
    _expiryTimer?.cancel();
    final endsAt = state.endsAt;
    if (endsAt == null) return;
    final delay = endsAt.difference(DateTime.now());
    if (delay.isNegative) return;
    _expiryTimer = Timer(delay, _onExpiry);
  }

  void _onExpiry() {
    if (state.endsAt == null) return;
    state = const RestTimerState();
    _pushToLiveActivity();
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
