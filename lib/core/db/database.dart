import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

const _dbFileName = 'simple_gym.db';

/// Current schema version. Exposed so tests open their in-memory databases at
/// exactly the version the app ships.
const kDbVersion = 7;

/// Schema steps in order. Index 0 is the v1 base schema; index N is the step
/// that takes a database from v(N) to v(N+1).
const _steps = <List<String>>[
  schemaV1,
  schemaV2Up,
  schemaV3Up,
  schemaV4Up,
  schemaV5Up,
  schemaV6Up,
  schemaV7Up,
];

Future<Database> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, _dbFileName);
  return openDatabase(
    path,
    version: kDbVersion,
    onConfigure: configureDatabase,
    onCreate: (db, version) => createSchema(db),
    onUpgrade: upgradeSchema,
  );
}

/// Per-connection setup. Foreign keys are off by default in SQLite.
Future<void> configureDatabase(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

/// Build a fresh database at [kDbVersion]: every step, in order.
Future<void> createSchema(Database db) async {
  final batch = db.batch();
  for (final step in _steps) {
    for (final stmt in step) {
      batch.execute(stmt);
    }
  }
  await batch.commit(noResult: true);
}

/// Bring a database from [oldVersion] up to [newVersion] by running every step
/// in between. Steps are cumulative: a v1 database runs v2…vN.
Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) async {
  final batch = db.batch();
  for (var v = oldVersion; v < newVersion && v < _steps.length; v++) {
    for (final stmt in _steps[v]) {
      batch.execute(stmt);
    }
  }
  await batch.commit(noResult: true);
}
