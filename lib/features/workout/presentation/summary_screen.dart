import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
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

  final exerciseIds = sets.map((s) => s.exerciseId).toSet();
  final programDao = ref.watch(programDaoProvider);
  final nameById = <String, String>{};
  for (final id in exerciseIds) {
    final e = await programDao.findExercise(id);
    if (e != null) nameById[id] = e.name;
  }

  String? dayName;
  String? programName;
  if (session.programDayId != null) {
    final d = await programDao.findDay(session.programDayId!);
    dayName = d?.name;
    if (d != null) {
      final p = await programDao.findProgram(d.programId);
      programName = p?.name;
    }
  }

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
    dayName: dayName,
    programName: programName,
  );
});

final _tonnageTrendProvider = FutureProvider<List<TonnagePoint>>((ref) async {
  final dao = ref.watch(workoutDaoProvider);
  final pts = await dao.totalTonnageBySession(limit: 8);
  return pts.reversed.toList();
});

class _SummaryData {
  _SummaryData({
    required this.session,
    required this.sets,
    required this.exerciseNames,
    required this.prevByExercise,
    required this.dayName,
    required this.programName,
  });
  final WorkoutSession session;
  final List<WorkoutSet> sets;
  final Map<String, String> exerciseNames;
  final Map<String, List<WorkoutSet>>? prevByExercise;
  final String? dayName;
  final String? programName;
}

class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final data = ref.watch(_sessionSummaryProvider(sessionId));
    final prs = ref.watch(sessionPrsProvider(sessionId));
    final trend = ref.watch(_tonnageTrendProvider);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    return data.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Failed to load: $e'))),
      data: (d) {
        if (d == null) {
          return Scaffold(
            body: Center(
              child: Text('Workout not found.',
                  style: LsType.bodyM.copyWith(color: t.surface.text2)),
            ),
          );
        }
        // Topbar title = workout (program) name, falling back to "Complete"
        // when the session was attached to an orphaned day.
        final headerTitle = d.programName ?? 'Complete';
        final heroDay = (d.dayName ?? 'Workout').toUpperCase();

        final byExercise = <String, List<WorkoutSet>>{};
        for (final s in d.sets) {
          byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
        }
        final totalVolumeKg =
            d.sets.fold<double>(0, (t, s) => t + s.weightKg * s.reps);
        final setCount = d.sets.length;
        final durationStr = _formatDuration(d.session.duration);
        final trendPts = trend.maybeWhen(
          data: (v) => v,
          orElse: () => const <TonnagePoint>[],
        );

        return LsScreen(
          topGap: LsGap.loose,
          topbar: LsTopbar(
            title: headerTitle,
            showBack: false,
            trailing: LsIconSquare(
              icon: Icons.check,
              onTap: () => context.go('/'),
              semanticLabel: 'Done',
            ),
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // WORKOUT SUMMARY eyebrow above the hero — page content, not header.
              Align(
                alignment: Alignment.centerRight,
                child: EyebrowLabel('WORKOUT SUMMARY'),
              ),
              const SizedBox(height: LsGap.sub),
              // Hero day name — same scale as the home screen's "TRAIN HEAVY."
              Text(
                heroDay,
                style: LsType.displayHome.copyWith(
                  color: t.surface.text,
                  fontSize: 64,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: LsGap.loose),
              // Right-aligned pill row of bold-number / regular-label stats.
              _StatPillsRow(
                items: [
                  _StatPillData(value: durationStr, label: 'DURATION'),
                  _StatPillData(value: '$setCount', label: 'SETS'),
                  _StatPillData(
                    value: WeightConv.format(totalVolumeKg, unit)
                        .replaceAll(unit.short.toUpperCase(), '')
                        .replaceAll(unit.short, '')
                        .trim(),
                    label: 'VOLUME ${unit.short.toUpperCase()}',
                  ),
                ],
              ),
              const SizedBox(height: LsGap.loose),
              if (trendPts.length >= 2) ...[
                _TrendCard(
                    points: trendPts,
                    currentSessionId: sessionId,
                    unit: unit),
                const SizedBox(height: LsGap.section),
              ],
              for (final entry in byExercise.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: LsGap.sub),
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
          ),
        );
      },
    );
  }
}

class _StatPillData {
  const _StatPillData({required this.value, required this.label});
  final String value;
  final String label;
}

