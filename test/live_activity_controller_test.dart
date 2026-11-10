import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/alert_config.dart';
import 'package:ls_workout_tracker/core/settings/settings_repository.dart';
import 'package:ls_workout_tracker/core/theme/app_theme.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/live_activity_controller.dart';
import 'package:ls_workout_tracker/features/workout/domain/active_session.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// QA DEL-18: a Live Activity left on the lock screen by a process iOS
/// killed mid-workout. The new process never learns that card's id, so
/// ending "the one I created" leaves it there — through resume, and even
/// through FINISH. Every start / finish / abandon ends ALL of the app's
/// activities (there is at most one workout).
///
/// The fake models the lock screen: the cards outlive a controller instance
/// (= a process) just like real activities outlive the app.
class _FakePlugin implements LiveActivities {
  _FakePlugin(this.lockScreen);

  final Set<String> lockScreen;
  final calls = <String>[];
  var _seq = 0;

  int get endAllCalls => calls.where((c) => c == 'endAll').length;

  @override
  Future init({
    required String appGroupId,
    String? urlScheme,
    bool requestAndroidNotificationPermission = true,
  }) async {}

  @override
  Future<bool> areActivitiesSupported() async => true;

  @override
  Future<bool> areActivitiesEnabled() async => true;

  @override
  Future<String?> createActivity(
    String activityId,
    Map<String, dynamic> data, {
    String? activityTag,
    bool removeWhenAppIsKilled = false,
    bool iOSEnableRemoteUpdates = true,
    Duration? staleIn,
  }) async {
    calls.add('create');
    final id = 'act-${_seq++}'; // iOS hands out its own ids
    lockScreen.add(id);
    return id;
  }

  @override
  Future createOrUpdateActivity(
    String activityId,
    Map<String, dynamic> data, {
    String? activityTag,
    bool removeWhenAppIsKilled = false,
    bool iOSEnableRemoteUpdates = true,
    Duration? staleIn,
  }) async {
    calls.add('createOrUpdate');
    lockScreen.add(activityId);
    return activityId;
  }

  @override
  Future updateActivity(
    String activityId,
    Map<String, dynamic> data, {
    String? activityTag,
    AlertConfig? alertConfig,
  }) async {
    calls.add('update');
  }

  @override
  Future endActivity(String activityId, {String? activityTag}) async {
    calls.add('end');
    lockScreen.remove(activityId);
  }

