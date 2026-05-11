import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../settings/settings_repository.dart';
import '../../theme/app_theme.dart';

/// A labelled CupertinoPicker column used for reps / weight / RIR / sets etc.
///
/// `itemCount` items are rendered via `builder`. The picker reports the
/// selected index via `onChanged`. Pair with a [FixedExtentScrollController]
/// owned by the parent if you need to programmatically jump to an index.
class PickerColumn extends StatelessWidget {
  const PickerColumn({
    super.key,
    required this.label,
    required this.controller,
    required this.itemCount,
    required this.builder,
    required this.onChanged,
    this.itemExtent = 48,
  });

  final String label;
  final FixedExtentScrollController controller;
  final int itemCount;
  final Widget Function(int index) builder;
  final ValueChanged<int> onChanged;
  final double itemExtent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        Expanded(
          child: CupertinoPicker.builder(
            scrollController: controller,
            itemExtent: itemExtent,
            useMagnifier: true,
            magnification: 1.15,
            squeeze: 1.1,
            backgroundColor: AppColors.elevated,
            selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
              background: Color(0x1AFF5A1F),
            ),
            onSelectedItemChanged: onChanged,
            childCount: itemCount,
            itemBuilder: (context, i) => Center(child: builder(i)),
          ),
        ),
      ],
    );
  }
}

/// Standard 24sp picker text used by [PickerColumn] entries.
class PickerText extends StatelessWidget {
  const PickerText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// Toggle for the weight step (kg: 0.5/1.0, lb: 1.0/2.5).
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
    final options = unit == WeightUnit.kg ? const [0.5, 1.0] : const [1.0, 2.5];
    return SegmentedButton<double>(
      segments: [
        for (final o in options)
          ButtonSegment(
            value: o,
            label: Text(
              '${o == o.roundToDouble() ? o.toStringAsFixed(0) : o} ${unit.short}',
            ),
          ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.divider),
      ),
    );
  }
}
