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
          // Stack the band BEHIND the picker. We previously passed the band
          // as `CupertinoPicker.selectionOverlay`, which (as the name
          // implies) paints ON TOP of the selected item. In dark mode the
          // band's `accentDimBg` is a translucent overlay
          // (`accent.withOpacity(0.16)`) so the text bleeds through; in
          // light mode it's the OPAQUE `accentDimSolidLight` (a pale tint
          // designed for white surfaces) and it completely occludes the
          // selected item's text — looked like a z-order bug because
          // effectively it was one.
          //
          // Drawing the band first (under the picker) with a transparent
          // picker background and an empty selectionOverlay keeps the
          // visual identical to dark mode while letting the selected
          // item's text sit in front of the band in every theme.
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: itemExtent,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.accentDimBg,
                      borderRadius: BorderRadius.circular(LsRadius.r3),
                      border: Border.all(
                        color: t.accent.accent.withValues(alpha: 0.7),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              CupertinoPicker.builder(
                scrollController: controller,
                itemExtent: itemExtent,
                useMagnifier: false,
                squeeze: 1.0,
                backgroundColor: Colors.transparent,
                // No overlay — the band is provided by the Stack
                // underneath. SizedBox.shrink keeps Cupertino from
                // painting its default selection hairlines.
                selectionOverlay: const SizedBox.shrink(),
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
            ],
          ),
        ),
      ],
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
    // Contrast model:
    //   • Dark mode → selection band is `accent.withOpacity(0.16)` painted
    //     over a dark surface — looks like a dim tinted patch. Saturated
    //     accent text (e.g. amber #FFB400) reads cleanly against that.
    //   • Light mode → selection band is `accentDimSolidLight`, an opaque
    //     pastel tint (e.g. cream #FFEFC2). Saturated accent text on top
    //     would be "yellow on yellow / pink on pink / cyan on cyan" — not
    //     readable. We swap to a surface-grey instead. `surface.text` is
    //     pure near-black and grabs the eye too hard against a pale band;
    //     `surface.text2` (#4A5057) stays readable but lets the band
    //     remain the focal element, the way the dark-mode version does.
    final Color color;
    if (!selected) {
      color = t.surface.text3;
    } else if (!accent) {
      color = t.surface.text;
    } else {
      color = t.isLight ? t.surface.text2 : t.accent.accent;
    }
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

/// Available weight-step options per unit. Kept in one place so both the
/// per-program editor (`WeightStepToggle`) and the in-workout cycle button
/// (`InlineWeightStepCycler`) iterate the same sequence — and the user only
/// ever sees a single, predictable list.
///
/// `5.0` for kg was added later so users can crank quickly on machines with
/// big plates (smith bench, leg press). Going through the wheel one 2.5kg
/// click at a time when you want +20kg gets old fast.
const List<double> kKgStepOptions = [0.5, 1.0, 2.5, 5.0];
const List<double> kLbStepOptions = [1.0, 2.5, 5.0];

List<double> stepOptionsFor(WeightUnit unit) =>
    unit == WeightUnit.kg ? kKgStepOptions : kLbStepOptions;

/// Toggle for the weight step. Used inside the exercise-editor sheet where
/// the step is per-exercise. The editor renders an "WEIGHT STEP" eyebrow
/// above and reuses this row purely as the chip control.
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
    final options = stepOptionsFor(unit);
    // LayoutBuilder + Wrap so the row collapses on narrow sheets. A selected
    // chip includes a checkmark icon + 8pt spacing, which pushes the
    // intrinsic width well past 100pt for "0.5 KG". Empirically, anything
    // narrower than ~110pt overflows. Use that as the threshold for
    // splitting into two rows.
    return LayoutBuilder(
      builder: (ctx, c) {
        const spacing = 10.0;
        const minWidthSingleRow = 110.0;
        final w = c.maxWidth;
        int perRow = options.length;
        var chipW = (w - spacing * (perRow - 1)) / perRow;
        if (chipW < minWidthSingleRow && options.length >= 4) {
          // Split 4 options into 2x2 — guarantees ≥ (w-10)/2 ≈ 170pt per
          // chip on any phone we care about.
          perRow = 2;
          chipW = (w - spacing) / 2;
        }
        final rows = <List<int>>[];
        for (var i = 0; i < options.length; i += perRow) {
          rows.add(List<int>.generate(
            (i + perRow).clamp(0, options.length) - i,
            (k) => i + k,
          ));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: spacing),
              Row(
                children: [
                  for (var k = 0; k < rows[r].length; k++) ...[
                    if (k > 0) const SizedBox(width: spacing),
                    SizedBox(
                      width: chipW,
                      child: LsChoiceChip(
                        label:
                            '${fmtStep(options[rows[r][k]])} ${unit.short}',
                        selected: current == options[rows[r][k]],
                        onTap: () => onChanged(options[rows[r][k]]),
                        height: 50,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  static String fmtStep(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// Compact step cycler used inside the set-log sheet so the lifter can
/// switch to a finer/coarser step mid-workout (e.g. moved from a smith
/// machine to dumbbells). Per-set/per-session only — never writes back to
/// the program. Tapping cycles to the next option; long-press would be
/// noise on a quick log flow, so we stick to single-tap.
class InlineWeightStepCycler extends StatelessWidget {
  const InlineWeightStepCycler({
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
    final t = LsTheme.of(context);
    final options = stepOptionsFor(unit);
    // Snap `current` to the nearest known step so the next-click always
    // lands on a valid neighbor (handles edge case where a per-exercise
    // step from the program isn't in the option list).
    var idx = options.indexOf(current);
    if (idx < 0) {
      var best = 0;
      var bestDelta = double.infinity;
      for (var i = 0; i < options.length; i++) {
        final d = (options[i] - current).abs();
        if (d < bestDelta) {
          bestDelta = d;
          best = i;
        }
      }
      idx = best;
    }
    return Material(
      color: t.surface.surface2,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: () {
          final next = options[(idx + 1) % options.length];
          onChanged(next);
        },
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: t.surface.borderStrong),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'STEP',
                style: LsType.monoMicro.copyWith(color: t.surface.text3),
              ),
              const SizedBox(width: 6),
              Text(
                '${WeightStepToggle.fmtStep(options[idx])} ${unit.short}',
                style: LsType.monoMeta.copyWith(
                  color: t.accent.accent,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_right,
                  size: 14, color: t.surface.text3),
            ],
          ),
        ),
      ),
    );
  }
}
