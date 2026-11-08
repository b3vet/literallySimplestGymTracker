import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../../onboarding/presentation/onboarding_fx.dart' show reduceMotionOf;
import '../../programs/domain/program_exercise_variant.dart';
import '../../share/application/summary_text.dart' show summaryTonnageGrouped;
import '../../share/domain/workout_summary.dart';
import '../../share/presentation/share_summary_button.dart';
import '../application/pr_detector.dart';
import '../application/summary_controller.dart';
import '../domain/workout_set.dart';

/// End-of-workout summary.
///
/// Ordered by the question stack a lifter actually has 30 seconds after racking
/// the last bar: *is it saved → did I beat anything all-time → did I beat last
/// time → how big was this → should I bump my program → what exactly did I
/// lift*. Everything is derived in [sessionSummaryProvider]; this file formats.
///
/// See `docs/design/summary-screen-redesign.md` for the full spec.
class SummaryScreen extends ConsumerWidget {
  const SummaryScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sessionSummaryProvider(sessionId));
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;

    return data.when(
      // Never a bare spinner on an unthemed Scaffold: the shell (and its
      // working Done button) render immediately so the screen can always be
      // left, and the skeleton is suppressed for the first 120ms because local
      // SQLite usually beats it.
      loading: () => const _SummaryShell(
        title: 'COMPLETE',
        child: _DelayedSkeleton(),
      ),
      error: (e, _) => _SummaryShell(
        title: 'COMPLETE',
        child: _SummaryMessage(
          eyebrow: 'SOMETHING WENT WRONG',
          headline: "COULDN'T LOAD THIS SESSION",
          body: 'Your sets are saved. Try again, or open it from History.',
          primaryLabel: 'TRY AGAIN',
          onPrimary: () => ref.invalidate(sessionSummaryProvider(sessionId)),
          secondaryLabel: 'GO HOME',
        ),
      ),
      data: (d) {
        if (d == null) {
          return const _SummaryShell(
            title: 'COMPLETE',
            child: _SummaryMessage(
              eyebrow: 'NOT FOUND',
              headline: "THIS SESSION ISN'T HERE",
              body: 'It may have been deleted.',
              primaryLabel: 'GO HOME',
            ),
          );
        }
        return _SummaryBody(summary: d, unit: unit);
      },
    );
  }
}

/// Screen chrome shared by every state, so loading → loaded never jumps.
class _SummaryShell extends StatelessWidget {
  const _SummaryShell({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LsScreen(
      topGap: LsGap.loose,
      topbar: LsTopbar(
        title: title,
        showBack: false,
        trailing: trailing ??
            Builder(
              builder: (context) => LsIconSquare(
                icon: Icons.check,
                onTap: () => context.go('/'),
                semanticLabel: 'Done',
              ),
            ),
      ),
      child: child,
    );
  }
}

class _SummaryBody extends ConsumerStatefulWidget {
  const _SummaryBody({required this.summary, required this.unit});
  final SessionSummary summary;
  final WeightUnit unit;

  @override
  ConsumerState<_SummaryBody> createState() => _SummaryBodyState();
}

class _SummaryBodyState extends ConsumerState<_SummaryBody> {
  /// Which lift cards are expanded. Held HERE, above the `ListView`, not in the
  /// cards: the list builds lazily, so a card scrolled out of the viewport
  /// loses any state it owns itself.
  final _expanded = <String>{};
  bool _allExpanded = false;

  void _toggle(String exerciseId) {
    setState(() {
      if (!_expanded.remove(exerciseId)) _expanded.add(exerciseId);
      _allExpanded = _expanded.length == widget.summary.exercises.length;
    });
  }

