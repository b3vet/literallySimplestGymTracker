import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../../programs/domain/exercise.dart';
import '../application/stats_provider.dart';

enum StatsMetric { topWeight, volume, oneRm }

extension on StatsMetric {
  String get label => switch (this) {
        StatsMetric.topWeight => 'Top set',
        StatsMetric.volume => 'Volume',
        StatsMetric.oneRm => 'Est 1RM',
      };
  double Function(ExerciseProgressionPoint) get accessor => switch (this) {
        StatsMetric.topWeight => (p) => p.topWeightKg,
        StatsMetric.volume => (p) => p.totalVolumeKg,
        StatsMetric.oneRm => (p) => p.est1RMKg,
      };
}

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Exercise? _selected;
  StatsMetric _metric = StatsMetric.topWeight;

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(loggedExercisesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: exercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) return const _Empty();
          _selected ??= list.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ExerciseSelector(
                exercises: list,
                selected: _selected!,
                onSelect: (e) => setState(() => _selected = e),
              ),
              const SizedBox(height: 16),
              _MetricToggle(
                metric: _metric,
                onChange: (m) => setState(() => _metric = m),
              ),
              const SizedBox(height: 16),
              _ExerciseChartCard(exerciseId: _selected!.id, metric: _metric),
            ],
          );
        },
      ),
    );
  }
}

class _ExerciseSelector extends StatelessWidget {
  const _ExerciseSelector({
    required this.exercises,
    required this.selected,
    required this.onSelect,
  });
  final List<Exercise> exercises;
  final Exercise selected;
  final ValueChanged<Exercise> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showModalBottomSheet<Exercise>(
            context: context,
            backgroundColor: AppColors.elevated,
            builder: (ctx) => SafeArea(
              top: false,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: exercises.length,
                itemBuilder: (c, i) {
                  final e = exercises[i];
                  return ListTile(
                    tileColor: AppColors.elevated,
                    title: Text(e.name),
                    trailing: e.id == selected.id
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, e),
                  );
                },
              ),
            ),
          );
          if (picked != null) onSelect(picked);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EXERCISE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            )),
                    const SizedBox(height: 4),
                    Text(selected.name,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricToggle extends StatelessWidget {
  const _MetricToggle({required this.metric, required this.onChange});
  final StatsMetric metric;
  final ValueChanged<StatsMetric> onChange;
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StatsMetric>(
      segments: [
        for (final m in StatsMetric.values)
          ButtonSegment(value: m, label: Text(m.label)),
      ],
      selected: {metric},
      onSelectionChanged: (s) => onChange(s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.divider),
      ),
    );
  }
}

class _ExerciseChartCard extends ConsumerWidget {
  const _ExerciseChartCard({required this.exerciseId, required this.metric});
  final String exerciseId;
  final StatsMetric metric;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(exerciseProgressionProvider(exerciseId));
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;

    return data.when(
      loading: () => const SizedBox(
          height: 280, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed: $e'),
      ),
      data: (p) {
        if (p.points.length < 2) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Log at least 2 sessions of this exercise to see progression.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          );
        }
        final get = metric.accessor;
        final spots = <FlSpot>[];
        for (var i = 0; i < p.points.length; i++) {
          spots.add(FlSpot(i.toDouble(), get(p.points[i])));
        }
        final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
        final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
        final padY = ((maxY - minY) * 0.1).clamp(1.0, double.infinity);

        final current = get(p.points.last);
        final best = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
        final delta = trendDelta(p.points, get);

        final valueLabel = switch (metric) {
          StatsMetric.topWeight => WeightConv.format(current, unit),
          StatsMetric.volume => WeightConv.format(current, unit),
          StatsMetric.oneRm => WeightConv.format(current, unit),
        };

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.label.toUpperCase(),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    )),
                        const SizedBox(height: 4),
                        Text(valueLabel,
                            style: Theme.of(context).textTheme.headlineLarge),
                      ],
                    ),
                  ),
                  _DeltaPill(deltaKg: delta, unit: unit),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minY: (minY - padY).clamp(0, double.infinity),
                    maxY: maxY + padY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: AppColors.divider,
                        strokeWidth: 1,
                        dashArray: [4, 6],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: (p.points.length / 4).ceilToDouble().clamp(1, double.infinity),
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= p.points.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              DateFormat('d/M').format(p.points[i].date),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(0),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.25,
                        barWidth: 3,
                        color: AppColors.primary,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                            radius: 3,
                            color: AppColors.primary,
                            strokeWidth: 0,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.primary.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Best ${WeightConv.format(best, unit)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.deltaKg, required this.unit});
  final double deltaKg;
  final WeightUnit unit;
  @override
  Widget build(BuildContext context) {
    final positive = deltaKg > 0;
    final neutral = deltaKg == 0;
    final color = neutral
        ? AppColors.textSecondary
        : (positive ? AppColors.success : AppColors.danger);
    final sign = positive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$sign${WeightConv.format(deltaKg.abs(), unit)} · 30d',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart,
                size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text('No stats yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Log at least 2 sessions of an exercise to see progress.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