/// Right-aligned row of stat pills: each pill stacks a BOLD mono numeral on
/// top of a regular monoMicro label. Used at the top of the summary screen.
class _StatPillsRow extends StatelessWidget {
  const _StatPillsRow({required this.items});
  final List<_StatPillData> items;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: LsGap.sub),
          _StatPill(data: items[i]),
        ],
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.data});
  final _StatPillData data;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface.surface,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        border: Border.all(color: t.surface.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Bold number (mono numeral) — large, w700.
          Text(
            data.value.toUpperCase(),
            style: LsType.monoNumeral.copyWith(
              color: t.surface.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          // Regular meta label.
          Text(
            data.label,
            style: LsType.monoMicro.copyWith(color: t.surface.text2),
          ),
        ],
      ),
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
    final t = LsTheme.of(context);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].tonnageKg),
    ];
    final last = points.last;
    final prev = points.length >= 2 ? points[points.length - 2] : null;
    final delta = prev == null ? null : last.tonnageKg - prev.tonnageKg;

    return LsCard(
      padding: LsPad.cardSpacious,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EyebrowLabel('VOLUME TREND')),
              if (delta != null)
                Text(
                  '${delta >= 0 ? '+' : ''}'
                  '${WeightConv.format(delta, unit).toUpperCase()}',
                  style: LsType.monoMeta.copyWith(
                    color: delta >= 0 ? t.accent.accent : LsSignals.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'LAST ${points.length} SESSIONS',
            style: LsType.monoMicro.copyWith(color: t.surface.text3),
          ),
          const SizedBox(height: 12),
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
                    color: t.accent.accent,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, _, _) {
                        final isCurrent = spot.x.toInt() == points.length - 1;
                        return FlDotCirclePainter(
                          radius: isCurrent ? 4.5 : 2.5,
                          color: isCurrent
                              ? t.accent.accent
                              : t.surface.text3,
                          strokeWidth: 0,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: t.accent.accent.withValues(alpha: 0.16),
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
    final t = LsTheme.of(context);
    final topWeight =
        sets.fold<double>(0, (m, s) => s.weightKg > m ? s.weightKg : m);
    final topRepsAtTop = sets
        .where((s) => s.weightKg >= topWeight - 1e-6)
        .fold<int>(0, (m, s) => s.reps > m ? s.reps : m);

    final prevTopWeight = prevSets == null || prevSets!.isEmpty
        ? null
        : prevSets!
            .fold<double>(0, (m, s) => s.weightKg > m ? s.weightKg : m);
    final prevTopReps =
        prevSets == null || prevSets!.isEmpty || prevTopWeight == null
            ? null
            : prevSets!
                .where((s) => s.weightKg >= prevTopWeight - 1e-6)
                .fold<int>(0, (m, s) => s.reps > m ? s.reps : m);

    String comparisonLabel;
    Color comparisonColor = t.surface.text2;
    if (isFirstSession) {
      comparisonLabel = 'FIRST TIME ON THIS DAY';
    } else if (prevTopWeight == null) {
      comparisonLabel = 'NEW ON THIS DAY';
    } else {
      final dWeight = topWeight - prevTopWeight;
      final dReps = (prevTopReps == null) ? 0 : topRepsAtTop - prevTopReps;
      if (dWeight.abs() < 1e-6 && dReps == 0) {
        comparisonLabel = 'MATCHED LAST';
      } else if (dWeight > 0 || (dWeight.abs() < 1e-6 && dReps > 0)) {
        final w = dWeight.abs() < 1e-6
            ? '+$dReps REPS'
            : '+${WeightConv.format(dWeight, unit).toUpperCase()}';
        comparisonLabel = '$w VS LAST';
        comparisonColor = t.accent.accent;
      } else {
        final w = dWeight.abs() < 1e-6
            ? '$dReps REPS'
            : '${dWeight > 0 ? '+' : ''}'
                '${WeightConv.format(dWeight, unit).toUpperCase()}';
        comparisonLabel = '$w VS LAST';
        comparisonColor = LsSignals.danger;
      }
    }

    return LsCard(
      padding: LsPad.cardSpacious,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 28,
                  ),
                ),
              ),
              if (pr != null && pr!.isPr) _PrBadge(pr: pr!),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${sets.length} SETS · TOP '
                  '${WeightConv.format(topWeight, unit).toUpperCase()} × $topRepsAtTop',
                  style: LsType.monoMeta.copyWith(color: t.surface.text2),
                ),
              ),
              Text(
                comparisonLabel,
                style: LsType.monoMeta.copyWith(color: comparisonColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < sets.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      'SET ${i + 1}',
                      style: LsType.monoMeta.copyWith(color: t.surface.text2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${WeightConv.format(sets[i].weightKg, unit).toUpperCase()}  ×  '
                      '${sets[i].reps}  ·  RIR ${sets[i].rir}',
                      style: LsType.monoData
                          .copyWith(color: t.surface.text, fontSize: 18),
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
        color: LsSignals.pr.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(LsRadius.r2),
        border: Border.all(color: LsSignals.pr),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 12, color: LsSignals.pr),
          const SizedBox(width: 4),
          Text(label,
              style: LsType.monoMicro.copyWith(color: LsSignals.pr)),
        ],
      ),
    );
  }
}
