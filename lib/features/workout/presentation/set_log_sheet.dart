import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../domain/active_session.dart';

class SetLogResult {
  const SetLogResult({
    required this.reps,
    required this.weightKg,
    required this.rir,
  });
  final int reps;
  final double weightKg;
  final int rir;
}

Future<SetLogResult?> showSetLogSheet(
  BuildContext context, {
  required PlannedExercise exercise,
  required int setNumber,
  required int? initialReps,
  required double? initialWeightKg,
  int initialRir = 0,
  String titleOverride = '',
}) {
  return showModalBottomSheet<SetLogResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.elevated,
    builder: (ctx) => _SetLogSheet(
      exercise: exercise,
      setNumber: setNumber,
      initialReps: initialReps,
      initialWeightKg: initialWeightKg,
      initialRir: initialRir,
      titleOverride: titleOverride,
    ),
  );
}

class _SetLogSheet extends ConsumerStatefulWidget {
  const _SetLogSheet({
    required this.exercise,
    required this.setNumber,
    required this.initialReps,
    required this.initialWeightKg,
    required this.initialRir,
    required this.titleOverride,
  });
  final PlannedExercise exercise;
  final int setNumber;
  final int? initialReps;
  final double? initialWeightKg;
  final int initialRir;
  final String titleOverride;

  @override
  ConsumerState<_SetLogSheet> createState() => _SetLogSheetState();
}

class _SetLogSheetState extends ConsumerState<_SetLogSheet> {
  static const int _repsMin = 1;
  static const int _repsMax = 50;
  static const int _rirMax = 10;

  // Picker value range for weight lives in the user's unit.
  double _weightRangeMax(WeightUnit unit) =>
      unit == WeightUnit.kg ? 300.0 : 660.0;

  late int _reps;
  late int _rir;
  // Weight picker state is indexed, driven by step.
  late double _weightDisplay; // value in user's unit
  late double _weightStep; // in user's unit

  final _repsCtrl = FixedExtentScrollController();
  final _weightCtrl = FixedExtentScrollController();
  final _rirCtrl = FixedExtentScrollController();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    final unit = settings.unit ?? WeightUnit.kg;

    final defaultReps =
        widget.initialReps ??
            ((widget.exercise.targetRepsMin + widget.exercise.targetRepsMax) ~/ 2);
    _reps = defaultReps.clamp(_repsMin, _repsMax);
    _rir = widget.initialRir.clamp(0, _rirMax);

    final defaultKg =
        widget.initialWeightKg ?? widget.exercise.defaultWeightKg;
    _weightStep = settings.weightStep > 0 ? settings.weightStep : unit.defaultStep;
    // Snap default to nearest step.
    final raw = WeightConv.fromKg(defaultKg, unit);
    _weightDisplay = (raw / _weightStep).round() * _weightStep;
    _weightDisplay = _weightDisplay.clamp(0, _weightRangeMax(unit));

    // Schedule jumpToItem after the first layout — these controllers need attachment.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repsCtrl.jumpToItem(_reps - _repsMin);
      _rirCtrl.jumpToItem(_rir);
      _weightCtrl.jumpToItem((_weightDisplay / _weightStep).round());
    });
  }

  @override
  void dispose() {
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    _rirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final weightCount = (_weightRangeMax(unit) / _weightStep).round() + 1;

    final title = widget.titleOverride.isNotEmpty
        ? widget.titleOverride
        : '${widget.exercise.exerciseName} · Set ${widget.setNumber}';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(title,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: Row(
                children: [
                  Expanded(
                    flex: 25,
                    child: _PickerColumn(
                      label: 'REPS',
                      controller: _repsCtrl,
                      itemCount: _repsMax - _repsMin + 1,
                      builder: (i) => _PickerText('${i + _repsMin}'),
                      onChanged: (i) {
                        setState(() => _reps = i + _repsMin);
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                  Expanded(
                    flex: 45,
                    child: _PickerColumn(
                      label: 'WEIGHT (${unit.short})',
                      controller: _weightCtrl,
                      itemCount: weightCount,
                      builder: (i) => _PickerText(
                        _formatWeightLabel(i * _weightStep, unit),
                      ),
                      onChanged: (i) {
                        setState(() => _weightDisplay = i * _weightStep);
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                  Expanded(
                    flex: 25,
                    child: _PickerColumn(
                      label: 'RIR',
                      controller: _rirCtrl,
                      itemCount: _rirMax + 1,
                      builder: (i) => _PickerText('$i'),
                      onChanged: (i) {
                        setState(() => _rir = i);
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _StepToggle(
              unit: unit,
              current: _weightStep,
              onChanged: (s) async {
                final oldIdx = (_weightDisplay / _weightStep).round();
                final oldValue = oldIdx * _weightStep;
                setState(() {
                  _weightStep = s;
                  _weightDisplay =
                      (oldValue / _weightStep).round() * _weightStep;
                });
                await ref.read(settingsProvider.notifier).setWeightStep(s);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _weightCtrl.jumpToItem(
                    (_weightDisplay / _weightStep).round(),
                  );
                });
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('SAVE SET'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _formatWeightLabel(double valueInUnit, WeightUnit unit) {
    if (unit == WeightUnit.kg) {
      return valueInUnit == valueInUnit.roundToDouble()
          ? valueInUnit.toStringAsFixed(0)
          : valueInUnit.toStringAsFixed(1);
    }
    return valueInUnit == valueInUnit.roundToDouble()
        ? valueInUnit.toStringAsFixed(0)
        : valueInUnit.toStringAsFixed(1);
  }

  void _save() {
    HapticFeedback.mediumImpact();
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    Navigator.pop(
      context,
      SetLogResult(
        reps: _reps,
        weightKg: WeightConv.toKg(_weightDisplay, unit),
        rir: _rir,
      ),
    );
  }
}

class _PickerColumn extends StatelessWidget {
  const _PickerColumn({
    required this.label,
    required this.controller,
    required this.itemCount,
    required this.builder,
    required this.onChanged,
  });
  final String label;
  final FixedExtentScrollController controller;
  final int itemCount;
  final Widget Function(int index) builder;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  )),
        ),
        Expanded(
          child: CupertinoPicker.builder(
            scrollController: controller,
            itemExtent: 48,
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

class _PickerText extends StatelessWidget {
  const _PickerText(this.text);
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

class _StepToggle extends StatelessWidget {
  const _StepToggle({
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
        ? const [0.5, 1.0]
        : const [1.0, 2.5];
    return SegmentedButton<double>(
      segments: [
        for (final o in options)
          ButtonSegment(
            value: o,
            label: Text('${o == o.roundToDouble() ? o.toStringAsFixed(0) : o} ${unit.short}'),
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
