import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../onboarding_fx.dart';

/// The wizard's signature progress indicator: a barbell "sleeve" that loads one
/// accent plate per completed step, with a `STEP 0X / NN` mono readout above.
///
/// It persists across step changes (the host keeps it mounted) so progress
/// reads as moving *through one instrument*, not reloading six screens. Only
/// the freshly-loaded plate animates in; the numeral rolls.
class PlateProgressBar extends StatefulWidget {
  const PlateProgressBar({
    super.key,
    required this.step, // 1-based current step
    required this.total,
  });

  final int step;
  final int total;

  @override
  State<PlateProgressBar> createState() => _PlateProgressBarState();
}

class _PlateProgressBarState extends State<PlateProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    // The first plate is already loaded on arrival — show it settled, no pop.
    _pop.value = 1;
  }

  @override
  void didUpdateWidget(covariant PlateProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.step > old.step) {
      if (reduceMotionOf(context)) {
        _pop.value = 1;
      } else {
        _pop.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepNumeral(step: widget.step, total: widget.total),
        const SizedBox(height: 7),
        SizedBox(
          width: widget.total * 18.0,
          height: 12,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Bar / sleeve baseline.
              Container(
                height: 2,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: t.surface.borderStrong,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < widget.total; i++)
                    _Plate(
                      filled: i < widget.step,
                      isNewest: i == widget.step - 1,
                      pop: _pop,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({
    required this.filled,
    required this.isNewest,
    required this.pop,
  });
  final bool filled;
  final bool isNewest;
  final Animation<double> pop;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final plate = AnimatedContainer(
      duration: LsMotion.base,
      width: 12,
      height: 11,
      decoration: BoxDecoration(
        color: filled ? t.accent.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(LsRadius.r1),
        border: Border.all(
          color: filled ? t.accent.accent : t.surface.border,
          width: 1.2,
        ),
      ),
    );
    if (!filled || !isNewest) return plate;
    // Newest plate "clacks" on: scale 0.6 → 1.04 → 1.0.
    return AnimatedBuilder(
      animation: pop,
      child: plate,
      builder: (context, child) {
        final v = pop.value;
        // ease-out with a tiny overshoot near the end.
        final scale = v < 0.85
            ? 0.6 + (1.04 - 0.6) * (v / 0.85)
            : 1.04 - 0.04 * ((v - 0.85) / 0.15);
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

class _StepNumeral extends StatelessWidget {
  const _StepNumeral({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final style = LsType.monoMicro.copyWith(color: t.surface.text3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('STEP ', style: style),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => ClipRect(
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.7),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: anim, child: child),
            ),
          ),
          child: Text(
            step.toString().padLeft(2, '0'),
            key: ValueKey(step),
            style: style.copyWith(color: t.accent.accent),
          ),
        ),
        Text(' / ${total.toString().padLeft(2, '0')}', style: style),
      ],
    );
  }
}
