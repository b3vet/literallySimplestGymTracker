import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../../programs/application/programs_provider.dart';
import '../application/active_workout_controller.dart';
import '../application/pr_detector.dart';
import '../data/workout_dao.dart';
import '../domain/workout_session.dart';
import '../domain/workout_set.dart';

final _sessionSummaryProvider =
    FutureProvider.family<_SummaryData?, String>((ref, id) async {
  final dao = ref.watch(workoutDaoProvider);
  final session = await dao.findSession(id);
  if (session == null) return null;
  final sets = await dao.setsForSession(id);

  // Resolve exercise names.
  final exerciseIds = sets.map((s) => s.exerciseId).toSet();
  final programDao = ref.watch(programDaoProvider);
  final nameById = <String, String>{};
  for (final id in exerciseIds) {
    final e = await programDao.findExercise(id);
    if (e != null) nameById[id] = e.name;
  }

  // Comparison vs previous session of the same program day, if any.
  Map<String, List<WorkoutSet>>? prevByExercise;
  if (session.programDayId != null) {
    final prev = await dao.previousCompletedSessionForDay(
      session.programDayId!,
      before: session.startedAt,
    );
    if (prev != null) {
      final prevSets = await dao.setsForSession(prev.id);
      prevByExercise = <String, List<WorkoutSet>>{};
      for (final s in prevSets) {
        prevByExercise.putIfAbsent(s.exerciseId, () => []).add(s);
      }
    }
  }

  return _SummaryData(
    session: session,
    sets: sets,
    exerciseNames: nameById,
    prevByExercise: prevByExercise,
  );
});

final _tonnageTrendProvider = FutureProvider<List<TonnagePoint>>((ref) async {
  final dao = ref.watch(workoutDaoProvider);
  final pts = await dao.totalTonnageBySession(limit: 8);
  // Most recent first → reverse to chronological order for the chart.
  return pts.reversed.toList();
});

