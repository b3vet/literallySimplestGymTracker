import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/active_workout_controller.dart';
import '../../workout/domain/workout_session.dart';

/// Compact summary of the user's most recent completed workout — feeds the
/// "LAST · 6 SETS · 930 KG · 13M" strip at the bottom of the home screen.
class LastSessionSummary {
  const LastSessionSummary({
    required this.session,
    required this.setCount,
    required this.totalVolumeKg,
    required this.durationMin,
  });
  final WorkoutSession session;
  final int setCount;
  final double totalVolumeKg;
  final int durationMin;
}

final lastSessionSummaryProvider =
    FutureProvider<LastSessionSummary?>((ref) async {
  final dao = ref.watch(workoutDaoProvider);
  final sessions = await dao.listCompletedSessions(limit: 1);
  if (sessions.isEmpty) return null;
  final s = sessions.first;
  final sets = await dao.setsForSession(s.id);
  final tonnage = sets.fold<double>(0, (t, x) => t + x.weightKg * x.reps);
  return LastSessionSummary(
    session: s,
    setCount: sets.length,
    totalVolumeKg: tonnage,
    durationMin: s.duration.inMinutes,
  );
});
