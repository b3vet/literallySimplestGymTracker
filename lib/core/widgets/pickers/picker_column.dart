import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../settings/settings_repository.dart';
import '../../theme/app_theme.dart';
import '../layout.dart';

/// Restyled CupertinoPicker column. Numbers render in **Antonio** display
/// (matching the standalone-HTML design — chunky condensed glyphs), not
/// JetBrains Mono. Selected items render at 42px display, the rows above
/// and below dim to 22px so the column has a clear focal point.
///
/// Selection band is a tall accent-tinted rectangle in the middle of the
/// column. That band IS the indicator (no stroke, no checkmark).
class PickerColumn extends StatelessWidget {
  const PickerColumn({
    super.key,
    required this.label,
    required this.controller,
    required this.itemCount,
    required this.builder,
    required this.onChanged,
    this.itemExtent = 56,
    this.unitSuffix,
  });

  final String label;
  final FixedExtentScrollController controller;
  final int itemCount;
  final Widget Function(int index, bool selected) builder;
  final ValueChanged<int> onChanged;
  final double itemExtent;
  final String? unitSuffix;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label.toUpperCase(),
                style: LsType.monoMicro.copyWith(color: t.surface.text3),
              ),
              if (unitSuffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  '· ${unitSuffix!.toUpperCase()}',
                  style: LsType.monoMicro.copyWith(color: t.surface.text3),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: CupertinoPicker.builder(
            scrollController: controller,
            itemExtent: itemExtent,
            useMagnifier: false,
            squeeze: 1.0,
            backgroundColor: Colors.transparent,
            selectionOverlay: _SelectionBand(
              color: t.accentDimBg,
              borderColor: t.accent.accent.withValues(alpha: 0.7),
            ),
            onSelectedItemChanged: (i) {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
            childCount: itemCount,
            itemBuilder: (context, i) {
              final selected = i == controller.selectedItem;
              return Center(child: builder(i, selected));
            },
          ),
        ),
      ],
    );
  }
}

/// Custom selection band replacement (the default CupertinoPicker draws thin
/// hairlines top + bottom; we want a filled accent rectangle instead).
class _SelectionBand extends StatelessWidget {
  const _SelectionBand({required this.color, required this.borderColor});
  final Color color;
  final Color borderColor;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(LsRadius.r3),
          border: Border.all(color: borderColor, width: 1.4),
        ),
      ),
    );
  }
}

/// Standard text item for [PickerColumn]. The selected item renders large
/// (Antonio display, 40px, accent fill); adjacent items render half-size in
/// `text3` so the wheel has a clear focal point.
class PickerText extends StatelessWidget {
  const PickerText(this.text, {super.key, this.selected = false, this.accent = true});
  final String text;
  final bool selected;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final color = selected
        ? (accent ? t.accent.accent : t.surface.text)
        : t.surface.text3;
    final style = selected
        ? TextStyle(
            fontFamily: 'Antonio',
            fontWeight: FontWeight.w700,
            fontSize: 40,
            height: 1.0,
            letterSpacing: -0.4,
            color: color,
          )
        : TextStyle(
            fontFamily: 'Antonio',
            fontWeight: FontWeight.w400,
            fontSize: 22,
            height: 1.0,
            color: color,
          );
    return Text(text, style: style);
  }
}

/// Toggle for the weight step (kg: 0.5/1.0/2.5, lb: 1.0/2.5/5.0).
///
/// Used inside the exercise-editor sheet where the step is per-exercise.
/// Set the [labelOverride] if the parent wants its own caption (the editor
/// renders an "WEIGHT STEP" eyebrow above and reuses this row purely as the
/// chip control).
class WeightStepToggle extends StatelessWidget {
  const WeightStepToggle({
    super.key,
    required this.unit,
    required this.current,
    required this.onChanged,
  });

  final WeightUnit unit;
  final double current;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = unit == WeightUnit.kg
        ? const [0.5, 1.0, 2.5]
        : const [1.0, 2.5, 5.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: LsChoiceChip(
              label: '${_fmt(options[i])} ${unit.short}',
              selected: current == options[i],
              onTap: () => onChanged(options[i]),
              height: 50,
            ),
          ),
        ],
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