class _SummaryData {
  _SummaryData({
    required this.session,
    required this.sets,
    required this.exerciseNames,
    required this.prevByExercise,
  });
  final WorkoutSession session;
  final List<WorkoutSet> sets;
  final Map<String, String> exerciseNames;
  final Map<String, List<WorkoutSet>>? prevByExercise;
}

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_sessionSummaryProvider(sessionId));
    final prs = ref.watch(sessionPrsProvider(sessionId));
    final trend = ref.watch(_tonnageTrendProvider);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout complete'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Done'),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (d) {
          if (d == null) {
            return const Center(child: Text('Workout not found.'));
          }
          final byExercise = <String, List<WorkoutSet>>{};
          for (final s in d.sets) {
            byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
          }
          final totalVolumeKg = d.sets
              .fold<double>(0, (t, s) => t + s.weightKg * s.reps);
          final setCount = d.sets.length;
          final durationStr = _formatDuration(d.session.duration);

          final trendPts = trend.maybeWhen(
            data: (v) => v,
            orElse: () => const <TonnagePoint>[],
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatRow(
                children: [
                  _Stat('Duration', durationStr),
                  _Stat('Sets', '$setCount'),
                  _Stat('Volume', WeightConv.format(totalVolumeKg, unit)),
                ],
              ),
              const SizedBox(height: 16),
              if (trendPts.length >= 2) ...[
                _TrendCard(points: trendPts, currentSessionId: sessionId, unit: unit),
                const SizedBox(height: 16),
              ],
              for (final entry in byExercise.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExerciseCard(
                    name: d.exerciseNames[entry.key] ?? 'Exercise',
                    sets: entry.value,
                    prevSets: d.prevByExercise?[entry.key],
                    isFirstSession: d.prevByExercise == null,
                    unit: unit,
                    pr: prs.value?[entry.key],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final c in children) Expanded(child: c),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.points,
    required this.currentSessionId,
    required this.unit,
  });
  final List<TonnagePoint> points;
  final String currentSessionId;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].tonnageKg),
    ];
    final last = points.last;
    final prev = points.length >= 2 ? points[points.length - 2] : null;
    final delta = prev == null ? null : last.tonnageKg - prev.tonnageKg;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Volume trend',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (delta != null)
                Text(
                  '${delta >= 0 ? '+' : ''}${WeightConv.format(delta, unit)}',
                  style: TextStyle(
                    color: delta >= 0 ? AppColors.success : AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'last ${points.length} sessions',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    barWidth: 2,
                    color: AppColors.primary,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, _, _) {
                        final isCurrent = spot.x.toInt() == points.length - 1;
                        return FlDotCirclePainter(
                          radius: isCurrent ? 4.5 : 2.5,
                          color: isCurrent
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.10),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.name,
    required this.sets,
    required this.prevSets,
    required this.isFirstSession,
    required this.unit,
    this.pr,
  });
  final String name;
  final List<WorkoutSet> sets;
  final List<WorkoutSet>? prevSets;
  final bool isFirstSession;
  final WeightUnit unit;
  final ExercisePR? pr;

  @override
  Widget build(BuildContext context) {
    final topWeight =
        sets.fold<double>(0, (m, s) => s.weightKg > m ? s.weightKg : m);
    final topRepsAtTop = sets
        .where((s) => s.weightKg >= topWeight - 1e-6)
        .fold<int>(0, (m, s) => s.reps > m ? s.reps : m);

    final prevTopWeight = prevSets == null || prevSets!.isEmpty
        ? null
        : prevSets!.fold<double>(
            0, (m, s) => s.weightKg > m ? s.weightKg : m);
    final prevTopReps = prevSets == null || prevSets!.isEmpty || prevTopWeight == null
        ? null
        : prevSets!
            .where((s) => s.weightKg >= prevTopWeight - 1e-6)
            .fold<int>(0, (m, s) => s.reps > m ? s.reps : m);

    String comparisonLabel;
    Color comparisonColor = AppColors.textSecondary;
    if (isFirstSession) {
      comparisonLabel = 'No prior sessions of this day';
    } else if (prevTopWeight == null) {
      comparisonLabel = 'New on this day';
    } else {
      final dWeight = topWeight - prevTopWeight;
      final dReps = (prevTopReps == null) ? 0 : topRepsAtTop - prevTopReps;
      if (dWeight.abs() < 1e-6 && dReps == 0) {
        comparisonLabel = 'Matched last session';
      } else if (dWeight > 0 || (dWeight.abs() < 1e-6 && dReps > 0)) {
        final w = dWeight.abs() < 1e-6
            ? '+$dReps reps'
            : '+${WeightConv.format(dWeight, unit)}';
        comparisonLabel = '$w vs last';
        comparisonColor = AppColors.success;
      } else {
        final w = dWeight.abs() < 1e-6
            ? '$dReps reps'
            : '${dWeight > 0 ? '+' : ''}${WeightConv.format(dWeight, unit)}';
        comparisonLabel = '$w vs last';
        comparisonColor = AppColors.danger;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              if (pr != null && pr!.isPr) _PrBadge(pr: pr!),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${sets.length} sets · top ${WeightConv.format(topWeight, unit)} × $topRepsAtTop',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
              Text(
                comparisonLabel,
                style: TextStyle(
                  color: comparisonColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < sets.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                      width: 48,
                      child: Text('Set ${i + 1}',
                          style: Theme.of(context).textTheme.bodyLarge)),
                  Expanded(
                    child: Text(
                      '${WeightConv.format(sets[i].weightKg, unit)}  ×  ${sets[i].reps}  ·  RIR ${sets[i].rir}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

class _PrBadge extends StatelessWidget {
  const _PrBadge({required this.pr});
  final ExercisePR pr;
  @override
  Widget build(BuildContext context) {
    final label = pr.kind == PrKind.weight ? 'WEIGHT PR' : 'REP PR';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 14, color: AppColors.success),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                color: AppColors.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              )),
        ],
      ),
    );
  }
}
