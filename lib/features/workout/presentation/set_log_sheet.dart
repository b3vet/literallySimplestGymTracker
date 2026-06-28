import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../../../core/widgets/pickers/picker_column.dart';
import '../domain/active_session.dart';
import '../domain/plate_math.dart';
import 'plate_line.dart';

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
  // Drop-set drops capture reps + weight only — hide the RIR wheel.
  bool showRir = true,
  String saveLabel = 'SAVE SET',
}) {
  return showModalBottomSheet<SetLogResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LsSheet(
      child: _SetLogSheet(
        exercise: exercise,
        setNumber: setNumber,
        initialReps: initialReps,
        initialWeightKg: initialWeightKg,
        initialRir: initialRir,
        titleOverride: titleOverride,
        showRir: showRir,
        saveLabel: saveLabel,
      ),
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
    required this.showRir,
    required this.saveLabel,
  });
  final PlannedExercise exercise;
  final int setNumber;
  final int? initialReps;
  final double? initialWeightKg;
  final int initialRir;
  final String titleOverride;
  final bool showRir;
  final String saveLabel;

  @override
  ConsumerState<_SetLogSheet> createState() => _SetLogSheetState();
}

class _SetLogSheetState extends ConsumerState<_SetLogSheet> {
  static const int _repsMin = 1;
  static const int _repsMax = 50;
  static const int _rirMax = 10;

  double _weightRangeMax(WeightUnit unit) =>
      unit == WeightUnit.kg ? 300.0 : 660.0;

  late int _reps;
  late int _rir;
  late double _weightDisplay;
  late double _weightStep;
  // Tracks the unit the wheel was last built against so we can detect
  // mid-sheet switches (rare, but the user CAN flip kg/lb in settings while
  // the sheet is open) and refit the picker.
  WeightUnit? _builtForUnit;

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