  @override
  Future endAllActivities() async {
    calls.add('endAll');
    lockScreen.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

PlannedExercise _ex(String id) => PlannedExercise(
      programExerciseId: 'pe-$id',
      exerciseId: id,
      exerciseName: 'Ex $id',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 60,
    );

ActiveSession _session() => ActiveSession(
      sessionId: 'sess',
      programDayId: 'day',
      startedAt: DateTime.now(),
      queue: [_ex('a')],
      cursor: const Cursor(exerciseIdx: 0, setIdx: 0),
      loggedSets: const [],
    );

void main() {
  final accent = lsAccents.first;

  group('LiveActivityController', () {
    late Set<String> lockScreen;
    setUp(() => lockScreen = <String>{});

    LiveActivityController process(_FakePlugin plugin) =>
        LiveActivityController(plugin: plugin, supported: true);

    test('start ends every activity first, so a resume leaves one card',
        () async {
      // The first process starts the workout, then iOS kills it.
      final dead = _FakePlugin(lockScreen);
      await process(dead).start(
          session: _session(), unit: WeightUnit.kg, accent: accent);
      expect(lockScreen, hasLength(1));

      // The relaunched process resumes and starts a new card.
      final plugin = _FakePlugin(lockScreen);
      await process(plugin).start(
          session: _session(), unit: WeightUnit.kg, accent: accent);
      expect(plugin.calls, ['endAll', 'create']);
      expect(lockScreen, hasLength(1), reason: 'the stale card is gone');
    });

    test('update with no known card ends every activity before creating',
        () async {
      final dead = _FakePlugin(lockScreen);
      await process(dead).start(
          session: _session(), unit: WeightUnit.kg, accent: accent);

      final plugin = _FakePlugin(lockScreen);
      final la = process(plugin);
      await la.update(
          session: _session(), unit: WeightUnit.kg, accent: accent);
      expect(plugin.calls, ['endAll', 'createOrUpdate']);
      expect(lockScreen, hasLength(1));

      // Once it knows its card, an update just updates it.
      await la.update(
          session: _session(), unit: WeightUnit.kg, accent: accent);
      expect(plugin.calls, ['endAll', 'createOrUpdate', 'update']);
    });

    test('endAll clears a card this process never created', () async {
      final dead = _FakePlugin(lockScreen);
      await process(dead).start(
          session: _session(), unit: WeightUnit.kg, accent: accent);

      final plugin = _FakePlugin(lockScreen);
      await process(plugin).endAll();
      expect(plugin.endAllCalls, 1);
      expect(lockScreen, isEmpty);
    });

    test('does nothing off iOS', () async {
      final plugin = _FakePlugin(lockScreen);
      final la = LiveActivityController(plugin: plugin, supported: false);
      await la.start(session: _session(), unit: WeightUnit.kg, accent: accent);
      await la.update(
          session: _session(), unit: WeightUnit.kg, accent: accent);
      await la.endAll();
      expect(plugin.calls, isEmpty);
    });
  });

  group('workout finish / abandon end every activity', () {
    setUpAll(sqfliteFfiInit);

    late Database db;
    late String dayId;
    late Set<String> lockScreen;

    setUp(() async {
      db = await openTestDb();
      final dao = ProgramDao(db);
      final p = await dao.createProgram('PPL');
      dayId = (await dao.createDay(p.id, 'Push')).id;
      await dao.addProgramExercise(
        programDayId: dayId,
        exerciseName: 'Bench Press',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 10,
        defaultWeightKg: 80,
      );
      lockScreen = <String>{};
    });
    tearDown(() async => db.close());

    Future<(ProviderContainer, _FakePlugin)> container() async {
      SharedPreferences.setMockInitialValues({'settings.live_activity': true});
      final prefs = await SharedPreferences.getInstance();
      final plugin = _FakePlugin(lockScreen);
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        liveActivityControllerProvider.overrideWithValue(
            LiveActivityController(plugin: plugin, supported: true)),
      ]);
      addTearDown(c.dispose);
      await c.read(activeSessionProvider.future);
      return (c, plugin);
    }

    /// A card a killed process left behind, plus a workout started now.
    Future<(ProviderContainer, _FakePlugin)> startWithStaleCard() async {
      lockScreen.add('stale-from-dead-process');
      final (c, plugin) = await container();
      await c.read(activeSessionProvider.notifier).start(dayId);
      await c
          .read(activeSessionProvider.notifier)
          .logSet(reps: 8, weightKg: 80, rir: 1);
      expect(plugin.calls.first, 'endAll', reason: 'start clears it');
      // Put it back: the strongest case is a card start() could not see.
      lockScreen.add('stale-from-dead-process');
      return (c, plugin);
    }

    test('finish', () async {
      final (c, plugin) = await startWithStaleCard();
      final before = plugin.endAllCalls;
      await c.read(activeSessionProvider.notifier).finish();
      expect(plugin.endAllCalls, before + 1);
      expect(plugin.calls.last, 'endAll');
      expect(lockScreen, isEmpty);
    });

    test('abandon', () async {
      final (c, plugin) = await startWithStaleCard();
      final before = plugin.endAllCalls;
      await c.read(activeSessionProvider.notifier).abandon();
      expect(plugin.endAllCalls, before + 1);
      expect(plugin.calls.last, 'endAll');
      expect(lockScreen, isEmpty);
    });
  });
}
