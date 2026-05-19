import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/session_exercise_override.dart';
import '../domain/workout_session.dart';
import '../domain/workout_set.dart';

class WorkoutDao {
  WorkoutDao(this._db);
  final Database _db;
  static const _uuid = Uuid();

  // ---------- Sessions ----------

  Future<WorkoutSession> startSession(String programDayId) async {
    final session = WorkoutSession(
      id: _uuid.v4(),
      programDayId: programDayId,
      startedAt: DateTime.now(),
      status: SessionStatus.active,
    );
    await _db.insert('workout_sessions', session.toRow());
    return session;
  }

  Future<WorkoutSession?> findActiveSession() async {
    final rows = await _db.query(
      'workout_sessions',
      where: 'status = ?',
      whereArgs: [SessionStatus.active.name],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WorkoutSession.fromRow(rows.first);
  }

  Future<WorkoutSession?> findSession(String id) async {
    final rows = await _db.query('workout_sessions',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : WorkoutSession.fromRow(rows.first);
  }

  Future<void> completeSession(String id) async {
    await _db.update(
      'workout_sessions',
      {
        'status': SessionStatus.completed.name,
        'ended_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> abandonSession(String id) async {
    await _db.update(
      'workout_sessions',
      {
        'status': SessionStatus.abandoned.name,
        'ended_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- Sets ----------

  Future<WorkoutSet> insertSet({
    required String sessionId,
    required String exerciseId,
    required int setIndex,
    required int reps,
    required double weightKg,
    required int rir,
  }) async {
    final s = WorkoutSet(
      id: _uuid.v4(),
      sessionId: sessionId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      reps: reps,
      weightKg: weightKg,
      rir: rir,
      loggedAt: DateTime.now(),
    );
    await _db.insert('workout_sets', s.toRow());
    return s;
  }

  Future<void> updateSet(WorkoutSet s) async {
    await _db.update('workout_sets', s.toRow(),
        where: 'id = ?', whereArgs: [s.id]);
  }

  Future<void> deleteSet(String id) async {
    await _db.delete('workout_sets', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WorkoutSet>> setsForSession(String sessionId) async {
    final rows = await _db.query(
      'workout_sets',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'logged_at ASC',
    );
    return rows.map(WorkoutSet.fromRow).toList();
  }

  /// Most recent set logged for this exercise across all sessions.
  /// Returns null if the exercise has never been logged.
  Future<WorkoutSet?> lastSetForExercise(String exerciseId) async {
    final rows = await _db.query(
      'workout_sets',
      where: 'exercise_id = ?',
      whereArgs: [exerciseId],
      orderBy: 'logged_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WorkoutSet.fromRow(rows.first);
  }

  /// Historical max weight for an exercise, excluding sets logged at/after [before].
  Future<double?> historicalMaxWeight(
    String exerciseId, {
    DateTime? before,
  }) async {
    final ts = before?.millisecondsSinceEpoch ?? (1 << 62);
    final rows = await _db.rawQuery(
      'SELECT MAX(weight) AS m FROM workout_sets '
      'WHERE exercise_id = ? AND logged_at < ?',
      [exerciseId, ts],
    );
    if (rows.isEmpty) return null;
    final m = rows.first['m'];
    return m == null ? null : (m as num).toDouble();
  }

  /// Historical max reps at-or-above a given weight for an exercise, excluding sets at/after [before].
  Future<int?> historicalMaxRepsAtWeight(
    String exerciseId, {
    required double weightKg,
    DateTime? before,
  }) async {
    final ts = before?.millisecondsSinceEpoch ?? (1 << 62);
    final rows = await _db.rawQuery(
      'SELECT MAX(reps) AS m FROM workout_sets '
      'WHERE exercise_id = ? AND weight >= ? AND logged_at < ?',
      [exerciseId, weightKg, ts],
    );
    if (rows.isEmpty) return null;
    final m = rows.first['m'];
    return m == null ? null : (m as num).toInt();
  }

  // ---------- History ----------

  Future<List<WorkoutSession>> listCompletedSessions({int limit = 100}) async {
    final rows = await _db.query(
      'workout_sessions',
      where: 'status = ?',
      whereArgs: [SessionStatus.completed.name],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(WorkoutSession.fromRow).toList();
  }

  /// Most recent completed session for the given program day. Used by the
  /// Start Workout screen to show "LAST 13M" alongside each day card.
  Future<WorkoutSession?> lastCompletedSessionForDay(
      String programDayId) async {
    final rows = await _db.query(
      'workout_sessions',
      where: 'program_day_id = ? AND status = ?',
      whereArgs: [programDayId, SessionStatus.completed.name],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WorkoutSession.fromRow(rows.first);
  }

  /// Most recent completed session for the given program day, started strictly
  /// before [before]. Returns null if none exists.
  Future<WorkoutSession?> previousCompletedSessionForDay(
    String programDayId, {
    required DateTime before,
  }) async {
    final rows = await _db.query(
      'workout_sessions',
      where: 'program_day_id = ? AND status = ? AND started_at < ?',
      whereArgs: [
        programDayId,
        SessionStatus.completed.name,
        before.millisecondsSinceEpoch,
      ],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WorkoutSession.fromRow(rows.first);
  }

  /// Tonnage (sum of weight × reps in kg) per completed session, most recent
  /// first. Used for the post-workout trend chart.
  Future<List<TonnagePoint>> totalTonnageBySession({int limit = 8}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT s.id AS id, s.started_at AS started_at,
             COALESCE(SUM(w.weight * w.reps), 0) AS tonnage
      FROM workout_sessions s
      LEFT JOIN workout_sets w ON w.session_id = s.id
      WHERE s.status = ?
      GROUP BY s.id
      ORDER BY s.started_at DESC
      LIMIT ?
      ''',
      [SessionStatus.completed.name, limit],
    );
    return rows
        .map((r) => TonnagePoint(
              sessionId: r['id'] as String,
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                  (r['started_at'] as num).toInt()),
              tonnageKg: (r['tonnage'] as num).toDouble(),
            ))
        .toList();
  }
}

class TonnagePoint {
  const TonnagePoint({
    required this.sessionId,
    required this.startedAt,
    required this.tonnageKg,
  });
  final String sessionId;
  final DateTime startedAt;
  final double tonnageKg;
}

// ---------- Session exercise overrides ----------

extension WorkoutDaoOverrides on WorkoutDao {
  /// Insert-or-update a session-scoped override for the given program
  /// exercise slot. Re-swapping the same slot updates the row in place;
  /// `previous_exercise_id` is rotated to whatever was the slot's last
  /// known exercise so the UI can surface a "PREVIOUS:" affordance.
  Future<void> upsertOverride({
    required String sessionId,
    required String programExerciseId,
    required String exerciseId,
    String? previousExerciseId,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required double defaultWeightKg,
    double? weightStepKg,
  }) async {
    // Look up the existing override (if any) so we can preserve its id and
    // rotate previous_exercise_id correctly. sqflite has no UPSERT helper,
    // so we do this with an explicit lookup + insert/update.
    final existing = await _db.query(
      'session_exercise_overrides',
      where: 'session_id = ? AND program_exercise_id = ?',
      whereArgs: [sessionId, programExerciseId],
      limit: 1,
    );
    final row = <String, Object?>{
      'session_id': sessionId,
      'program_exercise_id': programExerciseId,
      'exercise_id': exerciseId,
      'previous_exercise_id': previousExerciseId,
      'target_sets': targetSets,
      'target_reps_min': targetRepsMin,
      'target_reps_max': targetRepsMax,
      'default_weight': defaultWeightKg,
      'weight_step': weightStepKg,
    };
    if (existing.isEmpty) {
      row['id'] = const Uuid().v4();
      await _db.insert('session_exercise_overrides', row);
    } else {
      await _db.update(
        'session_exercise_overrides',
        row,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  /// Drop the override for a slot. Used by "REVERT TO PLAN" in the
  /// active-workout edit sheet.
  Future<void> deleteOverride({
    required String sessionId,
    required String programExerciseId,
  }) async {
    await _db.delete(
      'session_exercise_overrides',
      where: 'session_id = ? AND program_exercise_id = ?',
      whereArgs: [sessionId, programExerciseId],
    );
  }

  /// All overrides for a session, with the substituted exercise's name
  /// joined in. Used at resume time to re-apply overrides to the in-memory
  /// queue.
  Future<List<SessionExerciseOverride>> overridesForSession(
      String sessionId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT seo.*, e.name AS exercise_name
      FROM session_exercise_overrides seo
      JOIN exercises e ON e.id = seo.exercise_id
      WHERE seo.session_id = ?
      ''',
      [sessionId],
    );
    return rows
        .map((r) => SessionExerciseOverride(
              id: r['id'] as String,
              sessionId: r['session_id'] as String,
              programExerciseId: r['program_exercise_id'] as String,
              exerciseId: r['exercise_id'] as String,
              exerciseName: r['exercise_name'] as String,
              previousExerciseId: r['previous_exercise_id'] as String?,
              targetSets: (r['target_sets'] as num).toInt(),
              targetRepsMin: (r['target_reps_min'] as num).toInt(),
              targetRepsMax: (r['target_reps_max'] as num).toInt(),
              defaultWeightKg: (r['default_weight'] as num).toDouble(),
              weightStepKg: r['weight_step'] == null
                  ? null
                  : (r['weight_step'] as num).toDouble(),
            ))
        .toList();
  }
}
