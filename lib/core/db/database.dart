import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

const _dbFileName = 'simple_gym.db';

/// Current schema version. Exposed so tests open their in-memory databases at
/// exactly the version the app ships.
const kDbVersion = 9;

/// One schema step: plain SQL, or code that inspects the schema first (v8+).
typedef _Step = Future<void> Function(DatabaseExecutor db);

_Step _sql(List<String> statements) => (db) async {
  for (final stmt in statements) {
    await db.execute(stmt);
  }
};

/// Schema steps in order. Index 0 is the v1 base schema; index N is the step
/// that takes a database from v(N) to v(N+1).
final _steps = <_Step>[
  _sql(schemaV1),
  _sql(schemaV2Up),
  _sql(schemaV3Up),
  _sql(schemaV4Up),
  _sql(schemaV5Up),
  _sql(schemaV6Up),
  _sql(schemaV7Up),
  schemaV8Up,
  schemaV9Up,
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
  for (final step in _steps) {
    await step(db);
  }
}

/// Bring a database from [oldVersion] up to [newVersion] by running every step
/// in between. Steps are cumulative: a v1 database runs v2…vN.
///
/// Runs inside sqflite's open transaction (`onCreate` / `onUpgrade`), so a
/// failing step leaves the file at its old version.
Future<void> upgradeSchema(Database db, int oldVersion, int newVersion) async {
  for (var v = oldVersion; v < newVersion && v < _steps.length; v++) {
    await _steps[v](db);
  }
}
