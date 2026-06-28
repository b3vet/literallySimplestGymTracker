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
import '../../programs/domain/program_exercise.dart';
import '../../share/domain/workout_summary.dart';
import '../../share/presentation/share_summary_button.dart';
import '../application/active_workout_controller.dart';
import '../application/pr_detector.dart';
import '../data/workout_dao.dart';
import '../domain/active_session.dart';
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
  // Current program targets for this day, keyed by exerciseId, so each summary
  // card knows whether the exercise is in the plan and its current target
  // weight (drives "raise target" vs "add to day").
  final planByExercise = <String, ProgramExercise>{};
  if (session.programDayId != null) {
    final d = await programDao.findDay(session.programDayId!);
    dayName = d?.name;
    if (d != null) {
      final p = await programDao.findProgram(d.programId);
      programName = p?.name;
    }
    for (final v in await programDao.listProgramExercises(session.programDayId!)) {
      planByExercise[v.pe.exerciseId] = v.pe;
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
    planByExercise: planByExercise,
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
    required this.planByExercise,
  });
  final WorkoutSession session;
  final List<WorkoutSet> sets;
  final Map<String, String> exerciseNames;
  final Map<String, List<WorkoutSet>>? prevByExercise;
  final String? dayName;
  final String? programName;

  /// Current program targets for this session's day, keyed by exerciseId.
  /// Absent key => the exercise isn't in the day's plan (substituted/inserted).
  final Map<String, ProgramExercise> planByExercise;
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

        // A headless snapshot of THIS session for outbound share (text + card).
        // Built from the data already loaded above — no extra DB reads. PRs may
        // still be resolving; an empty map just means "no PR markers yet".
        final summary = WorkoutSummary.fromSession(
          date: d.session.startedAt,
          duration: d.session.duration,
          sets: d.sets,
          exerciseNames: d.exerciseNames,
          prs: prs.value ?? const {},
          programName: d.programName,
          dayName: d.dayName,
        );

        return LsScreen(
          topGap: LsGap.loose,
          topbar: LsTopbar(
            title: headerTitle,
            showBack: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShareSummaryButton(summary: summary, unit: unit),
                const SizedBox(width: 10),
                LsIconSquare(
                  icon: Icons.check,
                  onTap: () => context.go('/'),
                  semanticLabel: 'Done',
                ),
              ],
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
                    exerciseId: entry.key,
                    sets: entry.value,
                    prevSets: d.prevByExercise?[entry.key],
                    isFirstSession: d.prevByExercise == null,
                    unit: unit,
                    pr: prs.value?[entry.key],
                    planPe: d.planByExercise[entry.key],
                    programDayId: d.session.programDayId,
                    dayName: d.dayName,
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
    required this.exerciseId,
    required this.sets,
    required this.prevSets,
    required this.isFirstSession,
    required this.unit,
    this.pr,
    this.planPe,
    this.programDayId,
    this.dayName,
  });
  final String name;
  final String exerciseId;
  final List<WorkoutSet> sets;
  final List<WorkoutSet>? prevSets;
  final bool isFirstSession;
  final WeightUnit unit;
  final ExercisePR? pr;

  /// The program template row for this exercise in the session's day, or null
  /// when it isn't in the plan (substituted/inserted).
  final ProgramExercise? planPe;
  final String? programDayId;
  final String? dayName;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    // Logical sets: a drop set's top+drops render as one grouped block.
    final setGroups = groupedSetsFor(sets, exerciseId);
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
                  '${setGroups.length} SETS · TOP '
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
          for (var g = 0; g < setGroups.length; g++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      'SET ${g + 1}',
                      style: LsType.monoMeta.copyWith(color: t.surface.text2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < setGroups[g].length; i++)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
                            child: Text(
                              '${i > 0 ? '↓ ' : ''}'
                              '${WeightConv.format(setGroups[g][i].weightKg, unit).toUpperCase()}  ×  '
                              '${setGroups[g][i].reps}'
                              '${i == 0 && setGroups[g][i].rir > 0 ? '  ·  RIR ${setGroups[g][i].rir}' : ''}',
                              style: LsType.monoData.copyWith(
                                color: i == 0
                                    ? t.surface.text
                                    : t.surface.text2,
                                fontSize: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _ProgramTargetButton(
            programDayId: programDayId,
            dayName: dayName,
            exerciseName: name,
            planPe: planPe,
            topWeightKg: topWeight,
            sets: sets,
            unit: unit,
            isWeightPr: pr != null && pr!.isPr && pr!.kind == PrKind.weight,
          ),
        ],
      ),
    );
  }
}