  void _toggleAll() {
    setState(() {
      _allExpanded = !_allExpanded;
      _expanded
        ..clear()
        ..addAll(_allExpanded
            ? widget.summary.exercises.map((e) => e.exerciseId)
            : const <String>[]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.summary;
    final unit = widget.unit;
    final prs = <String, ExercisePR>{
      for (final e in d.exercises)
        if (e.pr != null) e.exerciseId: e.pr!,
    };

    // Headless snapshot for outbound share (text + branded card), built from
    // the data already loaded — no extra DB reads.
    final shareSummary = WorkoutSummary.fromSession(
      date: d.session.startedAt,
      duration: d.session.duration,
      sets: [for (final e in d.exercises) ...e.setGroups.expand((g) => g)],
      exerciseNames: {for (final e in d.exercises) e.exerciseId: e.name},
      prs: prs,
      programName: d.programName,
      dayName: d.dayName,
    );

    final hasSets = d.setCount > 0;

    return _SummaryShell(
      title: (d.programName ?? 'Complete').toUpperCase(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShareSummaryButton(summary: shareSummary, unit: unit),
          const SizedBox(width: 10),
          LsIconSquare(
            icon: Icons.check,
            onTap: () => context.go('/'),
            semanticLabel: 'Done',
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Masthead(summary: d),
          const SizedBox(height: LsGap.loose),
          if (!hasSets)
            const _SummaryMessage(
              eyebrow: 'NO SETS LOGGED',
              headline: 'NOTHING RECORDED',
              body: 'You finished before logging a set. '
                  'Nothing was added to your history.',
              primaryLabel: 'BACK TO HOME',
            )
          else ...[
            _VolumeBlock(summary: d, unit: unit),
            const SizedBox(height: LsGap.loose),
            if (d.prCount > 0) ...[
              _PrStrip(summary: d, unit: unit),
              const SizedBox(height: LsGap.loose),
            ],
            if (d.isFirstEverSession) ...[
              _BaselineCard(dayName: d.dayName),
              const SizedBox(height: LsGap.loose),
            ] else if (d.hasPrevSession) ...[
              _ProgressBlock(summary: d),
              const SizedBox(height: LsGap.loose),
            ],
            _ProgramUpdatesBlock(sessionId: d.session.id, unit: unit),
            _LiftsBlock(
              summary: d,
              unit: unit,
              expanded: _expanded,
              allExpanded: _allExpanded,
              onToggle: _toggle,
              onToggleAll: _toggleAll,
            ),
            const SizedBox(height: LsGap.loose),
            _Footer(summary: d, shareSummary: shareSummary, unit: unit),
          ],
          const SizedBox(height: LsGap.screenBot),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 0 — MASTHEAD
// ─────────────────────────────────────────────────────────────────────────────

class _Masthead extends StatelessWidget {
  const _Masthead({required this.summary});
  final SessionSummary summary;

  /// Deterministic size ladder — no `FittedBox`, so the hero never renders at
  /// an arbitrary in-between size. Steps down one rung under large Dynamic Type.
  static double heroSize(String name, double textScale) {
    final base = name.length <= 12
        ? 72.0
        : name.length <= 22
            ? 56.0
            : 44.0;
    if (textScale <= 1.15) return base;
    return base == 72 ? 56 : (base == 56 ? 44 : 36);
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final d = summary;
    final hero = (d.dayName ?? 'Workout').toUpperCase();
    final scale = MediaQuery.of(context).textScaler.scale(1);
    final date = DateFormat('EEE · MMM d').format(d.session.startedAt);

    final meta = [
      _formatDuration(d.session.duration),
      '${d.exerciseCount} ${d.exerciseCount == 1 ? 'LIFT' : 'LIFTS'}',
      '${d.setCount} ${d.setCount == 1 ? 'SET' : 'SETS'}',
    ].join(' · ');

    return Semantics(
      container: true,
      label: '${d.dayName ?? 'Workout'}, saved $date. '
          '${d.session.duration.inMinutes} minutes, '
          '${d.exerciseCount} lifts, ${d.setCount} sets.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: EyebrowLabel('SAVED · $date'),
            ),
            const SizedBox(height: LsGap.sub),
            Text(
              hero,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LsType.displayHome.copyWith(
                color: t.surface.text,
                fontSize: heroSize(hero, scale),
                height: 0.92,
              ),
            ),
            const SizedBox(height: LsGap.sub),
            Text(
              meta,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LsType.monoMeta.copyWith(color: t.surface.text2),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 1 — THE NUMBER
// ─────────────────────────────────────────────────────────────────────────────

class _VolumeBlock extends StatelessWidget {
  const _VolumeBlock({required this.summary, required this.unit});
  final SessionSummary summary;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final d = summary;
    final value =
        summaryTonnageGrouped(WeightConv.fromKg(d.totalVolumeKg, unit));
    final deltaLine = _deltaLine(context, t);

    return Semantics(
      container: true,
      label: 'Total volume $value ${unit.short}.'
          '${deltaLine == null ? '' : ' ${deltaLine.semantics}'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EyebrowLabel('TOTAL VOLUME'),
            const SizedBox(height: LsGap.sub),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _CountUpNumeral(
                    finalText: value,
                    style: LsType.monoNumeral.copyWith(
                      color: t.surface.text,
                      fontSize: 64,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      unit.short.toUpperCase(),
                      style: LsType.monoMeta.copyWith(
                        color: t.surface.text2,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (deltaLine != null) ...[
              const SizedBox(height: LsGap.tight),
              deltaLine.widget,
            ],
            const SizedBox(height: LsGap.section),
            Container(height: 2, color: t.accent.accent),
          ],
        ),
      ),
    );
  }

  _DeltaLine? _deltaLine(BuildContext context, LsTheme t) {
    final d = summary;
    final dayLabel = (d.dayName ?? 'THIS DAY').toUpperCase();
    TextStyle style(Color c) =>
        LsType.monoMeta.copyWith(color: c, fontSize: 15);

    if (d.session.programDayId == null) return null;

    if (d.isFirstEverSession) {
      return _DeltaLine(
        widget: _iconLine(
            Icons.flag, 'FIRST SESSION · BASELINE SET', t.accent.accent, style),
        semantics: 'First session logged, baseline set.',
      );
    }
    if (!d.hasPrevSession) {
      return _DeltaLine(
        widget: Text('FIRST TIME ON $dayLabel',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style(t.surface.text2)),
        semantics: 'First time on $dayLabel.',
      );
    }

    final delta = d.volumeDeltaKg ?? 0;
    final pct = d.volumeDeltaPercent;
    if (delta.abs() < 1e-6) {
      return _DeltaLine(
        widget: _iconLine(
            Icons.remove, 'MATCHED LAST $dayLabel', t.surface.text2, style),
        semantics: 'Matched last $dayLabel.',
      );
    }
    final up = delta > 0;
    final colour = up ? t.accent.accent : LsSignals.danger;
    // Grouped, like the hero numeral above it — "1,810 KG", not "1810 KG".
    final abs = '${summaryTonnageGrouped(WeightConv.fromKg(delta.abs(), unit))}'
        ' ${unit.short.toUpperCase()}';
    final valueText = '${up ? '+' : '−'}$abs'
        '${pct == null ? '' : ' · ${up ? '+' : '−'}${pct.abs()}%'}';
    return _DeltaLine(
      widget: Row(
        children: [
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14, color: colour),
          const SizedBox(width: 6),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(children: [
                TextSpan(text: valueText, style: style(colour)),
                TextSpan(
                    text: '  VS LAST $dayLabel',
                    style: style(t.surface.text2)),
              ]),
            ),
          ),
        ],
      ),
      semantics: '${up ? 'Up' : 'Down'} $abs'
          '${pct == null ? '' : ', ${pct.abs()} percent'}, '
          'versus last $dayLabel.',
    );
  }

  Widget _iconLine(IconData icon, String text, Color colour,
      TextStyle Function(Color) style) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style(colour)),
        ),
      ],
    );
  }
}

class _DeltaLine {
  const _DeltaLine({required this.widget, required this.semantics});
  final Widget widget;
  final String semantics;
}

/// Counts the tonnage up from zero once, on first build. The final string is
/// rendered invisibly underneath so the box never changes width mid-animation.
class _CountUpNumeral extends StatelessWidget {
  const _CountUpNumeral({required this.finalText, required this.style});
  final String finalText;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final target = double.tryParse(finalText.replaceAll(',', '')) ?? 0;
    if (reduceMotionOf(context) || target <= 0) {
      return Text(finalText, style: style);
    }
    return Stack(
      children: [
        Opacity(opacity: 0, child: Text(finalText, style: style)),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) =>
                  Text(summaryTonnageGrouped(v), style: style),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 2 — PR STRIP
// ─────────────────────────────────────────────────────────────────────────────

class _PrStrip extends StatelessWidget {
  const _PrStrip({required this.summary, required this.unit});
  final SessionSummary summary;
  final WeightUnit unit;

  /// Gold ink is dark-mode only: #FFB400 on a light surface is 1.78:1. On
  /// light, gold is reserved for the bar, border and glyph.
  Color _ink(LsTheme t) => t.isLight ? t.surface.text : LsSignals.pr;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final prs = summary.exercises.where((e) => e.isPr).toList();
    final single = prs.length == 1;
    final ink = _ink(t);

    return ClipRRect(
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: Container(
        decoration: BoxDecoration(
          color: t.prDimBg,
          border: Border.all(color: LsSignals.pr),
          borderRadius: BorderRadius.circular(LsRadius.r3),
        ),
        // Stack + Positioned rather than IntrinsicHeight + a stretched Row:
        // the bar animates its height, and an animated FractionallySizedBox
        // under an IntrinsicHeight makes this card's height depend on an
        // intrinsic pass over a widget that has no stable intrinsic size —
        // inside a lazily-built ListView that can throw the scroll extent off.
        // Here the bar is positioned against tight constraints instead, so the
        // card's height comes from its text alone.
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Padding(
                  padding: LsPad.cardSpacious,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: LsSignals.pr),
                          const SizedBox(width: 8),
                          Text(
                            single
                                ? 'NEW PERSONAL RECORD'
                                : '${prs.length} PERSONAL RECORDS',
                            style: LsType.monoMeta
                                .copyWith(color: ink, fontSize: 15),
                          ),
                        ],
                      ),
                      for (var i = 0; i < prs.length; i++) ...[
                        const SizedBox(height: LsGap.section),
                        _prRow(t, prs[i], single, ink),
                      ],
                    ],
                  ),
                ),
            ),
            const Positioned(left: 0, top: 0, bottom: 0, width: 4, child: _PrBar()),
          ],
        ),
      ),
    );
  }

  Widget _prRow(LsTheme t, ExerciseSummary e, bool single, Color ink) {
    final kind = e.pr!.kind == PrKind.weight
        ? 'HEAVIEST EVER'
        : 'MOST REPS AT ${WeightConv.format(e.pr!.weightKg, unit).toUpperCase()}';
    final top =
        '${WeightConv.format(e.topWeightKg, unit).toUpperCase()} × ${e.topReps}';
    return Semantics(
      container: true,
      label: 'New personal record. ${e.name}, $top. $kind.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LsType.displayM.copyWith(
                color: t.surface.text,
                fontSize: single ? 30 : 26,
              ),
            ),
            const SizedBox(height: LsGap.tight),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(top,
                    style: LsType.monoData.copyWith(
                      color: t.surface.text,
                      fontSize: single ? 20 : 18,
                    )),
                Text('  ·  ',
                    style: LsType.monoMeta.copyWith(color: t.surface.text3)),
                Text(kind,
                    style: LsType.monoMeta.copyWith(
                      color: ink,
                      fontSize: single ? 15 : 13,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The 4pt gold rule down the PR strip's left edge. Wipes in once (120ms hold,
/// then 320ms) so the eye lands on the highest-value element as the screen
/// settles; the text beside it is opaque from frame one either way.
class _PrBar extends StatelessWidget {
  const _PrBar();

  @override
  Widget build(BuildContext context) {
    // Keep the explicit width: `Align` loosens its child's constraints, and a
    // childless ColoredBox under loose constraints collapses to zero.
    const bar = SizedBox(width: 4, child: ColoredBox(color: LsSignals.pr));
    if (reduceMotionOf(context)) return bar;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 440),
      curve: const Interval(120 / 440, 1, curve: LsMotion.slowCurve),
      builder: (context, v, child) => Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(heightFactor: v, child: child),
      ),
      child: bar,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 3 — VS LAST TIME
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.summary});
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final d = summary;
    final days = d.daysSincePrev ?? 0;
    final when = days == 0
        ? 'TODAY'
        : days == 1
            ? '1 DAY AGO'
            : '$days DAYS AGO';
    final dayLabel = (d.dayName ?? 'THIS DAY').toUpperCase();

    // (delta, label, bar fill, legend ink) — the neutral fills read fine as a
    // 10pt block but not as 13px type, so the legend gets its own colour.
    final segments = <(ProgressDelta, String, Color, Color)>[
      (ProgressDelta.up, 'UP', t.accent.accent, t.accent.accent),
      (ProgressDelta.matched, 'MATCHED', t.surface.borderStrong, t.surface.text),
      (ProgressDelta.down, 'DOWN', LsSignals.danger, LsSignals.danger),
      (ProgressDelta.fresh, 'NEW', t.surface.surface3, t.surface.text2),
    ].where((s) => d.tallyOf(s.$1) > 0).toList();

    if (segments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowLabel('VS LAST $dayLabel · $when'),
        const SizedBox(height: LsGap.section),
        ExcludeSemantics(
          child: SizedBox(
            height: 10,
            child: Row(
              // Tight cross-axis constraints: the segments are childless
              // DecoratedBoxes, which collapse to zero height under the
              // default (loose) `center` alignment.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: d.tallyOf(segments[i].$1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: segments[i].$3,
                        borderRadius: BorderRadius.circular(LsRadius.r1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: LsGap.tight),
        Wrap(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Text('  ·  ',
                    style: LsType.monoMeta.copyWith(color: t.surface.text3)),
              Text('${d.tallyOf(segments[i].$1)}',
                  style: LsType.monoMeta.copyWith(color: segments[i].$4)),
              Text(' ${segments[i].$2}',
                  style: LsType.monoMeta.copyWith(color: t.surface.text2)),
            ],
          ],
        ),
      ],
    );
  }
}

