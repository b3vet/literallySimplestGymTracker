import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

const _dbFileName = 'simple_gym.db';
const _dbVersion = 1;

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
      await batch.commit(noResult: true);
    },
  );
}
