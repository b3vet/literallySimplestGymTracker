import 'package:sqflite/sqflite.dart';

/// Tables emptied by [wipeAllData], ordered children-before-parents so the
/// deletes satisfy foreign keys without disabling them.
const _tablesInDeleteOrder = <String>[
  'workout_sets',
  'session_exercise_overrides',
  'workout_sessions',
  'program_exercises',
  'program_days',
  'programs',
  'exercises',
];

/// Deletes every row of user data — programs, days, exercises, sessions, sets —
/// leaving the schema intact. Used only by the developer "Reset app data"
/// action; not exposed in release builds. Settings (unit, accent, theme,
/// onboarding flag) live in SharedPreferences and are handled separately.
Future<void> wipeAllData(Database db) async {
  await db.transaction((txn) async {
    for (final table in _tablesInDeleteOrder) {
      await txn.delete(table);
    }
  });
}
