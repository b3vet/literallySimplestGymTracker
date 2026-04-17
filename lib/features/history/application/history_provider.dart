import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../programs/application/programs_provider.dart';
import '../../workout/application/active_workout_controller.dart';
import '../../workout/domain/workout_session.dart';
import '../../workout/domain/workout_set.dart';

class SessionSummaryRow {
  const SessionSummaryRow({
    required this.session,
    required this.setCount,
    required this.totalVolumeKg,
    required this.topExerciseName,
    required this.dayName,
  });
  final WorkoutSession session;
  final int setCount;
  final double totalVolumeKg;
  final String? topExerciseName;
  final String? dayName;
}

class SessionDetailData {
  SessionDetailData({
    required this.session,
    required this.sets,
    required this.exerciseNames,
    required this.dayName,
  });
  final WorkoutSession session;
  final List<WorkoutSet> sets;
  final Map<String, String> exerciseNames;
  final String? dayName;
}

final historyListProvider =
    FutureProvider<List<SessionSummaryRow>>((ref) async {
  final workoutDao = ref.watch(workoutDaoProvider);
  final programDao = ref.watch(programDaoProvider);
  final sessions = await workoutDao.listCompletedSessions();

  final rows = <SessionSummaryRow>[];
  for (final s in sessions) {
    final sets = await workoutDao.setsForSession(s.id);
    final volume =
        sets.fold<double>(0, (t, x) => t + x.weightKg * x.reps);
    final topExerciseId = _mostFrequentExerciseId(sets);
    String? topName;
    if (topExerciseId != null) {
      final e = await programDao.findExercise(topExerciseId);
      topName = e?.name;
    }
    String? dayName;
    if (s.programDayId != null) {
      final d = await programDao.findDay(s.programDayId!);
      dayName = d?.name;
    }
    rows.add(SessionSummaryRow(
      session: s,
      setCount: sets.length,
      totalVolumeKg: volume,
      topExerciseName: topName,
      dayName: dayName,
    ));
  }
  return rows;
});

final sessionDetailProvider =
    FutureProvider.family<SessionDetailData?, String>((ref, id) async {
  final workoutDao = ref.watch(workoutDaoProvider);
  final programDao = ref.watch(programDaoProvider);
  final session = await workoutDao.findSession(id);
  if (session == null) return null;
  final sets = await workoutDao.setsForSession(id);
  final exerciseIds = sets.map((s) => s.exerciseId).toSet();
  final names = <String, String>{};
  for (final eid in exerciseIds) {
    final e = await programDao.findExercise(eid);
    if (e != null) names[eid] = e.name;
  }
  String? dayName;
  if (session.programDayId != null) {
    final d = await programDao.findDay(session.programDayId!);
    dayName = d?.name;
  }
  return SessionDetailData(
    session: session,
    sets: sets,
    exerciseNames: names,
    dayName: dayName,
  );
});

String? _mostFrequentExerciseId(List<WorkoutSet> sets) {
  if (sets.isEmpty) return null;
  final counts = <String, int>{};
  for (final s in sets) {
    counts.update(s.exerciseId, (v) => v + 1, ifAbsent: () => 1);
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}
