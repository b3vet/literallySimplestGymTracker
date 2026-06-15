import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spec.dart';
import '../onboarding_fx.dart';

/// Step 0 — "what it is". The instrument boots up: the LS monogram fills, a
/// power-on rule wipes across and keeps a scanner dot sweeping, and the
/// headline slams in line by line.
class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key, required this.isActive});
  final bool isActive;

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep>
    with TickerProviderStateMixin, StepEntrance<WelcomeStep> {
  @override
  bool get isActive => widget.isActive;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 3),
          Reveal(
            animation: entrance,
            start: 0.08,
            end: 0.30,
            child: _BrandRow(intro: entrance),
          ),
          const SizedBox(height: 30),
          PowerRule(intro: entrance, start: 0.04, end: 0.34),
          const SizedBox(height: 30),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Reveal(
                animation: entrance,
                start: 0.14,
                end: 0.36,
                child: _eyebrow(t),
              ),
              const SizedBox(height: LsGap.sub),
              for (final (i, line) in const ['A PRECISION', 'INSTRUMENT', 'FOR LIFTING.'].indexed)
                Reveal(
                  animation: entrance,
                  start: 0.18 + i * 0.07,
                  end: 0.42 + i * 0.07,
                  dy: 18,
                  child: Text(
                    line,
                    textAlign: TextAlign.right,
                    style: onbHeadline(t),
                  ),
                ),
              const SizedBox(height: LsGap.section),
              Reveal(
                animation: entrance,
                start: 0.42,
                end: 0.62,
                child: SizedBox(
                  width: 280,
                  child: Text(
                    'Build a program. Log every set clean. '
                    'Watch the numbers climb.',
                    textAlign: TextAlign.right,
                    style: LsType.bodyM.copyWith(color: t.surface.text2),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(flex: 4),
        ],
      ),
    );
  }

  Widget _eyebrow(LsTheme t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 16, height: 2, color: t.accent.accent),
          const SizedBox(width: 10),
          Text(
            'GET STARTED',
            style: LsType.monoMeta.copyWith(color: t.surface.text2),
          ),
        ],
      );
}

/// LS monogram (fills with accent on entry) + GYM TRACKER caption.
class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.intro});
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final fill = CurvedAnimation(
      parent: intro,
      curve: const Interval(0.12, 0.40, curve: Curves.easeOutCubic),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: fill,
          builder: (context, _) => FillWipe(
            t: reduceMotionOf(context) ? 1 : fill.value,
            fill: t.accent.accent,
            outline: t.accent.accent.withValues(alpha: 0.6),
            size: LsBox.brandLs,
            radius: LsRadius.r3,
            child: Text(
              'LS',
              style: TextStyle(
                fontFamily: 'Antonio',
                fontWeight: FontWeight.w700,
                fontSize: LsBox.brandLsLabel,
                letterSpacing: 0.6,
                height: 1.0,
                color: t.accent.accentInk,
              ),
            ),
          ),
        ),
        const SizedBox(width: LsGap.inline),
        Text(
          'GYM TRACKER',
          style: LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 14),
        ),
      ],
    );
  }
}

/// A 2px accent "power-on" rule that wipes in left→right, settles to a faint
/// hairline, then keeps a scanner dot sweeping along it forever. Reduce-motion:
/// a static hairline, no dot.
class PowerRule extends StatefulWidget {
  const PowerRule({
    super.key,
    required this.intro,
    required this.start,
    required this.end,
  });
  final Animation<double> intro;
  final double start;
  final double end;

  @override
  State<PowerRule> createState() => _PowerRuleState();
}

class _PowerRuleState extends State<PowerRule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient loops are OFF under reduce-motion (and gating them this way also
    // keeps widget tests from hanging on a never-idle binding).
    if (reduceMotionOf(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final rm = reduceMotionOf(context);
    final wipe = CurvedAnimation(
      parent: widget.intro,
      curve: Interval(widget.start, widget.end, curve: Curves.easeOutCubic),
    );
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, c) {
          return AnimatedBuilder(
            animation: Listenable.merge([wipe, _loop]),
            builder: (context, _) {
              final w = rm ? 1.0 : wipe.value;
              final lineColor =
                  Color.lerp(t.accent.accent, t.surface.border, w)!;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: w,
                    child: Container(height: 2, color: lineColor),
                  ),
                  if (!rm && w > 0.98)
                    Positioned(
                      left: _loop.value * (c.maxWidth - 6),
                      top: 1,
                      child: Opacity(
                        opacity: math.sin(_loop.value * math.pi) * 0.8,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: t.accent.accent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
