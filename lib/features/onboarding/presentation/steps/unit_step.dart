import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/settings/settings_repository.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spec.dart';
import '../../../../core/widgets/layout.dart';
import '../onboarding_fx.dart';

/// A plausible working weight per unit — the number you'd actually load, not a
/// literal 100→220.46 conversion. Sells the unit better than the math.
int _previewValue(WeightUnit u) => u == WeightUnit.kg ? 100 : 225;

/// Step 3 — fold the old standalone unit screen into the wizard, made lively by
/// a big preview numeral that counts up on entry and *rolls* between values as
/// the unit toggles. kg is preselected so the CTA is never dead.
class UnitStep extends StatefulWidget {
  const UnitStep({
    super.key,
    required this.isActive,
    required this.unit,
    required this.onChanged,
  });
  final bool isActive;
  final WeightUnit unit;
  final ValueChanged<WeightUnit> onChanged;

  @override
  State<UnitStep> createState() => _UnitStepState();
}

class _UnitStepState extends State<UnitStep>
    with TickerProviderStateMixin, StepEntrance<UnitStep> {
  @override
  bool get isActive => widget.isActive;

  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _breathe.stop();
    } else if (!_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  void _select(WeightUnit u) {
    if (u == widget.unit) return;
    HapticFeedback.selectionClick();
    widget.onChanged(u);
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final rm = reduceMotionOf(context);
    final value = _previewValue(widget.unit);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Reveal(
                animation: entrance,
                start: 0.0,
                end: 0.22,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 16, height: 2, color: t.accent.accent),
                    const SizedBox(width: 10),
                    Text('UNITS',
                        style:
                            LsType.monoMeta.copyWith(color: t.surface.text2)),
                  ],
                ),
              ),
              const SizedBox(height: LsGap.sub),
              for (final (i, line) in const ['PICK YOUR', 'UNIT.'].indexed)
                Reveal(
                  animation: entrance,
                  start: 0.06 + i * 0.07,
                  end: 0.30 + i * 0.07,
                  child: Text(line, style: onbHeadline(t)),
                ),
            ],
          ),
          const SizedBox(height: LsGap.sub),
          Reveal(
            animation: entrance,
            start: 0.26,
            end: 0.46,
            child: Text(
              'You can change this later in settings.',
              style: LsType.bodyM.copyWith(color: t.surface.text2),
            ),
          ),
          const Spacer(),
          Reveal(
            animation: entrance,
            start: 0.30,
            end: 0.52,
            dy: 18,
            child: _PreviewNumeral(
              value: value,
              unit: widget.unit,
              active: widget.isActive,
              reduceMotion: rm,
              breathe: _breathe,
            ),
          ),
          const Spacer(),
          Reveal(
            animation: entrance,
            start: 0.40,
            end: 0.58,
            child: Row(
              children: [
                Expanded(
                  child: LsChoiceChip(
                    label: 'KILOGRAMS',
                    selected: widget.unit == WeightUnit.kg,
                    onTap: () => _select(WeightUnit.kg),
                    height: 60,
                  ),
                ),
                const SizedBox(width: LsGap.inline),
                Expanded(
                  child: LsChoiceChip(
                    label: 'POUNDS',
                    selected: widget.unit == WeightUnit.lb,
                    onTap: () => _select(WeightUnit.lb),
                    height: 60,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _PreviewNumeral extends StatelessWidget {
  const _PreviewNumeral({
    required this.value,
    required this.unit,
    required this.active,
    required this.reduceMotion,
    required this.breathe,
  });
  final int value;
  final WeightUnit unit;
  final bool active;
  final bool reduceMotion;
  final Animation<double> breathe;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final target = active ? value.toDouble() : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            reduceMotion
                ? Text(
                    '$value',
                    style: _numeralStyle(t),
                  )
                : TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: target),
                    duration: const Duration(milliseconds: 460),
                    curve: LsMotion.slowCurve,
                    builder: (context, v, _) =>
                        Text(v.round().toString(), style: _numeralStyle(t)),
                  ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: LsMotion.fast,
              child: Text(
                unit.short.toUpperCase(),
                key: ValueKey(unit),
                style: LsType.displayM.copyWith(
                  color: t.accent.accent,
                  fontSize: 28,
                ),
              ),
            ),
          ],
          ),
        ),
        const SizedBox(height: 10),
        // Breathing underline — keeps the step alive without pulling focus.
        AnimatedBuilder(
          animation: breathe,
          builder: (context, _) => Container(
            width: 120,
            height: 2,
            color: t.accent.accent.withValues(
              alpha: reduceMotion ? 0.5 : 0.3 + breathe.value * 0.3,
            ),
          ),
        ),
      ],
    );
  }

  TextStyle _numeralStyle(LsTheme t) => TextStyle(
        fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.w600,
        fontSize: 72,
        height: 1.0,
        color: t.surface.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
