import 'package:flutter_test/flutter_test.dart';
import 'package:ls_workout_tracker/core/db/database.dart';
import 'package:ls_workout_tracker/core/db/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/test_db.dart';

/// Table → ordered column names, plus index names: enough to tell two schemas
/// apart.
Future<Map<String, Object>> _shape(Database db) async {
  final out = <String, Object>{};
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
    'ORDER BY name',
  );
  for (final t in tables) {
    final name = t['name'] as String;
    final cols = await db.rawQuery('PRAGMA table_info($name)');
    out[name] = cols.map((c) => c['name']).toList()..sort();
  }
  final idx = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  out['__indexes'] = idx.map((r) => r['name']).toList();
  return out;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('a v1 database upgraded step by step matches a fresh create', () async {
    // Opened one after the other: two concurrent `:memory:` handles collide.
    final upgraded = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: configureDatabase,
        onCreate: (db, _) async {
          for (final stmt in schemaV1) {
            await db.execute(stmt);
          }
        },
      ),
    );
    await upgradeSchema(upgraded, 1, kDbVersion);
    final upgradedShape = await _shape(upgraded);
    await upgraded.close();

    final fresh = await openTestDb();
    final freshShape = await _shape(fresh);
    await fresh.close();

    expect(upgradedShape, freshShape);
    expect(freshShape.keys, contains('session_exercise_overrides'));
  });

  test('foreign keys are enforced on every connection', () async {
    final db = await openTestDb();
    addTearDown(db.close);
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    expect(fk.first.values.first, 1);
  });
}