/// Replaces the vs-last block on the user's very first session — the empty
/// state that is actually an achievement.
class _BaselineCard extends StatelessWidget {
  const _BaselineCard({required this.dayName});
  final String? dayName;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return LsCard(
      padding: LsPad.cardSpacious,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EyebrowLabel('BASELINE'),
          const SizedBox(height: LsGap.section),
          Text('THIS IS YOUR BENCHMARK',
              style: LsType.displayM
                  .copyWith(color: t.surface.text, fontSize: 30)),
          const SizedBox(height: LsGap.tight),
          Text(
            'Every future ${(dayName ?? 'session').toUpperCase()} gets measured '
            'against today.',
            style: LsType.bodyM.copyWith(color: t.surface.text2),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 4 — UPDATE YOUR PROGRAM
// ─────────────────────────────────────────────────────────────────────────────

class _ProgramUpdatesBlock extends ConsumerWidget {
  const _ProgramUpdatesBlock({required this.sessionId, required this.unit});
  final String sessionId;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updates =
        ref.watch(programUpdatesProvider(sessionId)).value ?? const [];
    if (updates.isEmpty) return const SizedBox.shrink();

    final pending = updates.where((u) => !u.applied).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EyebrowLabel('UPDATE YOUR PROGRAM'),
        const SizedBox(height: LsGap.section),
        LsCard(
          padding: LsPad.cardSpacious,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < updates.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: LsGap.section),
                  const LsHairline(),
                  const SizedBox(height: LsGap.section),
                ],
                _ProgramUpdateRow(
                  sessionId: sessionId,
                  update: updates[i],
                  unit: unit,
                ),
              ],
              if (updates.length > 1) ...[
                const SizedBox(height: LsGap.section),
                LsButton(
                  label: pending == 0
                      ? 'UNDO ALL'
                      : pending == updates.length
                          ? 'APPLY ALL · $pending'
                          : 'APPLY REMAINING · $pending',
                  variant: pending == 0
                      ? LsButtonVariant.secondary
                      : LsButtonVariant.primary,
                  expand: true,
                  onPressed: () => _batch(context, ref, undo: pending == 0),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: LsGap.loose),
      ],
    );
  }

  Future<void> _batch(BuildContext context, WidgetRef ref,
      {required bool undo}) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = ref.read(programUpdatesProvider(sessionId).notifier);
    final n = undo ? await ctrl.undoAll() : await ctrl.applyAll();
    if (n == 0) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(undo
            ? '$n program ${n == 1 ? 'update' : 'updates'} undone'
            : '$n program ${n == 1 ? 'target' : 'targets'} updated'),
        duration: const Duration(seconds: 5),
        action: undo
            ? null
            : SnackBarAction(label: 'UNDO', onPressed: ctrl.undoAll),
      ));
  }
}

