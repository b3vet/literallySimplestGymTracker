import 'dart:ui' as ui;

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
          padding: const EdgeInsets.fromLTRB(
            LsSpace.screen,
            LsGap.screenTop,
            LsSpace.screen,
            LsGap.screenBot,
          ),
          // The outer Column has a fixed topbar at the top, a scrollable
          // middle section, and a footer pinned to the bottom. On a
          // tall device the scroll view simply doesn't scroll — its
          // intrinsic content fits inside the Expanded slot. On a small
          // device (iPhone SE / mini) the hero + CTA + 4 tile rows
          // legitimately exceed the viewport, so the middle section
          // scrolls and the footer stays put. This replaces the old
          // `Spacer()` + content-as-direct-Column-children layout,
          // which overflowed by ~20px in that regime.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Topbar: brand + today's date ─────────────────────────
              // Settings moved into the numbered tile rows below as #05.
              // The right slot now carries the date eyebrow — it lives
              // at the top of the page where you already glance to
              // check the time / battery, instead of competing with the
              // hero for the user's eye.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const BrandMark(),
                  const Spacer(),
                  EyebrowLabel(today.toUpperCase()),
                ],
              ),
              // Scroll region sits flush against the header. A ShaderMask
              // fades the *content's own pixels* into the background at the
              // top and bottom edges — so as a section scrolls past the
              // header (or under the last-session strip) it dissolves
              // smoothly instead of cutting against a hard line. The fade
              // belongs to the content, not a band laid on top of it.
              //
              // The scroll view carries `_kEdgeFade` of internal padding at
              // each end, so at rest the hero and the last tile sit clear of
              // the fade zones (crisp), and only begin to fade once they're
              // actually scrolled into the edge.
              Expanded(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: _edgeFadeShader,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: _kEdgeFade),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Hero — two lines, breaking at the period ─────
                        Text(
                          'TRAIN HEAVY.',
                          textAlign: TextAlign.right,
                          style: LsType.displayHome.copyWith(
                            color: t.surface.text,
                          ),
                        ),
                        Text(
                          'LOG CLEAN.',
                          textAlign: TextAlign.right,
                          style: LsType.displayHome.copyWith(
                            color: t.surface.text,
                          ),
                        ),
                        const SizedBox(height: LsGap.section),
                        // ── Primary CTA — accent fill, dark inner arrow ──
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
                        // ── Numbered tile rows ───────────────────────────
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
                            data: (s) =>
                                s == null ? 'NONE YET' : 'PAST SESSIONS',
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
                        const SizedBox(height: LsGap.item),
                        _TileRow(
                          index: 5,
                          label: 'SETTINGS',
                          meta: 'UNIT · ACCENT · LIVE ACTIVITY',
                          onTap: () => context.push('/settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Last-session strip pinned to bottom ──────────────────
              _LastSessionFooter(summary: lastSession.value, unit: unit),
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
                child: Icon(
                  Icons.arrow_forward,
                  color: t.accent.accentInk,
                  size: 26,
                ),
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

/// Height of the soft fade zone at each end of the home scroll region. Also
/// used as the scroll view's internal vertical padding, so at rest the hero
/// (top) and the last tile (bottom) sit clear of the fade and render fully
/// crisp — content only dissolves once it's actually scrolled into the edge.
const double _kEdgeFade = 28;

/// Builds the alpha gradient consumed by the home [ShaderMask] (with
/// [BlendMode.dstIn], the gradient's alpha multiplies the content's own
/// alpha). Opaque white through the middle keeps the body fully visible;
/// the top and bottom `_kEdgeFade` ramp to transparent so content fades
/// into the background as it reaches the header / last-session strip.
///
/// Stops are computed from the live layout height so the ramp is always
/// exactly `_kEdgeFade` logical pixels regardless of screen size.
Shader _edgeFadeShader(Rect bounds) {
  final double h = bounds.height;
  // Guard against a degenerate ramp on very short layouts.
  final double f = (_kEdgeFade / h).clamp(0.0, 0.5);
  return ui.Gradient.linear(
    Offset(0, bounds.top),
    Offset(0, bounds.bottom),
    const [
      Color(0x00FFFFFF), // top edge — fully transparent
      Color(0xFFFFFFFF), // body — fully opaque
      Color(0xFFFFFFFF),
      Color(0x00FFFFFF), // bottom edge — fully transparent
    ],
    [0.0, f, 1.0 - f, 1.0],
  );
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
