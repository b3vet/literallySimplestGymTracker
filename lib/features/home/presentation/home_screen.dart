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
import '../../programs/application/programs_provider.dart';
import '../../workout/application/active_workout_controller.dart';
import '../application/home_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final activeSession = ref.watch(activeSessionProvider);
    final hasActive = activeSession.value != null;
    final programs = ref.watch(programsListProvider);
    final lastSession = ref.watch(lastSessionSummaryProvider);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final today = DateFormat('EEE · MMM d').format(DateTime.now());

    return Scaffold(
      backgroundColor: t.surface.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(LsSpace.screen, LsGap.screenTop,
              LsSpace.screen, LsGap.screenBot),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Topbar: brand + settings ─────────────────────────────
              Row(
                children: [
                  const BrandMark(),
                  const Spacer(),
                  LsIconSquare(
                    icon: Icons.settings_outlined,
                    onTap: () => context.push('/settings'),
                    semanticLabel: 'Settings',
                  ),
                ],
              ),
              const SizedBox(height: LsGap.section),
              // ── Right-aligned date eyebrow ───────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: EyebrowLabel(today.toUpperCase()),
              ),
              const SizedBox(height: LsGap.sub),
              // ── Hero — two lines, breaking at the period ─────────────
              Text(
                'TRAIN HEAVY.',
                textAlign: TextAlign.right,
                style: LsType.displayHome.copyWith(color: t.surface.text),
              ),
              Text(
                'LOG CLEAN.',
                textAlign: TextAlign.right,
                style: LsType.displayHome.copyWith(color: t.surface.text),
              ),
              const SizedBox(height: LsGap.section),
              // ── Primary CTA — accent fill, dark inner arrow box ──────
              if (hasActive)
                _StartCta(
                  label: 'RESUME WORKOUT',
                  caption: 'TAP TO CONTINUE',
                  onTap: () => context.push('/workout/active'),
                )
              else
                _StartCta(
                  label: 'START WORKOUT',
                  caption: programs.maybeWhen(
                    data: (list) => list.isEmpty
                        ? 'NO PROGRAMS YET — CREATE ONE'
                        : 'PICK A PROGRAM DAY',
                    orElse: () => '...',
                  ),
                  onTap: () => context.push('/workout/start'),
                ),
              const SizedBox(height: LsGap.section),
              // ── Numbered tile rows ───────────────────────────────────
              _TileRow(
                index: 1,
                label: 'PROGRAMS',
                meta: programs.maybeWhen(
                  data: (list) => list.isEmpty
                      ? 'NONE YET'
                      : '${list.length} ACTIVE',
                  orElse: () => '—',
                ),
                onTap: () => context.push('/programs'),
              ),
              const SizedBox(height: LsGap.item),
              _TileRow(
                index: 2,
                label: 'HISTORY',
                meta: lastSession.maybeWhen(
                  data: (s) => s == null ? 'NONE YET' : 'PAST SESSIONS',
                  orElse: () => '—',
                ),
                onTap: () => context.push('/history'),
              ),
              const SizedBox(height: LsGap.item),
              _TileRow(
                index: 3,
                label: 'STATS',
                meta: 'TOP SET · VOLUME · 1RM',
                onTap: () => context.push('/stats'),
              ),
              const SizedBox(height: LsGap.item),
              _TileRow(
                index: 4,
                label: 'TIPS',
                meta: 'COACHING NOTES',
                onTap: () => context.push('/tips'),
              ),
              // ── Last-session strip pushed to bottom ──────────────────
              const Spacer(),
              _LastSessionFooter(
                summary: lastSession.value,
                unit: unit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Big accent-filled CTA. The inner arrow box sits on top of the accent fill,
/// so the right contrast trick is a translucent BLACK ink rectangle (not white)
/// — matches the `rgba(0,0,0,0.22)` `.arr` rule from the design CSS.
class _StartCta extends StatelessWidget {
  const _StartCta({
    required this.label,
    required this.caption,
    required this.onTap,
  });
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: t.accent.accent,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: Padding(
          padding: LsPad.cta,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: LsType.button.copyWith(
                        color: t.accent.accentInk,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: LsGap.tight),
                    Text(
                      caption.toUpperCase(),
                      style: LsType.monoMeta.copyWith(
                        color: t.accent.accentInk.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: LsBox.ctaArrow,
                height: LsBox.ctaArrow,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Black-on-accent, not white-on-accent — matches CSS spec
                  // `rgba(0,0,0,0.22)`. Holds up against red, magenta, lime,
                  // yellow, cyan.
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(LsRadius.r3),
                ),
                child: Icon(Icons.arrow_forward,
                    color: t.accent.accentInk, size: 26),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.tile-row` from the design — numbered nav row to a sub-section.
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.index,
    required this.label,
    required this.meta,
    required this.onTap,
  });
  final int index;
  final String label;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: t.surface.surface,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: Container(
          padding: LsPad.cardStd,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: t.surface.border),
          ),
          child: Row(
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
                    Text(
                      label,
                      style: LsType.displayS.copyWith(
                        color: t.surface.text,
                        fontSize: 23,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      style: LsType.monoMeta.copyWith(
                        color: t.surface.text3,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom footer strip on home — "LAST · 6 SETS · 930 KG · 13M".
/// Hidden when no completed sessions exist.
class _LastSessionFooter extends StatelessWidget {
  const _LastSessionFooter({required this.summary, required this.unit});
  final LastSessionSummary? summary;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    if (summary == null) return const SizedBox.shrink();
    final s = summary!;
    final volume = WeightConv.format(s.totalVolumeKg, unit).toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, LsGap.section, 0, LsGap.tight),
      child: Text(
        'LAST · ${s.setCount} SETS · $volume · ${s.durationMin}M',
        textAlign: TextAlign.center,
        style: LsType.monoMeta.copyWith(
          color: t.surface.text3,
          fontSize: 12,
          letterSpacing: 1.92,
        ),
      ),
    );
  }
}