class _ProgramUpdateRow extends ConsumerWidget {
  const _ProgramUpdateRow({
    required this.sessionId,
    required this.update,
    required this.unit,
  });
  final String sessionId;
  final ProgramUpdate update;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final u = update;
    final isAdd = u.isAddKind;
    final slot = (u.slotName ?? '').toUpperCase();
    final targetWord =
        u.kind == ProgramUpdateKind.raiseVariant ? 'VARIANT TARGET' : 'TARGET';
    // Non-breaking spaces: a weight never splits between number and unit.
    final spoken = WeightConv.format(u.proposedTargetKg, unit).toUpperCase();
    final proposed = _nb(spoken);
    final dataStyle = LsType.monoData.copyWith(fontSize: 20);

    // QA VAR-08: these lines WRAP rather than ellipsize — the old Row gave the
    // new weight whatever width was left after the label and the old weight,
    // which on a variant card was nothing ("40 → 42…", or "42.5 →" with the
    // value gone). In a Wrap the "old → new" group drops below the label when
    // it doesn't fit beside it, and itself wraps at the arrow if it must.
    final valueLine = isAdd
        ? Text(
            u.kind == ProgramUpdateKind.addVariant
                ? 'VARIANT OF $slot @ $proposed'
                : '${u.targetSets} × ${u.targetRepsMax} @ $proposed',
            style: dataStyle.copyWith(color: t.surface.text),
          )
        : Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(targetWord,
                  style: LsType.monoMeta.copyWith(color: t.surface.text2)),
              u.applied
                  ? Text(proposed,
                      style: dataStyle.copyWith(color: t.surface.text))
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: _nb(WeightConv.format(u.currentTargetKg ?? 0, unit)
                              .toUpperCase()
                              .replaceAll(' ${unit.short.toUpperCase()}', '')),
                          style: dataStyle.copyWith(color: t.surface.text3),
                        ),
                        TextSpan(
                          text: ' → ',
                          style: dataStyle.copyWith(color: t.surface.text3),
                        ),
                        TextSpan(
                          text: proposed,
                          style: dataStyle.copyWith(color: t.surface.text),
                        ),
                      ]),
                    ),
            ],
          );

    final statusWord = u.applied
        ? (u.kind == ProgramUpdateKind.addVariant
            ? 'SAVED'
            : (isAdd ? 'ADDED' : 'UPDATED'))
        : null;
    final tag = statusWord ??
        switch (u.kind) {
          ProgramUpdateKind.add => 'NOT IN PLAN',
          ProgramUpdateKind.addVariant => 'SWAPPED IN',
          // The value line already reads VARIANT TARGET (QA VAR-08: the
          // extra tag only took width from the name).
          ProgramUpdateKind.raiseVariant => null,
          ProgramUpdateKind.raise => null,
        };

    return Semantics(
      container: true,
      button: !u.applied,
      label: u.applied
          ? '${u.exerciseName} ${_appliedPhrase(u, spoken)}.'
          : '${u.exerciseName}. ${_pendingPhrase(u, spoken)}.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(LsRadius.r2),
            onTap: u.applied
                ? null
                : () => _apply(context, ref),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                // Signal 2 of 3: the whole row tints once applied.
                color: u.applied ? t.accentDimBg : Colors.transparent,
                borderRadius: BorderRadius.circular(LsRadius.r2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // A Wrap, not a Row (QA VAR-08): the name gets the
                        // full width and wraps; the tag sits
                        // beside it when there's room and drops below when
                        // there isn't, instead of squeezing the name to
                        // "SHOULDER PRESS (…".
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              u.exerciseName.toUpperCase(),
                              // Wraps (2 lines for "SHOULDER PRESS (MACHINE)",
                              // 3 for a long name) before any ellipsis.
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: LsType.displayS.copyWith(
                                  color: t.surface.text, fontSize: 23),
                            ),
                            // Signal 3 of 3: a word, so the state survives
                            // greyscale and colour-blindness.
                            if (tag != null)
                              Text(
                                tag,
                                style: LsType.monoMeta.copyWith(
                                  color: statusWord != null
                                      ? t.accent.accent
                                      : t.surface.text3,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: LsGap.tight),
                        valueLine,
                      ],
                    ),
                  ),
                  const SizedBox(width: LsGap.inline),
                  // Signal 1 of 3: outline → filled.
                  _AppliedSquare(
                    applied: u.applied,
                    idleIcon: isAdd ? Icons.add : Icons.arrow_upward,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = ref.read(programUpdatesProvider(sessionId).notifier);
    final conflict = await ctrl.applyOne(update.exerciseId);
    if (conflict != null) {
      _showConflict(messenger, conflict);
      return;
    }
    final proposed =
        WeightConv.format(update.proposedTargetKg, unit).toUpperCase();
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(_snackText(update, proposed, null)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => ctrl.undoOne(update.exerciseId),
        ),
      ));
  }
}

