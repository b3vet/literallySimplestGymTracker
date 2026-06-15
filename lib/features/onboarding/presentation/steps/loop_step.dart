import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spec.dart';
import '../onboarding_fx.dart';

class _Node {
  const _Node(this.index, this.name, this.caption);
  final String index;
  final String name;
  final String caption;
}

// The repeating session cycle — these run on loop every workout. The PROGRAM
// is built ONCE up front and is deliberately NOT part of this list, so the
// "on repeat" framing is honest.
const _cycle = <_Node>[
  _Node('01', 'START', 'PICK A DAY'),
  _Node('02', 'LOG SET', 'SCROLL · LOG'),
  _Node('03', 'REST', 'TIMER RUNS'),
  _Node('04', 'REPEAT', 'NEXT SET, NEXT DAY'),
];

/// Step 1 — the mental model, taught in motion. A one-time PROGRAM setup sits
/// apart at the top; below it the per-session cycle (start → log → rest →
/// repeat) loops, with a "current" pulse sweeping the rail forever.
class LoopStep extends StatefulWidget {
  const LoopStep({super.key, required this.isActive});
  final bool isActive;

  @override
  State<LoopStep> createState() => _LoopStepState();
}

class _LoopStepState extends State<LoopStep>
    with TickerProviderStateMixin, StepEntrance<LoopStep> {
  @override
  bool get isActive => widget.isActive;

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient pulse is OFF under reduce-motion.
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Reveal(
                animation: entrance,
                start: 0.0,
                end: 0.24,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 16, height: 2, color: t.accent.accent),
                    const SizedBox(width: 10),
                    Text('THE LOOP',
                        style:
                            LsType.monoMeta.copyWith(color: t.surface.text2)),
                  ],
                ),
              ),
              const SizedBox(height: LsGap.sub),
              for (final (i, line) in const ['BUILD ONCE.', 'THEN REPEAT.'].indexed)
                Reveal(
                  animation: entrance,
                  start: 0.04 + i * 0.06,
                  end: 0.26 + i * 0.06,
                  child: Text(line, style: onbHeadline(t)),
                ),
            ],
          ),
          const SizedBox(height: LsGap.loose),
          // One-time setup, set apart from the loop.
          Reveal(
            animation: entrance,
            start: 0.14,
            end: 0.38,
            dy: 16,
            child: const _SetupCard(),
          ),
          const SizedBox(height: LsGap.sub),
          Reveal(
            animation: entrance,
            start: 0.20,
            end: 0.42,
            child: Row(
              children: [
                Icon(Icons.arrow_downward, size: 13, color: t.surface.text3),
                const SizedBox(width: 8),
                Text(
                  'THEN, EVERY SESSION',
                  style: LsType.monoMicro.copyWith(color: t.surface.text3),
                ),
              ],
            ),
          ),
          const SizedBox(height: LsGap.sub),
          // The repeating cycle — rail + pulse loop over these only.
          Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 22,
                child: _Rail(entrance: entrance, loop: _loop, rm: rm),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Column(
                  children: [
                    for (var i = 0; i < _cycle.length; i++) ...[
                      if (i > 0) const SizedBox(height: LsGap.tight),
                      Reveal(
                        animation: entrance,
                        start: (0.24 + i * 0.06).clamp(0.0, 1.0),
                        end: (0.46 + i * 0.06).clamp(0.0, 1.0),
                        dy: 16,
                        child: _CycleCard(
                          node: _cycle[i],
                          position: i,
                          loop: _loop,
                          rm: rm,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

/// The one-time "build your program" foundation card — visually distinct from
/// the looping cycle (accent-tinted, no rail, an explicit ONCE tag).
class _SetupCard extends StatelessWidget {
  const _SetupCard();

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.accentDimBg,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        border: Border.all(color: t.accent.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accent.accent,
              borderRadius: BorderRadius.circular(LsRadius.r2),
            ),
            child: Icon(Icons.dashboard_customize_outlined,
                size: 18, color: t.accent.accentInk),
          ),
          const SizedBox(width: LsGap.inline),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PROGRAM',
                    style: LsType.displayS
                        .copyWith(color: t.surface.text, fontSize: 22)),
                const SizedBox(height: 3),
                Text('BUILD YOUR DAYS ONCE',
                    style:
                        LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.accent.accent,
              borderRadius: BorderRadius.circular(LsRadius.r1),
            ),
            child: Text('ONCE',
                style: LsType.monoMicro.copyWith(
                  color: t.accent.accentInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.entrance, required this.loop, required this.rm});
  final Animation<double> entrance;
  final Animation<double> loop;
  final bool rm;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final draw = CurvedAnimation(
      parent: entrance,
      curve: const Interval(0.22, 0.52, curve: Curves.easeOutCubic),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        return AnimatedBuilder(
          animation: Listenable.merge([draw, loop]),
          builder: (context, _) {
            final drawn = rm ? 1.0 : draw.value;
            return Stack(
              children: [
                // Faint full track.
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: t.surface.border),
                ),
                // Accent rail, drawn top→bottom.
                Positioned(
                  left: 10,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: h * drawn,
                    color: t.accent.accent.withValues(alpha: 0.55),
                  ),
                ),
                // Travelling current pulse — wraps bottom→top = "on repeat".
                if (!rm && drawn > 0.98)
                  Positioned(
                    left: 9,
                    top: (loop.value * (h - 26)).clamp(0.0, h),
                    child: Container(
                      width: 4,
                      height: 26,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            t.accent.accent.withValues(alpha: 0),
                            t.accent.accentHi,
                            t.accent.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CycleCard extends StatelessWidget {
  const _CycleCard({
    required this.node,
    required this.position,
    required this.loop,
    required this.rm,
  });
  final _Node node;
  final int position;
  final Animation<double> loop;
  final bool rm;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final isRepeat = position == _cycle.length - 1;
    return AnimatedBuilder(
      animation: loop,
      builder: (context, _) {
        // Glow peaks as the pulse crosses this node's vertical centre.
        final centre = (position + 0.5) / _cycle.length;
        final dist = (loop.value - centre).abs();
        final glow = rm ? 0.0 : (1 - (dist * _cycle.length).clamp(0.0, 1.0));

        final squareColor =
            Color.lerp(t.surface.surface2, t.accent.accent, glow * 0.9)!;
        final digitColor =
            Color.lerp(t.surface.text2, t.accent.accentInk, glow)!;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: t.surface.surface,
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(
              color: Color.lerp(t.surface.border, t.accent.accent, glow)!,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: squareColor,
                  borderRadius: BorderRadius.circular(LsRadius.r2),
                ),
                child: isRepeat
                    ? Icon(Icons.refresh, size: 18, color: digitColor)
                    : Text(
                        node.index,
                        style: LsType.monoMeta.copyWith(
                          color: digitColor,
                          fontSize: 13,
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
                      node.name,
                      style: LsType.displayS.copyWith(
                        color: t.surface.text,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      node.caption,
                      style: LsType.monoMeta.copyWith(
                        color: t.surface.text3,
                        fontSize: 11,
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
}
