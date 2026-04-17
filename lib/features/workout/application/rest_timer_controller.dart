import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  RestTimerState build() => const RestTimerState();

  void start(int seconds) {
    state = RestTimerState(
      endsAt: DateTime.now().add(Duration(seconds: seconds)),
    );
  }

  void dismiss() {
    state = const RestTimerState();
  }

  void adjust(int deltaSeconds) {
    final now = DateTime.now();
    final base = state.endsAt != null && state.endsAt!.isAfter(now)
        ? state.endsAt!
        : now;
    final next = base.add(Duration(seconds: deltaSeconds));
    if (!next.isAfter(now)) {
      state = const RestTimerState();
    } else {
      state = RestTimerState(endsAt: next);
    }
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(
  RestTimerController.new,
);