/// Per-exercise action on the summary that syncs the program template to what
/// the lifter actually did this session — so progression doesn't mean editing
/// the program by hand. Context-aware:
///   • in the plan AND today's top weight beats the current target → "RAISE
///     TARGET" (updates `default_weight` for that day's slot).
///   • not in the plan (substituted / inserted) → "ADD TO {DAY}" (creates a
///     new program exercise from this session's sets/reps/weight).
///   • otherwise → nothing.
/// Applies on one tap with a snackbar + UNDO; never asks first.
class _ProgramTargetButton extends ConsumerStatefulWidget {
  const _ProgramTargetButton({
    required this.programDayId,
    required this.dayName,
    required this.exerciseName,
    required this.planPe,
    required this.topWeightKg,
    required this.sets,
    required this.unit,
    required this.isWeightPr,
  });

  final String? programDayId;
  final String? dayName;
  final String exerciseName;
  final ProgramExercise? planPe;
  final double topWeightKg;
  final List<WorkoutSet> sets;
  final WeightUnit unit;

  /// True when this session set a WEIGHT PR for the exercise — surface the
  /// "set target" button even if today's top weight doesn't exceed the current
  /// (possibly aspirational) program target.
  final bool isWeightPr;

  @override
  ConsumerState<_ProgramTargetButton> createState() =>
      _ProgramTargetButtonState();
}

class _ProgramTargetButtonState extends ConsumerState<_ProgramTargetButton> {
  bool _applied = false;

  bool get _isAdd => widget.planPe == null;
  bool get _canRaise =>
      widget.planPe != null &&
      widget.topWeightKg > widget.planPe!.defaultWeightKg + 1e-6;

  /// Offer the in-plan "set target" button when today's top beats the target OR
  /// it's a weight PR (which the lifter expects to be able to lock in even if
  /// their planned target sits above it).
  bool get _showInPlan => !_isAdd && (_canRaise || widget.isWeightPr);

  @override
  Widget build(BuildContext context) {
    if (widget.programDayId == null) return const SizedBox.shrink();
    if (!_isAdd && !_showInPlan) return const SizedBox.shrink();

    final t = LsTheme.of(context);
    final accent = t.accent.accent;
    final fg = _applied ? t.surface.text3 : accent;
    final icon = _applied
        ? Icons.check
        : (_isAdd
            ? Icons.add
            : (_canRaise ? Icons.arrow_upward : Icons.star));
    final weightLabel =
        WeightConv.format(widget.topWeightKg, widget.unit).toUpperCase();
    final label = _applied
        ? (_isAdd ? 'ADDED' : 'TARGET SET')
        : (_isAdd
            ? 'ADD TO ${(widget.dayName ?? 'DAY').toUpperCase()}'
            : (_canRaise
                ? 'RAISE TARGET → $weightLabel'
                : 'SET TARGET → $weightLabel'));

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(LsRadius.r2),
          onTap: _applied ? null : _apply,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LsRadius.r2),
              border: Border.all(
                color: _applied ? t.surface.border : accent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 8),
                Text(label, style: LsType.monoMeta.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _apply() async {
    final dao = ref.read(programDaoProvider);
    if (_isAdd) {
      var repsMin = widget.sets.first.reps;
      var repsMax = widget.sets.first.reps;
      for (final s in widget.sets) {
        if (s.reps < repsMin) repsMin = s.reps;
        if (s.reps > repsMax) repsMax = s.reps;
      }
      final created = await dao.addProgramExercise(
        programDayId: widget.programDayId!,
        exerciseName: widget.exerciseName,
        targetSets: widget.sets.length,
        targetRepsMin: repsMin,
        targetRepsMax: repsMax,
        defaultWeightKg: widget.topWeightKg,
      );
      if (!mounted) return;
      _refreshDay();
      setState(() => _applied = true);
      _showUndo(
        'Added ${widget.exerciseName.toUpperCase()} to '
        '${(widget.dayName ?? 'day').toUpperCase()}',
        () => dao.deleteProgramExercise(created.id),
      );
    } else {
      final old = widget.planPe!;
      await dao.updateProgramExercise(
        old.copyWith(defaultWeightKg: widget.topWeightKg),
      );
      if (!mounted) return;
      _refreshDay();
      setState(() => _applied = true);
      _showUndo(
        '${widget.exerciseName.toUpperCase()} target → '
        '${WeightConv.format(widget.topWeightKg, widget.unit).toUpperCase()}',
        () => dao.updateProgramExercise(old),
      );
    }
  }

  /// Drop the cached day-exercise list so the program editor reflects the
  /// add/raise without an app restart.
  void _refreshDay() {
    final dayId = widget.programDayId;
    if (dayId != null) ref.invalidate(dayExercisesProvider(dayId));
  }

  void _showUndo(String message, Future<void> Function() undo) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            await undo();
            _refreshDay();
            if (mounted) setState(() => _applied = false);
          },
        ),
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
