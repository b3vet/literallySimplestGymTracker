import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:ls_workout_tracker/features/programs/data/program_dao.dart';
import 'package:ls_workout_tracker/features/workout/application/active_workout_controller.dart';
import 'package:ls_workout_tracker/features/workout/application/rest_timer_controller.dart';
import 'package:ls_workout_tracker/main.dart'
    show databaseProvider, sharedPreferencesProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SOW-03 §5: a running rest must be cleared — in memory AND on disk — when the
/// workout finishes or is discarded. Otherwise the persisted end-time (added by
/// SOW-03) resurrects a rest on relaunch for a workout that's over, or leaks
/// into the next session. These exercise the real controller termination paths,
/// which is where an on-phone-discard leak slipped through review.
void main() {
  const kRestKey = 'active_rest_ends_at_ms';

  setUpAll(sqfliteFfiInit);

  Future<Database> openDb() => databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 6,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            final b = db.batch();
            for (final stmt in [
              ...schemaV1,
              ...schemaV2Up,
              ...schemaV3Up,
              ...schemaV4Up,
              ...schemaV5Up,
              ...schemaV6Up,
            ]) {
              b.execute(stmt);
            }
            await b.commit(noResult: true);
          },
        ),
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Open a seeded DB + container with an active session and a running rest.
  Future<(ProviderContainer, SharedPreferences, Database)> withRunningRest()
      async {
    SharedPreferences.setMockInitialValues({'settings.live_activity': false});
    final prefs = await SharedPreferences.getInstance();
    final db = await openDb();

    final programDao = ProgramDao(db);
    final program = await programDao.createProgram('PPL');
    final day = await programDao.createDay(program.id, 'Push A');
    await programDao.addProgramExercise(
      programDayId: day.id,
      exerciseName: 'Bench Press',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      defaultWeightKg: 80,
    );

    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(c.dispose);
    addTearDown(db.close);

    await c.read(activeSessionProvider.future); // resolves to null (none active)
    await c.read(activeSessionProvider.notifier).start(day.id);
    c.read(restTimerProvider.notifier).start(90);
    await settle();
    expect(prefs.getInt(kRestKey), isNotNull, reason: 'rest persisted on start');
    expect(c.read(restTimerProvider).running, isTrue);
    return (c, prefs, db);
  }

  test('finish() clears the persisted + in-memory rest', () async {
    final (c, prefs, _) = await withRunningRest();

    await c.read(activeSessionProvider.notifier).finish();
    await settle();

    expect(prefs.getInt(kRestKey), isNull, reason: 'no rest survives finish');
    expect(c.read(restTimerProvider).running, isFalse);
  });

  test('abandon() (discard) clears the persisted + in-memory rest', () async {
    final (c, prefs, _) = await withRunningRest();

    await c.read(activeSessionProvider.notifier).abandon();
    await settle();

    // The regression this guards: a discarded workout must not resurrect its
    // rest on the next launch, nor leak its end-time into the next session.
    expect(prefs.getInt(kRestKey), isNull, reason: 'no rest survives discard');
    expect(c.read(restTimerProvider).running, isFalse);
  });
}