/// 44pt trailing square. Outline + action glyph when pending, accent-filled +
/// check when applied — the app's established selected/unselected language.
class _AppliedSquare extends StatelessWidget {
  const _AppliedSquare({required this.applied, required this.idleIcon});
  final bool applied;
  final IconData idleIcon;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: applied ? t.accent.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(LsRadius.r2),
        border: applied ? null : Border.all(color: t.accent.accent),
      ),
      child: Icon(
        applied ? Icons.check : idleIcon,
        size: applied ? 20 : 18,
        color: applied ? t.accent.accentInk : t.accent.accent,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 5 — THE LIFTS
// ─────────────────────────────────────────────────────────────────────────────

class _LiftsBlock extends StatelessWidget {
  const _LiftsBlock({
    required this.summary,
    required this.unit,
    required this.expanded,
    required this.allExpanded,
    required this.onToggle,
    required this.onToggleAll,
  });
  final SessionSummary summary;
  final WeightUnit unit;
  final Set<String> expanded;
  final bool allExpanded;
  final void Function(String exerciseId) onToggle;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: EyebrowLabel('THE LIFTS · ${summary.exerciseCount}'),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(LsRadius.r2),
                onTap: onToggleAll,
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(allExpanded ? 'HIDE SETS' : 'ALL SETS',
                            style: LsType.monoMeta
                                .copyWith(color: t.surface.text2)),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: allExpanded ? 0.5 : 0,
                          duration: LsMotion.base,
                          child: Icon(Icons.expand_more,
                              size: 18, color: t.surface.text2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LsGap.section),
        for (var i = 0; i < summary.exercises.length; i++) ...[
          if (i > 0) const SizedBox(height: LsGap.item),
          _LiftCard(
            index: i + 1,
            exercise: summary.exercises[i],
            sessionId: summary.session.id,
            dayName: summary.dayName,
            unit: unit,
            expanded: expanded.contains(summary.exercises[i].exerciseId),
            onToggle: () => onToggle(summary.exercises[i].exerciseId),
          ),
        ],
      ],
    );
  }
}

