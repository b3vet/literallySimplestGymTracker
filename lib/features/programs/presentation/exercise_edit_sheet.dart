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
import '../../workout/application/active_workout_controller.dart';
import '../application/programs_provider.dart';
import '../data/exercises_seed.dart';

class ExerciseEditResult {
  ExerciseEditResult({
    required this.name,
    required this.sets,
    required this.repsMin,
    required this.repsMax,
    required this.weightKg,
    required this.weightStepKg,
    this.delete = false,
  });
  final String name;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double weightKg;

  /// Per-exercise weight step in **kg**, persisted on the ProgramExercise.
  final double weightStepKg;
  final bool delete;
}

Future<ExerciseEditResult?> showExerciseEditSheet(
  BuildContext context, {
  required WeightUnit unit,
  required String initialName,
  required int initialSets,
  required int initialRepsMin,
  required int initialRepsMax,
  required double initialWeightKg,
  required double? initialWeightStepKg,
  bool canDelete = false,
}) {
  return showModalBottomSheet<ExerciseEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LsSheet(
      child: _ExerciseEditSheet(
        unit: unit,
        initialName: initialName,
        initialSets: initialSets,
        initialRepsMin: initialRepsMin,
        initialRepsMax: initialRepsMax,
        initialWeightKg: initialWeightKg,
        initialWeightStepKg: initialWeightStepKg,
        canDelete: canDelete,
      ),
    ),
  );
}

class _ExerciseEditSheet extends ConsumerStatefulWidget {
  const _ExerciseEditSheet({
    required this.unit,
    required this.initialName,
    required this.initialSets,
    required this.initialRepsMin,
    required this.initialRepsMax,
    required this.initialWeightKg,
    required this.initialWeightStepKg,
    required this.canDelete,
  });
  final WeightUnit unit;
  final String initialName;
  final int initialSets;
  final int initialRepsMin;
  final int initialRepsMax;
  final double initialWeightKg;
  final double? initialWeightStepKg;
  final bool canDelete;

