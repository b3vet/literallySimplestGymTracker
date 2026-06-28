import 'package:flutter/material.dart';

import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../domain/workout_summary.dart';
import '../application/summary_text.dart'
    show summaryDateShort, summaryDurationShort, summaryTonnageGrouped;

/// The branded, shareable workout-summary card. Always dark (it's an outbound
/// image, not in-app chrome) with the user's [accent]. Fixed at [cardWidth] ×
/// [cardHeight] logical px — rendered off-screen and captured at pixelRatio 3
/// (see `summary_card_renderer.dart`).
///
/// It is wrapped in a [RepaintBoundary] keyed by [boundaryKey] so the renderer
/// can snapshot exactly this subtree. Visible exercise lines are capped
/// ([maxVisibleLines]) with a "+k more" tail so a long session never overflows.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    required this.unit,
    required this.accent,
    required this.boundaryKey,
  });

  static const double cardWidth = 1080;
  static const double cardHeight = 1350;

  /// Max exercise rows drawn before collapsing the tail into "+k more". Sized so
  /// the worst case — every visible row carrying a PR badge plus the "+k more"
  /// line — still fits the fixed [Expanded] budget at the production
  /// [cardWidth] × [cardHeight] without clipping.
  static const int maxVisibleLines = 9;

  final WorkoutSummary summary;
  final WeightUnit unit;
  final LsAccentSpec accent;
  final GlobalKey boundaryKey;

  @override
  Widget build(BuildContext context) {
    const s = lsDark;
    final visible = summary.lines.take(maxVisibleLines).toList();
    final overflowCount = summary.lines.length - visible.length;

    return RepaintBoundary(
      key: boundaryKey,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Material(
          color: s.bg,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 72, 72, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(summary: summary, accent: accent),
                const SizedBox(height: 48),
                _StatsRow(summary: summary, unit: unit, accent: accent),
                const SizedBox(height: 36),
                _Divider(color: s.border),
                const SizedBox(height: 36),
                Expanded(
                  child: _ExerciseList(
                    lines: visible,
                    overflowCount: overflowCount,
                    unit: unit,
                    accent: accent,
                  ),
                ),
                const SizedBox(height: 24),
                _Divider(color: s.border),
                const SizedBox(height: 28),
                _Footer(accent: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.accent});
  final WorkoutSummary summary;
  final LsAccentSpec accent;

  @override
  Widget build(BuildContext context) {
    const s = lsDark;
    final day = (summary.dayName ?? summary.programName ?? 'Workout');
    final program = summary.programName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LS monogram tile.
        Container(
          width: 96,
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.accent,
            borderRadius: BorderRadius.circular(LsRadius.r3),
          ),
          child: Text(
            'LS',
            style: TextStyle(
              fontFamily: 'Antonio',
              fontWeight: FontWeight.w700,
              fontSize: 52,
              height: 1.0,
              letterSpacing: 0.6,
              color: accent.accentInk,
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (program != null) ...[
                Text(
                  program.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LsType.monoMeta.copyWith(
                    color: s.text2,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                day.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LsType.displayM.copyWith(
                  color: s.text,
                  fontSize: 76,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // The date is a single short token, but scaleDown guards against an
        // unexpectedly wide locale rendering pushing the row past the edge.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            summaryDateShort(summary.date).toUpperCase(),
            maxLines: 1,
            style: LsType.monoMeta.copyWith(color: s.text2, fontSize: 28),
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.summary,
    required this.unit,
    required this.accent,
  });
  final WorkoutSummary summary;
  final WeightUnit unit;
  final LsAccentSpec accent;

  @override
  Widget build(BuildContext context) {
    final tonnage =
        summaryTonnageGrouped(WeightConv.fromKg(summary.tonnageKg, unit));
    // Each stat is Flexible so a very large tonnage (e.g. "1,234,567") can
    // shrink (via the per-stat FittedBox) instead of overflowing the row to the
    // right. The PR stat sits hard against the trailing edge.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: _Stat(value: tonnage, label: unit.short.toUpperCase()),
        ),
        const SizedBox(width: 56),
        Flexible(
          child: _Stat(
            value: '${summary.exerciseCount}',
            label: summary.exerciseCount == 1 ? 'LIFT' : 'LIFTS',
          ),
        ),
        const SizedBox(width: 56),
        Flexible(
          child: _Stat(
            value: summaryDurationShort(summary.duration),
            label: 'TIME',
          ),
        ),
        if (summary.prCount > 0) ...[
          const SizedBox(width: 56),
          Flexible(
            child: _Stat(
              value: '${summary.prCount}',
              label: summary.prCount == 1 ? 'PR' : 'PRS',
              accentColor: accent.accent,
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.accentColor,
  });
  final String value;
  final String label;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    const s = lsDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // scaleDown lets the big numeral shrink to fit the stat's Flexible slot
        // (a 7-figure tonnage) instead of overflowing the row.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: LsType.monoNumeral.copyWith(
              color: accentColor ?? s.text,
              fontSize: 72,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LsType.monoMicro.copyWith(
            color: accentColor != null
                ? accentColor!.withValues(alpha: 0.9)
                : s.text2,
            fontSize: 24,
          ),
        ),
      ],
    );
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList({
    required this.lines,
    required this.overflowCount,
    required this.unit,
    required this.accent,
  });
  final List<TopSetLine> lines;
  final int overflowCount;
  final WeightUnit unit;
  final LsAccentSpec accent;

  @override
  Widget build(BuildContext context) {
    const s = lsDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: _ExerciseRow(line: line, unit: unit, accent: accent),
          ),
        if (overflowCount > 0)
          Text(
            '+$overflowCount MORE',
            style: LsType.monoMeta.copyWith(color: s.text3, fontSize: 28),
          ),
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.line,
    required this.unit,
    required this.accent,
  });
  final TopSetLine line;
  final WeightUnit unit;
  final LsAccentSpec accent;

  @override
  Widget build(BuildContext context) {
    const s = lsDark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            line.exercise.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LsType.displayS.copyWith(color: s.text, fontSize: 40),
          ),
        ),
        const SizedBox(width: 20),
        // scaleDown so a heavy set value (e.g. "2,205 LB × 12") can't push the
        // PR badge past the card edge.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '${WeightConv.format(line.weightKg, unit).toUpperCase()} × ${line.reps}',
              maxLines: 1,
              style: LsType.monoData.copyWith(color: s.text, fontSize: 40),
            ),
          ),
        ),
        if (line.isPr) ...[
          const SizedBox(width: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accent.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(LsRadius.r2),
              border: Border.all(color: accent.accent),
            ),
            child: Text(
              'PR',
              style: LsType.monoMeta.copyWith(
                color: accent.accent,
                fontSize: 26,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.accent});
  final LsAccentSpec accent;

  @override
  Widget build(BuildContext context) {
    const s = lsDark;
    return Row(
      children: [
        Container(width: 28, height: 4, color: accent.accent),
        const SizedBox(width: 16),
        Text(
          'LOGGED WITH LS GYM TRACK',
          style: LsType.monoMeta.copyWith(color: s.text2, fontSize: 28),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(height: 2, color: color);
}
