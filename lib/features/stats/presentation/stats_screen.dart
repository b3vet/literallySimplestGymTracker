import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../../programs/domain/exercise.dart';
import '../application/stats_provider.dart';

enum StatsMetric { topSet, volume, est1rm }

extension on StatsMetric {
  String get label => switch (this) {
    StatsMetric.topSet => 'TOP SET',
    StatsMetric.volume => 'VOLUME',
    StatsMetric.est1rm => 'EST 1RM',
  };
  double Function(ExerciseProgressionPoint) get accessor => switch (this) {
    StatsMetric.topSet => (p) => p.topWeightKg,
    StatsMetric.volume => (p) => p.totalVolumeKg,
    StatsMetric.est1rm => (p) => p.est1RMKg,
  };
}

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Exercise? _selected;
  StatsMetric _metric = StatsMetric.topSet;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final exercises = ref.watch(loggedExercisesProvider);
    return LsScreen(
      topGap: LsGap.loose,
      topbar: const LsTopbar(title: 'Stats'),
      child: exercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NO STATS YET',
                      style: LsType.displayM.copyWith(color: t.surface.text),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Log at least 2 sessions of an exercise to see progress.',
                      textAlign: TextAlign.center,
                      style: LsType.bodyM.copyWith(color: t.surface.text2),
                    ),
                  ],
                ),
              ),
            );
          }
          _selected ??= list.first;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _ExerciseSelector(
                exercises: list,
                selected: _selected!,
                onSelect: (e) => setState(() => _selected = e),
              ),
              const SizedBox(height: LsGap.section),
              _MetricSegmented(
                metric: _metric,
                onChange: (m) => setState(() => _metric = m),
              ),
              const SizedBox(height: LsGap.section),
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
    final t = LsTheme.of(context);
    return LsCard(
      padding: LsPad.cardSpacious,
      onTap: () async {
        final picked = await showModalBottomSheet<Exercise>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => LsSheet(
            child: _ChooseExerciseSheetBody(
              exercises: exercises,
              selectedId: selected.id,
            ),
          ),
        );
        if (picked != null) onSelect(picked);
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EyebrowLabel('EXERCISE'),
                const SizedBox(height: LsGap.sub),
                Text(
                  selected.name.toUpperCase(),
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 32,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.unfold_more, color: t.surface.text2, size: 22),
        ],
      ),
    );
  }
}