class _LiftCard extends ConsumerWidget {
  const _LiftCard({
    required this.index,
    required this.exercise,
    required this.sessionId,
    required this.dayName,
    required this.unit,
    required this.expanded,
    required this.onToggle,
  });
  final int index;
  final ExerciseSummary exercise;
  final String sessionId;
  final String? dayName;
  final WeightUnit unit;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final e = exercise;
    final top =
        '${WeightConv.format(e.topWeightKg, unit).toUpperCase()} × ${e.topReps}';
    final delta = _delta(t);

    return Semantics(
      container: true,
      button: true,
      label: '${e.name}.${e.isPr ? ' Personal record.' : ''}'
          '${e.isFirstExposure ? ' First time.' : ''}'
          '${e.isVariant ? ' Variant of ${e.variantOfName}.' : ''} '
          '$top, ${e.setCount} sets. ${delta.semantics}',
      hint: expanded ? 'Double tap to hide sets.' : 'Double tap to show sets.',
      child: ExcludeSemantics(
        child: LsCard(
          padding: LsPad.cardStd,
          onTap: onToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: LsBox.tileIndex,
                    height: LsBox.tileIndex,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accent.accentDim,
                      borderRadius: BorderRadius.circular(LsRadius.r2),
                    ),
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: LsType.monoMeta.copyWith(
                        color: t.accent.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: LsGap.inline),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                e.name.toUpperCase(),
                                // Three lines: a long variant name next to its
                                // PR chip ("SINGLE-ARM LANDMINE / SHOULDER
                                // PRESS / (MACHINE)") stays whole (QA VAR-08).
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: LsType.displayM.copyWith(
                                    color: t.surface.text, fontSize: 26),
                              ),
                            ),
                            if (e.isPr) ...[
                              const SizedBox(width: 8),
                              const _PrChip(),
                            ] else if (e.isFirstExposure) ...[
                              const SizedBox(width: 8),
                              Text('FIRST TIME',
                                  style: LsType.monoMeta
                                      .copyWith(color: t.accent.accent)),
                            ] else if (!e.inPlan) ...[
                              const SizedBox(width: 8),
                              Text('NOT IN PLAN',
                                  style: LsType.monoMeta
                                      .copyWith(color: t.surface.text3)),
                            ],
                          ],
                        ),
                        if (e.isVariant) ...[
                          const SizedBox(height: 4),
                          Text(
                            'VARIANT OF '
                            '${(e.variantOfName ?? '').toUpperCase()}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LsType.monoMeta
                                .copyWith(color: t.surface.text3),
                          ),
                        ],
                        const SizedBox(height: 6),
                        // Wrap, not Row: at the widest combination (a 3-digit
                        // weight plus a long delta word) the three parts are
                        // ~1pt over the content width, and an ellipsised
                        // "2…" is worse than a second line.
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 2,
                          children: [
                            RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: top,
                                  style: LsType.monoData.copyWith(
                                      color: t.surface.text, fontSize: 20),
                                ),
                                TextSpan(
                                  text: ' · ${e.setCount} '
                                      '${e.setCount == 1 ? 'SET' : 'SETS'}',
                                  style: LsType.monoMeta
                                      .copyWith(color: t.surface.text2),
                                ),
                              ]),
                            ),
                            delta.widget,
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (expanded) _expandedBody(context, ref, t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandedBody(BuildContext context, WidgetRef ref, LsTheme t) {
    final e = exercise;
    // A variant's TARGET line: the slot's sets/reps at the variant's weight.
    final pe = e.planPe ??
        (e.planVariant == null
            ? null
            : e.variantSlotPe
                ?.copyWith(defaultWeightKg: e.planVariant!.defaultWeightKg));
    final update = ref
        .watch(programUpdatesProvider(sessionId))
        .value
        ?.where((u) => u.exerciseId == e.exerciseId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LsGap.section),
        const LsHairline(),
        const SizedBox(height: LsGap.section),
        if (pe != null) ...[
          Text(
            'TARGET  ${pe.targetSets} × '
            '${pe.targetRepsMin == pe.targetRepsMax ? '${pe.targetRepsMin}' : '${pe.targetRepsMin}-${pe.targetRepsMax}'}'
            ' @ ${WeightConv.format(pe.defaultWeightKg, unit).toUpperCase()}',
            style: LsType.monoMeta.copyWith(color: t.surface.text2),
          ),
          const SizedBox(height: LsGap.sub),
        ],
        for (var g = 0; g < e.setGroups.length; g++) ...[
          if (g > 0) const SizedBox(height: LsGap.item),
          _SetRow(group: e.setGroups[g], ordinal: g + 1, unit: unit),
        ],
        if (e.prevTopWeightKg != null) ...[
          const SizedBox(height: LsGap.section),
          Text(
            'LAST TIME   '
            '${WeightConv.format(e.prevTopWeightKg!, unit).toUpperCase()} × ${e.prevTopReps ?? 0}'
            '${e.prevSetCount == null ? '' : '  ·  ${e.prevSetCount} SETS'}',
            style: LsType.monoMeta.copyWith(color: t.surface.text3),
          ),
        ],
        if (update != null) ...[
          const SizedBox(height: LsGap.section),
          _InlineProgramAction(
            sessionId: sessionId,
            update: update,
            dayName: dayName,
            unit: unit,
          ),
        ],
      ],
    );
  }

  _DeltaLine _delta(LsTheme t) {
    final e = exercise;
    TextStyle style(Color c) =>
        LsType.monoMeta.copyWith(color: c, fontSize: 15);
    switch (e.delta) {
      case ProgressDelta.fresh:
        return _DeltaLine(
          widget: Text('NEW', style: style(t.surface.text3)),
          semantics: 'New.',
        );
      case ProgressDelta.matched:
        return _DeltaLine(
          widget: Text('— MATCHED', style: style(t.surface.text2)),
          semantics: 'Matched last time.',
        );
      case ProgressDelta.up:
      case ProgressDelta.down:
        final up = e.delta == ProgressDelta.up;
        final colour = up ? t.accent.accent : LsSignals.danger;
        final dW = e.topWeightKg - (e.prevTopWeightKg ?? 0);
        final label = dW.abs() < 1e-6
            ? '${up ? '+' : ''}${e.topReps - (e.prevTopReps ?? 0)} REPS'
            : '${up ? '+' : '−'}'
                '${WeightConv.format(dW.abs(), unit).toUpperCase()}';
        return _DeltaLine(
          widget: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14, color: colour),
              const SizedBox(width: 2),
              Text(label, style: style(colour)),
            ],
          ),
          semantics: '${up ? 'Up' : 'Down'} $label.',
        );
    }
  }
}