  @override
  ConsumerState<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends ConsumerState<_ExerciseEditSheet> {
  static const int _setsMin = 1;
  static const int _setsMax = 10;
  static const int _repsMin = 1;
  static const int _repsMax = 50;

  double _weightRangeMax(WeightUnit unit) =>
      unit == WeightUnit.kg ? 300.0 : 660.0;

  late int _sets;
  late int _repsMinVal;
  late int _repsMaxVal;
  late double _weightDisplay;
  late double _weightStep;

  late final TextEditingController _name;
  final FocusNode _nameFocus = FocusNode();
  String? _lastAutofilledFor;

  final _setsCtrl = FixedExtentScrollController();
  final _repsMinCtrl = FixedExtentScrollController();
  final _repsMaxCtrl = FixedExtentScrollController();
  final _weightCtrl = FixedExtentScrollController();

  bool _userTouchedSets = false;
  bool _userTouchedRepsMin = false;
  bool _userTouchedRepsMax = false;
  bool _userTouchedWeight = false;

  @override
  void initState() {
    super.initState();
    // Per-exercise step in display units. NULL initial → unit default.
    _weightStep = widget.initialWeightStepKg ?? widget.unit.defaultStep;
    if (widget.unit == WeightUnit.lb && widget.initialWeightStepKg != null) {
      // Convert kg-stored step to nearest lb step.
      final asLb = widget.initialWeightStepKg! * 2.20462;
      if (asLb <= 1.25) {
        _weightStep = 1.0;
      } else if (asLb <= 3.75) {
        _weightStep = 2.5;
      } else {
        _weightStep = 5.0;
      }
    }

    _sets = widget.initialSets.clamp(_setsMin, _setsMax);
    _repsMinVal = widget.initialRepsMin.clamp(_repsMin, _repsMax);
    _repsMaxVal = widget.initialRepsMax.clamp(_repsMinVal, _repsMax);

    final raw = WeightConv.fromKg(widget.initialWeightKg, widget.unit);
    _weightDisplay = (raw / _weightStep).round() * _weightStep;
    _weightDisplay = _weightDisplay.clamp(0.0, _weightRangeMax(widget.unit));

    _name = TextEditingController(text: widget.initialName);
    if (widget.initialName.trim().isNotEmpty) {
      _lastAutofilledFor = widget.initialName.trim().toLowerCase();
    }
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) _maybeAutofillFromName();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setsCtrl.jumpToItem(_sets - _setsMin);
      _repsMinCtrl.jumpToItem(_repsMinVal - _repsMin);
      _repsMaxCtrl.jumpToItem(_repsMaxVal - _repsMin);
      _weightCtrl.jumpToItem((_weightDisplay / _weightStep).round());
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _setsCtrl.dispose();
    _repsMinCtrl.dispose();
    _repsMaxCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeAutofillFromName() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final norm = name.toLowerCase();
    if (norm == _lastAutofilledFor) return;

    final programDao = ref.read(programDaoProvider);
    final pe = await programDao.mostRecentProgramExerciseForName(name);
    if (pe == null) {
      _lastAutofilledFor = norm;
      return;
    }

    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    double? overrideWeightKg;
    final lastSet =
        await ref.read(workoutDaoProvider).lastSetForExercise(pe.exerciseId);
    if (lastSet != null) overrideWeightKg = lastSet.weightKg;

    if (!mounted) return;

    setState(() {
      if (!_userTouchedSets) {
        _sets = pe.targetSets.clamp(_setsMin, _setsMax);
      }
      if (!_userTouchedRepsMin) {
        _repsMinVal = pe.targetRepsMin.clamp(_repsMin, _repsMax);
      }
      if (!_userTouchedRepsMax) {
        _repsMaxVal = pe.targetRepsMax.clamp(_repsMinVal, _repsMax);
      }
      if (!_userTouchedWeight) {
        final kg = overrideWeightKg ?? pe.defaultWeightKg;
        final raw = WeightConv.fromKg(kg, unit);
        _weightDisplay = (raw / _weightStep).round() * _weightStep;
        _weightDisplay = _weightDisplay.clamp(0.0, _weightRangeMax(unit));
      }
      _lastAutofilledFor = norm;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_userTouchedSets) _setsCtrl.jumpToItem(_sets - _setsMin);
      if (!_userTouchedRepsMin) {
        _repsMinCtrl.jumpToItem(_repsMinVal - _repsMin);
      }
      if (!_userTouchedRepsMax) {
        _repsMaxCtrl.jumpToItem(_repsMaxVal - _repsMin);
      }
      if (!_userTouchedWeight) {
        _weightCtrl.jumpToItem((_weightDisplay / _weightStep).round());
      }
    });
  }

  Iterable<String> _options(TextEditingValue value, List<String> all) {
    final query = value.text.trim().toLowerCase();
    if (query.isEmpty) return all.take(40);
    final starts = <String>[];
    final contains = <String>[];
    for (final n in all) {
      final ln = n.toLowerCase();
      if (ln == query) continue;
      if (ln.startsWith(query)) {
        starts.add(n);
      } else if (ln.contains(query)) {
        contains.add(n);
      }
    }
    return [...starts, ...contains].take(40);
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final weightCount = (_weightRangeMax(unit) / _weightStep).round() + 1;

    final seed = ref.watch(seedExerciseNamesProvider).maybeWhen(
          data: (v) => v,
          orElse: () => const <String>[],
        );
    final knownAsync = ref.watch(_knownExerciseNamesProvider);
    final known = knownAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <String>[],
    );
    final mergedNames = _mergeNames(seed, known);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LsGap.tight),
        EyebrowLabel(
          widget.initialName.isEmpty ? 'ADD EXERCISE' : 'EDIT EXERCISE',
        ),
        const SizedBox(height: LsGap.sub),
        // Display-font name input — replaces the previous title + text-field
        // pair. Reads like the section's headline; functions like a free-form
        // input with autocomplete.
        _DisplayNameField(
          controller: _name,
          focusNode: _nameFocus,
          optionsBuilder: (v) => _options(v, mergedNames),
          onSelected: (selected) {
            _name.text = selected;
            _name.selection = TextSelection.fromPosition(
              TextPosition(offset: _name.text.length),
            );
            _maybeAutofillFromName();
          },
        ),
        const SizedBox(height: LsGap.loose),
        // Four-column wheel grid: Sets / Rep Min / Rep Max / Weight.
        SizedBox(
          height: 240,
          child: Row(
            children: [
              Expanded(
                child: PickerColumn(
                  label: 'SETS',
                  controller: _setsCtrl,
                  itemCount: _setsMax - _setsMin + 1,
                  builder: (i, sel) =>
                      PickerText('${i + _setsMin}', selected: sel),
                  onChanged: (i) {
                    setState(() {
                      _sets = i + _setsMin;
                      _userTouchedSets = true;
                    });
                  },
                ),
              ),
              Expanded(
                child: PickerColumn(
                  label: 'REP MIN',
                  controller: _repsMinCtrl,
                  itemCount: _repsMax - _repsMin + 1,
                  builder: (i, sel) =>
                      PickerText('${i + _repsMin}', selected: sel),
                  onChanged: (i) {
                    setState(() {
                      _repsMinVal = i + _repsMin;
                      _userTouchedRepsMin = true;
                      if (_repsMaxVal < _repsMinVal) {
                        _repsMaxVal = _repsMinVal;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _repsMaxCtrl.jumpToItem(_repsMaxVal - _repsMin);
                          }
                        });
                      }
                    });
                  },
                ),
              ),
              Expanded(
                child: PickerColumn(
                  label: 'REP MAX',
                  controller: _repsMaxCtrl,
                  itemCount: _repsMax - _repsMin + 1,
                  builder: (i, sel) =>
                      PickerText('${i + _repsMin}', selected: sel),
                  onChanged: (i) {
                    setState(() {
                      _repsMaxVal = i + _repsMin;
                      _userTouchedRepsMax = true;
                      if (_repsMaxVal < _repsMinVal) {
                        _repsMinVal = _repsMaxVal;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _repsMinCtrl.jumpToItem(_repsMinVal - _repsMin);
                          }
                        });
                      }
                    });
                  },
                ),
              ),
              Expanded(
                child: PickerColumn(
                  label: 'WT',
                  unitSuffix: unit.short,
                  controller: _weightCtrl,
                  itemCount: weightCount,
                  builder: (i, sel) => PickerText(
                    _formatWeightLabel(i * _weightStep, unit),
                    selected: sel,
                  ),
                  onChanged: (i) {
                    setState(() {
                      _weightDisplay = i * _weightStep;
                      _userTouchedWeight = true;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LsGap.loose),
        // "WEIGHT STEP" eyebrow + chip row. The user explicitly asked for a
        // label here — without it, the kg/lb numbers on the chips below are
        // unmoored.
        EyebrowLabel('WEIGHT STEP'),
        const SizedBox(height: LsGap.sub),
        WeightStepToggle(
          unit: unit,
          current: _weightStep,
          onChanged: (s) {
            final oldValue = _weightDisplay;
            setState(() {
              _weightStep = s;
              _weightDisplay = (oldValue / _weightStep).round() * _weightStep;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _weightCtrl
                  .jumpToItem((_weightDisplay / _weightStep).round());
            });
          },
        ),
        const SizedBox(height: LsGap.loose),
        LsButton(
          label: 'SAVE',
          onPressed: _save,
          expand: true,
          minHeight: LsBox.cta,
        ),
        if (widget.canDelete) ...[
          const SizedBox(height: LsGap.sub),
          // Antonio button-style label, danger color. Matches the design
          // screenshot — same chunky condensed face as SAVE, just smaller and
          // red.
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              ExerciseEditResult(
                name: _name.text,
                sets: 0,
                repsMin: 0,
                repsMax: 0,
                weightKg: 0,
                weightStepKg: _weightStep,
                delete: true,
              ),
            ),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              'DELETE',
              style: LsType.button.copyWith(color: LsSignals.danger),
            ),
          ),
        ],
        const SizedBox(height: LsGap.tight),
      ],
    );
  }

  String _formatWeightLabel(double valueInUnit, WeightUnit unit) {
    if (valueInUnit == valueInUnit.roundToDouble()) {
      return valueInUnit.toStringAsFixed(0);
    }
    return valueInUnit.toStringAsFixed(1);
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || _repsMaxVal < _repsMinVal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a name and a valid rep range.')),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    // Persist step in kg regardless of current display unit.
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    final stepKg = unit == WeightUnit.kg
        ? _weightStep
        : (_weightStep / 2.20462); // lb → kg
    Navigator.pop(
      context,
      ExerciseEditResult(
        name: name,
        sets: _sets,
        repsMin: _repsMinVal,
        repsMax: _repsMaxVal,
        weightKg: WeightConv.toKg(_weightDisplay, widget.unit),
        weightStepKg: stepKg,
      ),
    );
  }
}

