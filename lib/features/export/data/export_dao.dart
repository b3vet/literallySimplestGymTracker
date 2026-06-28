import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../main.dart' show databaseProvider;
import '../domain/export_models.dart';

/// Read-only aggregate over the existing tables for a full export. No writes,
/// no new tables — the DB stays at v6.
class ExportDao {
  ExportDao(this._db);
  final Database _db;

  /// All **completed** sessions with their sets, oldest→newest, names + stable
  /// ids joined. Empty sessions survive (LEFT JOIN) with an empty `sets` list.
  /// Abandoned / active sessions are excluded (matches history/stats semantics).
  /// Ordered with `group_seq` last so drop-set members emit deterministically.
  Future<List<ExportSession>> exportAllSessions() async {
    final rows = await _db.rawQuery('''
      SELECT s.id AS session_id, s.started_at AS started_at, s.ended_at AS ended_at,
             s.program_day_id AS program_day_id, d.program_id AS program_id,
             p.name AS program_name, d.name AS day_name,
             w.id AS set_id, w.exercise_id AS exercise_id, e.name AS exercise_name,
             w.set_index AS set_index, w.reps AS reps, w.weight AS weight,
             w.rir AS rir, w.logged_at AS logged_at,
             w.set_group AS set_group, w.group_seq AS group_seq
      FROM workout_sessions s
      LEFT JOIN workout_sets w ON w.session_id = s.id
      LEFT JOIN exercises e ON e.id = w.exercise_id
      LEFT JOIN program_days d ON d.id = s.program_day_id
      LEFT JOIN programs p ON p.id = d.program_id
      WHERE s.status = ?
      ORDER BY s.started_at ASC, w.set_index ASC, w.logged_at ASC, w.group_seq ASC
    ''', ['completed']);

    final byId = <String, ExportSession>{};
    final order = <String>[];
    for (final r in rows) {
      final sid = r['session_id'] as String;
      final session = byId.putIfAbsent(sid, () {
        order.add(sid);
        return ExportSession(
          id: sid,
          startedAt: _ms(r['started_at']),
          endedAt: r['ended_at'] == null ? null : _ms(r['ended_at']),
          programDayId: r['program_day_id'] as String?,
          programId: r['program_id'] as String?,
          programName: r['program_name'] as String?,
          dayName: r['day_name'] as String?,
        );
      });
      // LEFT JOIN yields one all-null-set row for a session with no sets.
      if (r['set_id'] != null) {
        session.sets.add(ExportSetRow(
          id: r['set_id'] as String,
          loggedAt: _ms(r['logged_at']),
          exercise: (r['exercise_name'] as String?) ?? '',
          exerciseId: (r['exercise_id'] as String?) ?? '',
          setNumber: (r['set_index'] as num).toInt(),
          reps: (r['reps'] as num).toInt(),
          weightKg: (r['weight'] as num).toDouble(),
          rir: (r['rir'] as num).toInt(),
          setGroup: r['set_group'] as String?,
          groupSeq: (r['group_seq'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    return [for (final sid in order) byId[sid]!];
  }

  static DateTime _ms(Object? v) =>
      DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
}

final exportDaoProvider = Provider<ExportDao>(
  (ref) => ExportDao(ref.watch(databaseProvider)),
);
