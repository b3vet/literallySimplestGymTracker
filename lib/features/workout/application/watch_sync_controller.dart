import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import 'active_workout_controller.dart';
import 'rest_timer_controller.dart';
import 'watch_bridge.g.dart';
import 'watch_snapshot.dart';

/// PHONE-side sync layer for the Apple Watch companion (SOW §4/§6).
///
/// The phone is the durable store. This controller:
///   * pushes a [WatchSessionSnapshot] to the watch whenever the active
///     session, rest timer, or settings change (mirrors the Live Activity push
///     choreography in [ActiveWorkoutController]);
///   * applies inbound [WatchMutation]s from the watch by reusing the existing
///     controllers/DAO, deduping by (deviceId, seq) and by set id.
///
/// It implements the Pigeon [WatchBridgeFlutterApi] (Swift -> Dart) and wraps
/// the [WatchBridgeHostApi] (Dart -> Swift). Constructed once at app startup
/// (see [watchBridgeControllerProvider]); never disposed for the app's life.
class WatchSyncController implements WatchBridgeFlutterApi {
  WatchSyncController(this._ref) {
    WatchBridgeFlutterApi.setUp(this);
    _activate();
    _wireListeners();
  }

  final Ref _ref;
  final WatchBridgeHostApi _host = WatchBridgeHostApi();

  /// Dedupe ledger for inbound mutations: a bounded set of seen "deviceId:seq"
  /// keys (mirrors the native WCSessionManager). A SET — not a max-`seq` — so an
  /// out-of-order arrival across the durable/fast channels, or a watch relaunch,
  /// is never mistaken for a duplicate and dropped (SOW §6).
  final Set<String> _seenMutationKeys = {};
  final List<String> _seenMutationOrder = [];
  static const int _seenMutationLimit = 512;

  /// Terminal sessions (finish/discard): first event wins, later events for the
  /// same session are ignored.
  final Set<String> _terminalSessions = {};

  /// While applying an inbound mutation we suppress the listener-driven snapshot
  /// push, then push exactly one fresh snapshot at the end of the apply. This
  /// avoids a flurry of intermediate pushes (and any echo) for one inbound
  /// event.
  bool _applyingInbound = false;

  Future<void> _activate() async {
    try {
      await _host.activate();
      debugPrint('[WatchSync] activated');
    } catch (e) {
      debugPrint('[WatchSync] activate failed: $e');
    }
  }

  /// Push a snapshot whenever any of the three authoritative inputs change.
  void _wireListeners() {
    _ref.listen<AsyncValue<dynamic>>(activeSessionProvider, (_, _) {
      _maybePushSnapshot();
    });
    _ref.listen<RestTimerState>(restTimerProvider, (_, _) {
      _maybePushSnapshot();
    });
    _ref.listen<AppSettings>(settingsProvider, (_, _) {
      _maybePushSnapshot();
    });
  }

  void _maybePushSnapshot() {
    if (_applyingInbound) return;
    _pushSnapshot();
  }

  void _pushSnapshot() {
    final snapshot = buildWatchSnapshot(
      session: _ref.read(activeSessionProvider).value,
      rest: _ref.read(restTimerProvider),
      settings: _ref.read(settingsProvider),
    );
    try {
      _host.pushSnapshot(snapshot);
    } catch (e) {
      debugPrint('[WatchSync] pushSnapshot failed: $e');
    }
  }

  // ─── WatchBridgeFlutterApi (Swift -> Dart) ────────────────────────────────

  @override
  void onMutationReceived(WatchMutation m) {
    // Dedupe by (deviceId, seq) with a bounded seen-set: the same mutation can
    // arrive on both the durable (transferUserInfo) and fast (sendMessage)
    // channels. Set membership — not a max seq — so out-of-order / post-relaunch
    // events are never false-dropped.
    final key = '${m.deviceId}:${m.seq}';
    if (_seenMutationKeys.contains(key)) {
      debugPrint(
          '[WatchSync] drop duplicate ${m.type} dev=${m.deviceId} seq=${m.seq}');
      return;
    }
    _seenMutationKeys.add(key);
    _seenMutationOrder.add(key);
    if (_seenMutationOrder.length > _seenMutationLimit) {
      _seenMutationKeys.remove(_seenMutationOrder.removeAt(0));
    }

    // finish/discard are terminal: first wins, later events for that session
    // are ignored.
    if (_terminalSessions.contains(m.sessionId)) {
      debugPrint('[WatchSync] ignore ${m.type}: session already terminal');
      return;
    }

    debugPrint('[WatchSync] <- ${m.type} dev=${m.deviceId} seq=${m.seq}');
    _applyMutation(m);
  }

