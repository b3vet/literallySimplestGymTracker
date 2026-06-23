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
    this.dropCount = 0,
    this.delete = false,
    this.revert = false,
  });
  final String name;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double weightKg;

  /// Drop-set drops after the top set (0 = normal exercise).
  final int dropCount;

  /// Per-exercise weight step in **kg**, persisted on the ProgramExercise.
  final double weightStepKg;
  final bool delete;

  /// True when the user chose "REVERT TO PLAN" — only emitted by the
  /// active-workout edit flow (`canRevert: true`). The other fields are
  /// meaningless in that case; the caller should look at `revert` first
  /// and drop the override server-side.
  final bool revert;
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
  int initialDropCount = 0,
  bool canDelete = false,
  bool canRevert = false,
}) {
  return showModalBottomSheet<ExerciseEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // The wrapper does exactly two things:
    //   1. `Padding(bottom: viewInsets)` lifts the sheet clear of the
    //      keyboard. (This is the canonical Flutter pattern — the
    //      `showModalBottomSheet` API itself does not apply it.)
    //   2. `ConstrainedBox(maxHeight: …)` caps the sheet height at the
    //      visible viewport so it doesn't sail off the top of the screen
    //      when content + dropdown together exceed the available space.
    // The sheet itself sizes to its content (LsSheet's column is
    // `mainAxisSize.min`), so when nothing forces it to grow it stays
    // compact. The dropdown is now an INLINE part of the sheet body that
    // appears only when the textfield is focused — when it does appear,
    // the sheet grows to accommodate, the keyboard padding lifts the
    // whole stack clear, and the inner SingleChildScrollView absorbs any
    // overflow. No more overlay-vs-keyboard arithmetic anywhere.
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mq.size.height - mq.padding.top - mq.viewInsets.bottom,
          ),
          child: LsSheet(
            child: _ExerciseEditSheet(
              unit: unit,
              initialName: initialName,
              initialSets: initialSets,
              initialRepsMin: initialRepsMin,
              initialRepsMax: initialRepsMax,
              initialWeightKg: initialWeightKg,
              initialWeightStepKg: initialWeightStepKg,
              initialDropCount: initialDropCount,
              canDelete: canDelete,
              canRevert: canRevert,
            ),
          ),
        ),
      );
    },
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
    required this.initialDropCount,
    required this.canDelete,
    required this.canRevert,
  });
  final WeightUnit unit;
  final String initialName;
  final int initialSets;
  final int initialRepsMin;
  final int initialRepsMax;
  final double initialWeightKg;
  final double? initialWeightStepKg;
  final int initialDropCount;
  final bool canDelete;
  final bool canRevert;

  @override
  ConsumerState<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends ConsumerState<_ExerciseEditSheet> {
  static const int _setsMin = 1;
  static const int _setsMax = 10;
  static const int _repsMin = 1;
  static const int _repsMax = 50;
  static const int _dropsMax = 4;

  double _weightRangeMax(WeightUnit unit) =>
      unit == WeightUnit.kg ? 300.0 : 660.0;

  late int _sets;
  late int _repsMinVal;
  late int _repsMaxVal;
  late double _weightDisplay;
  late double _weightStep;
  late int _dropCount;

  late final TextEditingController _name;
  final FocusNode _nameFocus = FocusNode();
  String? _lastAutofilledFor;

  // Picker controllers are constructed in initState with `initialItem` set
  // to the matching `widget.initial*` value. This matters because the sheet
  // has a two-mode layout: while the name field is focused (dropdown open),
  // the pickers aren't in the tree at all. The first-frame `jumpToItem`
  // call only succeeds when the pickers are mounted, so if the dropdown
  // opens before they mount, the pickers default to item 0 — leaving the
  // user with SETS=1, REPS=1/1, WT=0 the first time they're seen. Using
  // `initialItem` removes that race entirely.
  late final FixedExtentScrollController _setsCtrl;
  late final FixedExtentScrollController _repsMinCtrl;
  late final FixedExtentScrollController _repsMaxCtrl;
  late final FixedExtentScrollController _weightCtrl;

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
    _dropCount = widget.initialDropCount.clamp(0, _dropsMax);

    final raw = WeightConv.fromKg(widget.initialWeightKg, widget.unit);
    _weightDisplay = (raw / _weightStep).round() * _weightStep;
    _weightDisplay = _weightDisplay.clamp(0.0, _weightRangeMax(widget.unit));

    // Construct picker controllers AFTER the values are clamped so each
    // wheel starts on the right row regardless of when the pickers first
    // mount (see the comment near the field declarations).
    _setsCtrl = FixedExtentScrollController(initialItem: _sets - _setsMin);
    _repsMinCtrl = FixedExtentScrollController(
      initialItem: _repsMinVal - _repsMin,
    );
    _repsMaxCtrl = FixedExtentScrollController(
      initialItem: _repsMaxVal - _repsMin,
    );
    _weightCtrl = FixedExtentScrollController(
      initialItem: (_weightDisplay / _weightStep).round(),
    );

    _name = TextEditingController(text: widget.initialName);
    if (widget.initialName.trim().isNotEmpty) {
      _lastAutofilledFor = widget.initialName.trim().toLowerCase();
    }
    _nameFocus.addListener(() {
      // Rebuild so the inline options list appears/disappears with focus.
      if (mounted) setState(() {});
      if (!_nameFocus.hasFocus) _maybeAutofillFromName();
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
    final lastSet = await ref
        .read(workoutDaoProvider)
        .lastSetForExercise(pe.exerciseId);
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

    final seed = ref
        .watch(seedExerciseNamesProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <String>[]);
    final knownAsync = ref.watch(_knownExerciseNamesProvider);
    final known = knownAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <String>[],
    );
    final mergedNames = _mergeNames(seed, known);
    final options = _options(_name.value, mergedNames).toList(growable: false);
    final showDropdown = _nameFocus.hasFocus && options.isNotEmpty;

    // **Unified tree** — eyebrow, _NameField, then EITHER the dropdown OR
    // the form, both wrapped in `Flexible(loose)` so they consume the
    // remaining sheet height. The two modes used to live in two completely
    // different roots (`Column` vs `ListView`); switching between them
    // recreated the `_NameField` element, which detached its EditableText
    // from the IME for one frame. iOS interprets that as "no text input
    // client right now" and dismisses the keyboard. Users saw the
    // keyboard flash off whenever the dropdown appeared/disappeared
    // (first-mount autofocus race, and the "delete one char of an exact
    // match" case). With a single Column root, `_NameField` keeps the
    // same element identity across mode toggles — focus + IME survive.
    //
    // The remaining-space child below `_NameField` is what swaps:
    //   • Typing mode (dropdown showing): `_NameOptionsList`.
    //   • Editing mode (no dropdown): the form (pickers + weight step +
    //     save + delete? + revert?) inside a `SingleChildScrollView` so
    //     it scrolls when the keyboard eats into the available height.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LsGap.tight),
        EyebrowLabel(
          widget.initialName.isEmpty ? 'ADD EXERCISE' : 'EDIT EXERCISE',
        ),
        const SizedBox(height: LsGap.sub),
        _NameField(
          controller: _name,
          focusNode: _nameFocus,
          onChanged: () => setState(() {}),
        ),
        if (showDropdown) ...[
          const SizedBox(height: LsGap.sub),
          Flexible(
            fit: FlexFit.loose,
            child: _NameOptionsList(
              options: options,
              onPick: (selected) {
                _name.text = selected;
                _name.selection = TextSelection.fromPosition(
                  TextPosition(offset: _name.text.length),
                );
                _maybeAutofillFromName();
                _nameFocus.unfocus();
                setState(() {});
              },
            ),
          ),
        ] else
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: LsGap.loose),
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
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      _repsMaxCtrl.jumpToItem(
                                        _repsMaxVal - _repsMin,
                                      );
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
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      _repsMinCtrl.jumpToItem(
                                        _repsMinVal - _repsMin,
                                      );
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
                  EyebrowLabel('WEIGHT STEP'),
                  const SizedBox(height: LsGap.sub),
                  WeightStepToggle(
                    unit: unit,
                    current: _weightStep,
                    onChanged: (s) {
                      final oldValue = _weightDisplay;
                      setState(() {
                        _weightStep = s;
                        _weightDisplay =
                            (oldValue / _weightStep).round() * _weightStep;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _weightCtrl.jumpToItem(
                          (_weightDisplay / _weightStep).round(),
                        );
                      });
                    },
                  ),
                  const SizedBox(height: LsGap.loose),
                  EyebrowLabel('DROP SET'),
                  const SizedBox(height: LsGap.sub),
                  Row(
                    children: [
                      Expanded(
                        child: LsChoiceChip(
                          label: 'OFF',
                          selected: _dropCount == 0,
                          expand: true,
                          onTap: () => setState(() => _dropCount = 0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LsChoiceChip(
                          label: 'ON',
                          selected: _dropCount > 0,
                          expand: true,
                          onTap: () => setState(() {
                            if (_dropCount == 0) _dropCount = 1;
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (_dropCount > 0) ...[
                    const SizedBox(height: LsGap.loose),
                    EyebrowLabel('DROPS'),
                    const SizedBox(height: LsGap.sub),
                    Row(
                      children: [
                        for (var n = 1; n <= _dropsMax; n++) ...[
                          if (n > 1) const SizedBox(width: 8),
                          Expanded(
                            child: LsChoiceChip(
                              label: '$n',
                              selected: _dropCount == n,
                              expand: true,
                              onTap: () => setState(() => _dropCount = n),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: LsGap.loose),
                  LsButton(
                    label: 'SAVE',
                    onPressed: _save,
                    expand: true,
                    minHeight: LsBox.cta,
                  ),
                  if (widget.canDelete) ...[
                    const SizedBox(height: LsGap.sub),
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
                  if (widget.canRevert) ...[
                    const SizedBox(height: LsGap.sub),
                    TextButton(
                      // The other fields are filled with the current display
                      // values so callers that ignore `revert` and just
                      // persist the result still get a sane row, but the
                      // canonical reading is "look at `revert` first; if
                      // true, drop the override".
                      onPressed: () => Navigator.pop(
                        context,
                        ExerciseEditResult(
                          name: _name.text,
                          sets: _sets,
                          repsMin: _repsMinVal,
                          repsMax: _repsMaxVal,
                          weightKg: WeightConv.toKg(
                            _weightDisplay,
                            widget.unit,
                          ),
                          weightStepKg: _weightStep,
                          dropCount: _dropCount,
                          revert: true,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(
                        'REVERT TO PLAN',
                        style: LsType.button.copyWith(
                          color: LsTheme.of(context).surface.text2,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: LsGap.tight),
                ],
              ),
            ),
          ),
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
        dropCount: _dropCount,
      ),
    );
  }
}

final _knownExerciseNamesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) {
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

/// Plain display-font TextField used for the exercise name. No overlay,
/// no measurement — the autocomplete list is rendered as a sibling widget
/// (`_NameOptionsList`) in the parent column, so it participates in the
/// sheet's natural scroll layout.
class _NameField extends StatefulWidget {
  const _NameField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleText);
    super.dispose();
  }

  void _handleText() {
    if (mounted) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.controller.text.isEmpty,
      textCapitalization: TextCapitalization.characters,
      style: LsType.displayM.copyWith(color: t.surface.text, fontSize: 30),
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
    );
  }
}

/// Inline autocomplete results. Renders as a bounded card with an internal
/// scrolling ListView — it lives in the sheet's main scroll column, so
/// (a) it pushes pickers down rather than overlapping them, and (b) the
/// sheet/keyboard padding system handles keyboard avoidance for free.
class _NameOptionsList extends StatelessWidget {
  const _NameOptionsList({required this.options, required this.onPick});
  final List<String> options;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    // No outer sizing — the parent (Flexible(loose) in the typing-mode
    // Column above) hands us the exact remaining sheet height as our
    // bounded constraint. We just fill it. The ListView scrolls
    // internally when there are more options than fit.
    return Material(
      color: t.surface.surface2,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          border: Border.all(color: t.surface.border),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: options.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: t.surface.border),
          itemBuilder: (ctx, i) {
            final opt = options[i];
            return InkWell(
              onTap: () => onPick(opt),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Text(
                  opt.toUpperCase(),
                  style: LsType.displayS.copyWith(color: t.surface.text),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