/// Dark ink on solid gold — 10:1 in BOTH themes, which is why this is a filled
/// chip rather than the tinted badge it replaces.
class _PrChip extends StatelessWidget {
  const _PrChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: LsSignals.pr,
        borderRadius: BorderRadius.circular(LsRadius.r2),
      ),
      child: Text(
        'PR',
        style: LsType.monoMeta.copyWith(
          color: lsDark.bg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.group,
    required this.ordinal,
    required this.unit,
  });

  /// One logical set: `[top]`, or `[top, drop, drop…]` for a drop set.
  final List<WorkoutSet> group;
  final int ordinal;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final top = group.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text('$ordinal',
              style: LsType.monoMeta.copyWith(color: t.surface.text3)),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${WeightConv.format(top.weightKg, unit).toUpperCase()} × ${top.reps}',
                style: LsType.monoData
                    .copyWith(color: t.surface.text, fontSize: 20),
              ),
              // Drops stay on the same line — one logical set reads as one row.
              for (var i = 1; i < group.length; i++)
                Text(
                  '  ↓ ${WeightConv.format(group[i].weightKg, unit).toUpperCase()} × ${group[i].reps}',
                  style: LsType.monoData
                      .copyWith(color: t.surface.text2, fontSize: 18),
                ),
            ],
          ),
        ),
        if (top.rir > 0) ...[
          const SizedBox(width: 8),
          Text('RIR ${top.rir}',
              style: LsType.monoMeta.copyWith(color: t.surface.text2)),
        ],
      ],
    );
  }
}

/// The per-exercise program action inside an expanded lift card. Reads and
/// writes the same [programUpdatesProvider] entry as the Block 4 row, so the
/// two can never disagree.
class _InlineProgramAction extends ConsumerWidget {
  const _InlineProgramAction({
    required this.sessionId,
    required this.update,
    required this.dayName,
    required this.unit,
  });
  final String sessionId;
  final ProgramUpdate update;
  final String? dayName;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final u = update;
    final isAdd = u.isAddKind;
    final weight =
        _nb(WeightConv.format(u.proposedTargetKg, unit).toUpperCase());
    final raiseLabel = u.kind == ProgramUpdateKind.raiseVariant
        ? 'VARIANT TARGET → $weight'
        : (u.currentTargetKg ?? 0) < u.proposedTargetKg - 1e-6
            ? 'RAISE TARGET → $weight'
            : 'SET TARGET → $weight';
    final label = u.applied
        ? switch (u.kind) {
            ProgramUpdateKind.add => 'ADDED',
            ProgramUpdateKind.addVariant => 'SAVED AS VARIANT',
            _ => 'TARGET SET',
          }
        : switch (u.kind) {
            ProgramUpdateKind.add =>
              'ADD TO ${(dayName ?? 'DAY').toUpperCase()}',
            ProgramUpdateKind.addVariant =>
              'SAVE AS VARIANT OF ${(u.slotName ?? '').toUpperCase()}',
            _ => raiseLabel,
          };
    final fg = u.applied ? t.accent.accentInk : t.accent.accent;