final _knownExerciseNamesProvider =
    FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(programDaoProvider).listKnownExerciseNames();
});

List<String> _mergeNames(List<String> seed, List<String> known) {
  final seenLower = <String>{};
  final out = <String>[];
  for (final list in [seed, known]) {
    for (final n in list) {
      final lower = n.toLowerCase();
      if (seenLower.add(lower)) out.add(n);
    }
  }
  out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

/// Display-font name input with anchored autocomplete dropdown. The
/// TextField uses Antonio at the same scale as a `displayM` title, so the
/// input *reads* like the section's headline — exactly the affordance the
/// user wanted ("format the input box to use the display font").
class _DisplayNameField extends StatefulWidget {
  const _DisplayNameField({
    required this.controller,
    required this.focusNode,
    required this.optionsBuilder,
    required this.onSelected,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final Iterable<String> Function(TextEditingValue) optionsBuilder;
  final ValueChanged<String> onSelected;

  @override
  State<_DisplayNameField> createState() => _DisplayNameFieldState();
}

class _DisplayNameFieldState extends State<_DisplayNameField> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  double _fieldWidth = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocus);
    widget.controller.addListener(_handleText);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocus);
    widget.controller.removeListener(_handleText);
    super.dispose();
  }

  void _handleFocus() {
    if (widget.focusNode.hasFocus) {
      _measureField();
      if (!_overlay.isShowing) _overlay.show();
    } else {
      if (_overlay.isShowing) _overlay.hide();
    }
  }

  void _handleText() {
    if (mounted) setState(() {});
  }

  void _measureField() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      _fieldWidth = box.size.width;
    }
  }

  void _select(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: value.length),
    );
    widget.onSelected(value);
    widget.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final options =
        widget.optionsBuilder(widget.controller.value).toList(growable: false);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (overlayCtx) {
          if (options.isEmpty) return const SizedBox.shrink();
          return Positioned(
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
              child: TapRegion(
                onTapOutside: (_) => widget.focusNode.unfocus(),
                child: SizedBox(
                  width: _fieldWidth > 0 ? _fieldWidth : 280,
                  child: Material(
                    color: t.surface.surface,
                    elevation: 8,
                    shadowColor: Colors.black54,
                    borderRadius: BorderRadius.circular(LsRadius.r3),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: t.surface.border),
                        itemBuilder: (ctx, i) {
                          final opt = options[i];
                          return InkWell(
                            onTap: () => _select(opt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Text(
                                opt.toUpperCase(),
                                style: LsType.displayS
                                    .copyWith(color: t.surface.text),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: TextField(
          key: _fieldKey,
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: widget.controller.text.isEmpty,
          textCapitalization: TextCapitalization.characters,
          style: LsType.displayM.copyWith(
            color: t.surface.text,
            fontSize: 30,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            hintText: 'EXERCISE NAME',
            hintStyle: LsType.displayM.copyWith(
              color: t.surface.text3,
              fontSize: 30,
            ),
            filled: true,
            fillColor: t.surface.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LsRadius.r3),
              borderSide: BorderSide(color: t.surface.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LsRadius.r3),
              borderSide: BorderSide(color: t.surface.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LsRadius.r3),
              borderSide: BorderSide(color: t.accent.accent, width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}
