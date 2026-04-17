import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../programs/application/programs_provider.dart';
import '../../programs/domain/exercise.dart';
import '../../workout/application/active_workout_controller.dart';
import '../../../main.dart' show databaseProvider;

class ExerciseProgressionPoint {
  const ExerciseProgressionPoint({
    required this.date,
    required this.topWeightKg,
    required this.totalVolumeKg,
    required this.est1RMKg,
  });
  final DateTime date;
  final double topWeightKg;
  final double totalVolumeKg;
  final double est1RMKg;
}

class ExerciseProgression {
  const ExerciseProgression({
    required this.exerciseId,
    required this.points,
  });
  final String exerciseId;
  final List<ExerciseProgressionPoint> points;
}

/// List of exercises that have ever been logged (for the stats selector).
final loggedExercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.rawQuery('''
    SELECT DISTINCT e.id, e.name, e.notes
    FROM exercises e
    JOIN workout_sets ws ON ws.exercise_id = e.id
    JOIN workout_sessions s ON s.id = ws.session_id
    WHERE s.status = 'completed'
    ORDER BY e.name COLLATE NOCASE
  ''');
  return rows.map(Exercise.fromRow).toList();
});

final exerciseProgressionProvider = FutureProvider.family<
    ExerciseProgression, String>((ref, exerciseId) async {
  final db = ref.watch(databaseProvider);
  // Ensure invalidation chains through.
  ref.watch(workoutDaoProvider);
  ref.watch(programDaoProvider);

  final rows = await db.rawQuery('''
    SELECT s.id as session_id, s.started_at, ws.weight, ws.reps
    FROM workout_sets ws
    JOIN workout_sessions s ON s.id = ws.session_id
    WHERE ws.exercise_id = ? AND s.status = 'completed'
    ORDER BY s.started_at ASC, ws.logged_at ASC
  ''', [exerciseId]);

  final bySession = <String, List<Map<String, Object?>>>{};
  final startedAtBySession = <String, int>{};
  for (final r in rows) {
    final sid = r['session_id'] as String;
    bySession.putIfAbsent(sid, () => []).add(r);
    startedAtBySession[sid] = r['started_at'] as int;
  }

  final points = <ExerciseProgressionPoint>[];
  final sessionIds = bySession.keys.toList()
    ..sort((a, b) => startedAtBySession[a]!.compareTo(startedAtBySession[b]!));
  for (final sid in sessionIds) {
    final sessionSets = bySession[sid]!;
    double top = 0;
    double volume = 0;
    double best1rm = 0;
    for (final r in sessionSets) {
      final w = (r['weight'] as num).toDouble();
      final reps = r['reps'] as int;
      if (w > top) top = w;
      volume += w * reps;
      // Epley formula; clamps 1RM to the weight when reps == 1.
      final est = w * (1 + reps / 30);
      if (est > best1rm) best1rm = est;
    }
    points.add(ExerciseProgressionPoint(
      date: DateTime.fromMillisecondsSinceEpoch(startedAtBySession[sid]!),
      topWeightKg: top,
      totalVolumeKg: volume,
      est1RMKg: best1rm,
    ));
  }
  return ExerciseProgression(exerciseId: exerciseId, points: points);
});

// Returns the largest delta in the given list's last value vs any earlier value within N days.
double trendDelta(
    List<ExerciseProgressionPoint> points, double Function(ExerciseProgressionPoint) get,
    {int days = 30}) {
  if (points.length < 2) return 0;
  final now = points.last.date;
  final cutoff = now.subtract(Duration(days: days));
  final earlier = points
      .where((p) => p.date.isBefore(now) && p.date.isAfter(cutoff))
      .toList();
  if (earlier.isEmpty) return 0;
  final base = earlier.map(get).reduce(min);
  return get(points.last) - base;
}