/// Custom "CHOOSE EXERCISE" bottom sheet — matches design screenshot 13:
/// drag handle (provided by LsSheet), eyebrow header, hairline dividers
/// between rows, Antonio display font for exercise names, accent checkmark
/// on the selected row.
class _ChooseExerciseSheetBody extends StatelessWidget {
  const _ChooseExerciseSheetBody({
    required this.exercises,
    required this.selectedId,
  });
  final List<Exercise> exercises;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: LsGap.sub),
            child: EyebrowLabel('CHOOSE EXERCISE'),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: exercises.length,
              separatorBuilder: (_, _) =>
                  Container(height: 1, color: t.surface.border),
              itemBuilder: (ctx, i) {
                final e = exercises[i];
                final isSelected = e.id == selectedId;
                return InkWell(
                  onTap: () => Navigator.pop(ctx, e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LsType.displayM.copyWith(
                              color: isSelected
                                  ? t.surface.text
                                  : t.surface.text2,
                              fontSize: 26,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check, size: 22, color: t.accent.accent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricSegmented extends StatelessWidget {
  const _MetricSegmented({required this.metric, required this.onChange});
  final StatsMetric metric;
  final ValueChanged<StatsMetric> onChange;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface.surface2,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        border: Border.all(color: t.surface.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final m in StatsMetric.values)
            Expanded(
              child: _SegmentButton(
                label: m.label,
                selected: m == metric,
                onTap: () => onChange(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: selected ? t.accent.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(LsRadius.r3 - 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3 - 4),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: t.accent.accentInk),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: LsType.button.copyWith(
                  color: selected ? t.accent.accentInk : t.surface.text2,
                ),
              ),
            ],
          ),
        ),
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
    final t = LsTheme.of(context);
    final data = ref.watch(exerciseProgressionProvider(exerciseId));
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;

    return data.when(
      loading: () => const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Failed: $e',
          style: LsType.bodyM.copyWith(color: t.surface.text2),
        ),
      ),
      data: (p) {
        if (p.points.length < 2) {
          return LsCard(
            padding: LsPad.cardSpacious,
            child: Text(
              'INSUFFICIENT DATA — LOG AT LEAST 2 SESSIONS',
              style: LsType.monoMicro.copyWith(color: t.surface.text3),
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

        return LsCard(
          padding: const EdgeInsets.all(LsSpace.cardHero),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: EyebrowLabel(metric.label)),
                  _DeltaPill(deltaKg: delta, unit: unit),
                ],
              ),
              const SizedBox(height: 12),
              // Big hero value — split between value & unit (mono numeral
              // colored accent, mono meta unit muted).
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _heroValue(current, unit, metric),
                    style: LsType.displayHero.copyWith(
                      color: t.accent.accent,
                      fontSize: 56,
                      height: 0.9,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      unit.short.toUpperCase(),
                      style: LsType.monoMeta.copyWith(color: t.surface.text2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    minY: (minY - padY).clamp(0, double.infinity),
                    maxY: maxY + padY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: t.surface.border,
                        strokeWidth: 1,
                        dashArray: const [4, 6],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: (p.points.length / 4).ceilToDouble().clamp(
                            1,
                            double.infinity,
                          ),
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= p.points.length) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              DateFormat('M/d').format(p.points[i].date),
                              style: LsType.monoMicro.copyWith(
                                color: t.surface.text3,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.2,
                        barWidth: 2,
                        color: t.accent.accent,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, _, _, _) {
                            final isLast =
                                spot.x.toInt() == p.points.length - 1;
                            return FlDotCirclePainter(
                              radius: isLast ? 5 : 2.5,
                              color: t.accent.accent,
                              strokeWidth: isLast ? 2 : 0,
                              strokeColor: t.surface.bg,
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
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.surface.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'BEST',
                        style: LsType.monoMeta.copyWith(
                          color: t.surface.text2,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${WeightConv.format(best, unit).toUpperCase()} · '
                      '${DateFormat('MMM d').format(_bestDate(p.points, get)).toUpperCase()}',
                      style: LsType.monoMeta.copyWith(
                        color: t.accent.accent,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static DateTime _bestDate(
    List<ExerciseProgressionPoint> pts,
    double Function(ExerciseProgressionPoint) get,
  ) {
    var best = pts.first;
    for (final p in pts) {
      if (get(p) > get(best)) best = p;
    }
    return best.date;
  }

  static String _heroValue(double value, WeightUnit unit, StatsMetric metric) {
    // strip unit suffix from end (e.g. "10 kg" → "10")
    final s = WeightConv.format(value, unit);
    final pattern = RegExp('\\s*${unit.short}\$', caseSensitive: false);
    return s.replaceAll(pattern, '');
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.deltaKg, required this.unit});
  final double deltaKg;
  final WeightUnit unit;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final positive = deltaKg > 0;
    final neutral = deltaKg == 0;
    final color = neutral
        ? t.surface.text2
        : (positive ? t.accent.accent : LsSignals.danger);
    final sign = positive ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface.surface2,
        borderRadius: BorderRadius.circular(LsRadius.r2),
        border: Border.all(color: t.surface.border),
      ),
      child: Text(
        '$sign${WeightConv.format(deltaKg.abs(), unit).toUpperCase()} · 30D',
        style: LsType.monoMeta.copyWith(color: color),
      ),
    );
  }
}
