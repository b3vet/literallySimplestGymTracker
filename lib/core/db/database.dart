import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

const _dbFileName = 'simple_gym.db';
const _dbVersion = 3;

Future<Database> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, _dbFileName);
  return openDatabase(
    path,
    version: _dbVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    onCreate: (db, version) async {
      final batch = db.batch();
      for (final stmt in schemaV1) {
        batch.execute(stmt);
      }
      for (final stmt in schemaV2Up) {
        batch.execute(stmt);
      }
      for (final stmt in schemaV3Up) {
        batch.execute(stmt);
      }
      await batch.commit(noResult: true);
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      final batch = db.batch();
      if (oldVersion < 2) {
        for (final stmt in schemaV2Up) {
          batch.execute(stmt);
        }
      }
      if (oldVersion < 3) {
        for (final stmt in schemaV3Up) {
          batch.execute(stmt);
        }
      }
      await batch.commit(noResult: true);
    },
  );
}