    final defaultKg = widget.initialWeightKg ?? widget.exercise.defaultWeightKg;
    // Per-exercise step (kg) wins; otherwise fall back to the unit default.
    final stepKg = widget.exercise.weightStepKg ?? WeightUnit.kg.defaultStep;
    _weightStep = _stepInUnit(stepKg, unit);
    _builtForUnit = unit;
    final raw = WeightConv.fromKg(defaultKg, unit);
    _weightDisplay = (raw / _weightStep).round() * _weightStep;
    _weightDisplay = _weightDisplay.clamp(0, _weightRangeMax(unit));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repsCtrl.jumpToItem(_reps - _repsMin);
      _rirCtrl.jumpToItem(_rir);
      _weightCtrl.jumpToItem((_weightDisplay / _weightStep).round());
    });
  }

  /// Convert a step stored in kg into the current display unit. Pounds use
  /// 1/2.5/5 — fall back to whichever unit-default is closest if the user
  /// originally configured a kg step but the display unit is lb.
  double _stepInUnit(double stepKg, WeightUnit unit) {
    if (unit == WeightUnit.kg) return stepKg;
    // Convert kg → lb, snap to the nearest sane lb step.
    final asLb = stepKg * 2.20462;
    if (asLb <= 1.25) return 1.0;
    if (asLb <= 3.75) return 2.5;
    return 5.0;
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
    final settings = ref.watch(settingsProvider);
    final unit = settings.unit ?? WeightUnit.kg;
    final weightCount = (_weightRangeMax(unit) / _weightStep).round() + 1;
    final t = LsTheme.of(context);

    // The wheel value is in the DISPLAY unit — convert to kg before solving so
    // the plate math (always kg) lines up with the bar + inventory (also kg).
    // Recomputes every build, i.e. synchronously inside the wheel's onChanged
    // setState — no async, no DB, no extra tap.
    final plateResult = solvePlates(
      targetKg: WeightConv.toKg(_weightDisplay, unit),
      barKg: settings.barWeightKg,
      inventoryKg: settings.plateInventoryKg,
    );

    // If the user flips the unit setting while the sheet is open, snap the
    // wheel step over so the picker stays in the same number-system.
    if (_builtForUnit != unit) {
      _builtForUnit = unit;
      // Re-derive a sane step in the new unit closest to the previous one.
      _weightStep = unit == WeightUnit.kg
          ? WeightUnit.kg.defaultStep
          : WeightUnit.lb.defaultStep;
      _weightDisplay =
          (_weightDisplay / _weightStep).round() * _weightStep;
      _weightDisplay = _weightDisplay.clamp(0.0, _weightRangeMax(unit));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _weightCtrl.jumpToItem((_weightDisplay / _weightStep).round());
        }
      });
    }

    final eyebrow = widget.titleOverride.isNotEmpty
        ? widget.titleOverride
        : 'SET ${widget.setNumber}';

    final repsTarget =
        widget.exercise.targetRepsMin == widget.exercise.targetRepsMax
        ? '${widget.exercise.targetRepsMin}'
        : '${widget.exercise.targetRepsMin}-${widget.exercise.targetRepsMax}';
    final weightTarget = WeightConv.format(
      widget.exercise.defaultWeightKg,
      unit,
    ).toUpperCase();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LsGap.sub),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: EyebrowLabel(eyebrow.toUpperCase())),
            Text(
              '$repsTarget · $weightTarget',
              style: LsType.monoMeta.copyWith(color: t.surface.text2),
            ),
          ],
        ),
        const SizedBox(height: LsGap.sub),
        // Per-set step cycler. Sometimes the lifter wants finer (0.5kg
        // micro-adjustments on dumbbells) or coarser (5kg jumps on a smith
        // bench machine) than the program default. Tap to cycle.
        Row(
          children: [
            const Spacer(),
            InlineWeightStepCycler(
              unit: unit,
              current: _weightStep,
              onChanged: (s) {
                setState(() {
                  final old = _weightDisplay;
                  _weightStep = s;
                  _weightDisplay =
                      (old / _weightStep).round() * _weightStep;
                  _weightDisplay =
                      _weightDisplay.clamp(0.0, _weightRangeMax(unit));
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _weightCtrl
                      .jumpToItem((_weightDisplay / _weightStep).round());
                });
              },
            ),
          ],
        ),
        const SizedBox(height: LsGap.section),
        SizedBox(
          height: 260,
          child: Row(
            children: [
              Expanded(
                flex: widget.showRir ? 25 : 35,
                child: PickerColumn(
                  label: 'REPS',
                  controller: _repsCtrl,
                  itemCount: _repsMax - _repsMin + 1,
                  builder: (i, sel) =>
                      PickerText('${i + _repsMin}', selected: sel),
                  onChanged: (i) {
                    setState(() => _reps = i + _repsMin);
                  },
                ),
              ),
              Expanded(
                flex: widget.showRir ? 45 : 65,
                child: PickerColumn(
                  label: 'WEIGHT',
                  unitSuffix: unit.short,
                  controller: _weightCtrl,
                  itemCount: weightCount,
                  builder: (i, sel) => PickerText(
                    _formatWeightLabel(i * _weightStep, unit),
                    selected: sel,
                  ),
                  onChanged: (i) {
                    setState(() => _weightDisplay = i * _weightStep);
                  },
                ),
              ),
              if (widget.showRir)
                Expanded(
                  flex: 25,
                  child: PickerColumn(
                    label: 'RIR',
                    controller: _rirCtrl,
                    itemCount: _rirMax + 1,
                    builder: (i, sel) => PickerText('$i', selected: sel),
                    onChanged: (i) {
                      setState(() => _rir = i);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: LsGap.section),
        // Passive per-side plate breakdown for the current wheel weight.
        // Read-only except the "BAR n" affordance, which opens the bar chooser.
        PlateLine(
          result: plateResult,
          unit: unit,
          onBarTap: () => showBarChooserSheet(context, ref, unit),
        ),
        const SizedBox(height: LsGap.loose),
        LsButton(
          label: widget.saveLabel,
          onPressed: _save,
          expand: true,
          minHeight: LsBox.cta,
        ),
      ],
    );
  }

  String _formatWeightLabel(double v, WeightUnit unit) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
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

/// The common-bar chooser. Shared by the set-logger's "BAR n" affordance and
/// the Settings "Default bar" row. Lists the three standard Olympic bars
/// (20 / 15 / 10 kg) labelled in the user's display [unit]; the chosen value is
/// always converted back to kg before being stored, since bar weight — like
/// every weight in the app — is persisted in kg.
Future<void> showBarChooserSheet(
  BuildContext context,
  WidgetRef ref,
  WeightUnit unit,
) {
  // Standard bar weights, in kg. The label is rendered in the display unit.
  const barsKg = <double>[20.0, 15.0, 10.0];
  final currentKg = ref.read(settingsProvider).barWeightKg;
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('Barbell weight'),
      actions: [
        for (final barKg in barsKg)
          CupertinoActionSheetAction(
            onPressed: () {
              ref.read(settingsProvider.notifier).setBarWeightKg(barKg);
              Navigator.pop(ctx);
            },
            child: Text(
              '${WeightConv.format(barKg, unit).toUpperCase()}'
              '${(barKg - currentKg).abs() < 1e-6 ? '  ✓' : ''}',
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}
