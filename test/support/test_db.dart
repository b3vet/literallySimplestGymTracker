import 'package:ls_workout_tracker/core/db/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fresh in-memory database built by the app's own [createSchema], at the
/// version the app ships ([kDbVersion]). Every DAO test opens one of these, so
/// a schema change lands in every test at once.
///
/// Call `sqfliteFfiInit()` in `setUpAll` first.
Future<Database> openTestDb() {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: kDbVersion,
      onConfigure: configureDatabase,
      onCreate: (db, _) => createSchema(db),
      onUpgrade: upgradeSchema,
    ),
  );
}