  void _applyMutation(WatchMutation m) {
    _applyingInbound = true;
    () async {
      try {
        final sessionCtrl = _ref.read(activeSessionProvider.notifier);
        final restCtrl = _ref.read(restTimerProvider.notifier);
        switch (m.type) {
          case WatchMutationType.logSet:
            final set = m.set;
            if (set != null) {
              await sessionCtrl.applyWatchLogSet(set);
            }
          case WatchMutationType.editSet:
            final set = m.set;
            if (set != null) {
              final existing = _ref
                  .read(activeSessionProvider)
                  .value
                  ?.loggedSets
                  .where((s) => s.id == set.id)
                  .firstOrNull;
              // Apply by set id (LWW; v1 just applies the latest received).
              // Reuse the persisted row's session/exercise/index so only the
              // mutable fields change. If the set isn't known locally yet,
              // there's nothing to edit.
              if (existing != null) {
                await sessionCtrl.editSet(
                  existing.copyWith(
                    reps: set.reps,
                    weightKg: set.weightKg,
                    rir: set.rir,
                  ),
                );
              }
            }
          case WatchMutationType.deleteSet:
            final setId = m.setId;
            if (setId != null) {
              await sessionCtrl.deleteSet(setId);
            }
          case WatchMutationType.gotoExercise:
            final idx = m.exerciseIdx;
            if (idx != null) {
              await sessionCtrl.goToExerciseIndex(idx);
            }
          case WatchMutationType.restSet:
            // 0 / null => cancel rest.
            restCtrl.applyRemoteRest(m.restEndsAtMs ?? 0);
          case WatchMutationType.finish:
            _terminalSessions.add(m.sessionId);
            final sid = await sessionCtrl.finish();
            // Surface the completion so the phone UI navigates to the summary,
            // exactly as an on-phone finish would.
            _ref.read(watchEndEventProvider.notifier).emit(
                  WatchEndEvent(sessionId: sid ?? m.sessionId, completed: true),
                );
          case WatchMutationType.discard:
            _terminalSessions.add(m.sessionId);
            await sessionCtrl.abandon();
            _ref.read(watchEndEventProvider.notifier).emit(
                  WatchEndEvent(sessionId: m.sessionId, completed: false),
                );
        }
      } catch (e) {
        debugPrint('[WatchSync] apply ${m.type} failed: $e');
      } finally {
        _applyingInbound = false;
        // Echo one authoritative snapshot so the watch reconciles (sets union
        // by id; cursor/rest/meta authoritative). This is a snapshot, not a
        // mutation, so it cannot trigger a mutation echo back.
        _pushSnapshot();
      }
    }();
  }

  @override
  void onWatchRequestedResync() {
    debugPrint('[WatchSync] resync requested');
    _pushSnapshot();
  }

  @override
  void onReachabilityChanged(bool reachable) {
    debugPrint('[WatchSync] reachable -> $reachable');
    _ref.read(watchConnectedProvider.notifier).set(reachable);
    if (reachable) {
      // Bring the watch up to date the moment it becomes reachable.
      _pushSnapshot();
    }
  }

  @override
  void onWatchJoinedSession(String sessionId) {
    debugPrint('[WatchSync] watch joined session $sessionId');
    _ref.read(watchConnectedProvider.notifier).set(true);
    _pushSnapshot();
  }
}

/// Whether the watch app is currently connected / reachable. Drives the small
/// watch glyph in the active-workout header. Updated by [WatchSyncController]
/// from reachability / join callbacks.
class WatchConnectedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool connected) => state = connected;
}

final watchConnectedProvider =
    NotifierProvider<WatchConnectedNotifier, bool>(WatchConnectedNotifier.new);

/// A workout-end event originated FROM THE WATCH (finish or discard), surfaced
/// to the phone UI so it can navigate the same way an on-phone end would —
/// summary on finish, home on discard. The active-workout screen consumes it
/// once and clears it.
class WatchEndEvent {
  const WatchEndEvent({required this.sessionId, required this.completed});
  final String sessionId;
  final bool completed;
}

class WatchEndEventNotifier extends Notifier<WatchEndEvent?> {
  @override
  WatchEndEvent? build() => null;
  void emit(WatchEndEvent event) => state = event;
  void clear() => state = null;
}

final watchEndEventProvider =
    NotifierProvider<WatchEndEventNotifier, WatchEndEvent?>(
  WatchEndEventNotifier.new,
);

/// Constructed lazily on first read; the constructor sets up the FlutterApi,
/// activates the WCSession, and wires the snapshot-push listeners. Read once at
/// app startup to bring it to life. Name kept stable to avoid churn.
final watchBridgeControllerProvider = Provider<WatchSyncController>((ref) {
  return WatchSyncController(ref);
});
