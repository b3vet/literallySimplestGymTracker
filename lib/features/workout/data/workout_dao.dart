import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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
}