    return Semantics(
      button: !u.applied,
      label: u.applied
          ? '${u.exerciseName} ${_appliedPhrase(u, weight)}.'
              .replaceAll('\u00A0', ' ')
          : label.replaceAll('\u00A0', ' '),
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(LsRadius.r2),
            onTap: u.applied ? null : () => _apply(context, ref),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: u.applied ? t.accent.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(LsRadius.r2),
                border:
                    u.applied ? null : Border.all(color: t.accent.accent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    u.applied ? Icons.check : (isAdd ? Icons.add : Icons.arrow_upward),
                    size: 16,
                    color: fg,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    // Two lines before an ellipsis: "VARIANT TARGET → 42.5 KG"
                    // must keep its number (QA VAR-08).
                    child: Text(label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: LsType.monoMeta.copyWith(color: fg)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = ref.read(programUpdatesProvider(sessionId).notifier);
    final conflict = await ctrl.applyOne(update.exerciseId);
    if (conflict != null) {
      _showConflict(messenger, conflict);
      return;
    }
    final weight = WeightConv.format(update.proposedTargetKg, unit).toUpperCase();
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(_snackText(update, weight, dayName)),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => ctrl.undoOne(update.exerciseId),
        ),
      ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BLOCK 6 — FOOTER
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.summary,
    required this.shareSummary,
    required this.unit,
  });
  final SessionSummary summary;
  final WorkoutSummary shareSummary;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final d = summary;
    final pace = d.pacePerSet;
    final clock = DateFormat('HH:mm');
    final ended = d.session.endedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LsHairline(),
        const SizedBox(height: LsGap.section),
        if (pace != null)
          Text(
            [
              if (ended != null)
                '${clock.format(d.session.startedAt)} → ${clock.format(ended)}',
              '${pace.inMinutes}:${(pace.inSeconds.remainder(60)).toString().padLeft(2, '0')} AVG / SET',
            ].join('  ·  '),
            textAlign: TextAlign.center,
            style: LsType.monoMeta.copyWith(color: t.surface.text3),
          ),
        const SizedBox(height: LsGap.loose),
        ShareSummaryButton(
          summary: shareSummary,
          unit: unit,
          style: ShareButtonStyle.wide,
        ),
        const SizedBox(height: LsGap.item),
        LsButton(
          label: 'DONE',
          expand: true,
          minHeight: LsBox.cta,
          onPressed: () => context.go('/'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED STATES
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryMessage extends StatelessWidget {
  const _SummaryMessage({
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
  });
  final String eyebrow;
  final String headline;
  final String body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: Alignment.centerLeft, child: EyebrowLabel(eyebrow)),
        const SizedBox(height: LsGap.section),
        Text(headline,
            style:
                LsType.displayM.copyWith(color: t.surface.text, fontSize: 26)),
        const SizedBox(height: LsGap.tight),
        Text(body, style: LsType.bodyM.copyWith(color: t.surface.text2)),
        const SizedBox(height: LsGap.loose),
        LsButton(
          label: primaryLabel,
          expand: true,
          onPressed: onPrimary ?? () => context.go('/'),
        ),
        if (secondaryLabel != null) ...[
          const SizedBox(height: LsGap.item),
          LsButton(
            label: secondaryLabel!,
            variant: LsButtonVariant.ghost,
            expand: true,
            onPressed: () => context.go('/'),
          ),
        ],
      ],
    );
  }
}

/// Local SQLite normally beats any skeleton, so show nothing for 120ms rather
/// than flash a placeholder the user never asked for.
class _DelayedSkeleton extends StatefulWidget {
  const _DelayedSkeleton();
  @override
  State<_DelayedSkeleton> createState() => _DelayedSkeletonState();
}

class _DelayedSkeletonState extends State<_DelayedSkeleton> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final t = LsTheme.of(context);
    Widget bar(double h, double w, {Alignment align = Alignment.centerLeft}) =>
        Align(
          alignment: align,
          child: Container(
            height: h,
            width: w,
            decoration: BoxDecoration(
              color: t.surface.surface2,
              borderRadius: BorderRadius.circular(LsRadius.r2),
            ),
          ),
        );
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        bar(13, 140, align: Alignment.centerRight),
        const SizedBox(height: LsGap.sub),
        bar(64, 220, align: Alignment.centerRight),
        const SizedBox(height: LsGap.sub),
        bar(13, 200, align: Alignment.centerRight),
        const SizedBox(height: LsGap.loose),
        bar(64, 240),
        const SizedBox(height: LsGap.loose),
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(height: LsGap.item),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: t.surface.surface,
              borderRadius: BorderRadius.circular(LsRadius.r3),
              border: Border.all(color: t.surface.border),
            ),
          ),
        ],
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}H ${m}M';
  return '${m}M';
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROGRAM-UPDATE WORDING (shared by the card and the inline action)
// ─────────────────────────────────────────────────────────────────────────────

/// [s] with its spaces made non-breaking, so a weight like "42.5 KG" never
/// wraps between the number and the unit.
String _nb(String s) => s.replaceAll(' ', '\u00A0');

/// SOW-14 day rule: the program refused the update (it stays pending).
void _showConflict(ScaffoldMessengerState messenger, VariantConflict e) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(e.message)));
}

String _appliedPhrase(ProgramUpdate u, String weight) => switch (u.kind) {
      ProgramUpdateKind.add => 'added to your program',
      ProgramUpdateKind.addVariant =>
        'saved as a variant of ${u.slotName ?? 'its slot'}',
      ProgramUpdateKind.raiseVariant => 'variant target set to $weight',
      ProgramUpdateKind.raise => 'target set to $weight',
    };

String _pendingPhrase(ProgramUpdate u, String weight) => switch (u.kind) {
      ProgramUpdateKind.add => 'Add to your program',
      ProgramUpdateKind.addVariant =>
        'Save as a variant of ${u.slotName ?? 'its slot'}',
      ProgramUpdateKind.raiseVariant => 'Raise variant target to $weight',
      ProgramUpdateKind.raise => 'Raise target to $weight',
    };

String _snackText(ProgramUpdate u, String weight, String? dayName) {
  final name = u.exerciseName.toUpperCase();
  return switch (u.kind) {
    ProgramUpdateKind.add => dayName == null
        ? '$name added to your program'
        : '$name added to ${dayName.toUpperCase()}',
    ProgramUpdateKind.addVariant =>
      '$name saved as a variant of ${(u.slotName ?? '').toUpperCase()}',
    ProgramUpdateKind.raiseVariant => '$name variant target → $weight',
    ProgramUpdateKind.raise => '$name target → $weight',
  };
}
