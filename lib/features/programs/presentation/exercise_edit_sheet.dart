import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
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
    this.delete = false,
  });
  final String name;
  final int sets;
  final int repsMin;
  final int repsMax;
  final double weightKg;
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
  bool canDelete = false,
}) {
  return showModalBottomSheet<ExerciseEditResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.elevated,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: _ExerciseEditSheet(
        unit: unit,
        initialName: initialName,
        initialSets: initialSets,
        initialRepsMin: initialRepsMin,
        initialRepsMax: initialRepsMax,
        initialWeightKg: initialWeightKg,
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
    required this.canDelete,
  });
  final WeightUnit unit;
  final String initialName;
  final int initialSets;
  final int initialRepsMin;
  final int initialRepsMax;
  final double initialWeightKg;
  final bool canDelete;

  @override
  ConsumerState<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends ConsumerState<_ExerciseEditSheet> {
  // ---- range bounds for pickers ----
  static const int _setsMin = 1;
  static const int _setsMax = 10;
  static const int _repsMin = 1;
  static const int _repsMax = 50;

  double _weightRangeMax(WeightUnit unit) =>
      unit == WeightUnit.kg ? 300.0 : 660.0;

  // ---- live picker state ----
  late int _sets;
  late int _repsMinVal;
  late int _repsMaxVal;
  late double _weightDisplay; // in user's unit
  late double _weightStep; // in user's unit

  // ---- name combobox state ----
  late final TextEditingController _name;
  final FocusNode _nameFocus = FocusNode();
  String? _lastAutofilledFor; // last name we autofilled from, normalized

  // ---- picker controllers ----
  final _setsCtrl = FixedExtentScrollController();
  final _repsMinCtrl = FixedExtentScrollController();
  final _repsMaxCtrl = FixedExtentScrollController();
  final _weightCtrl = FixedExtentScrollController();

  // ---- "user touched" flags so autofill never overrides explicit edits ----
  bool _userTouchedSets = false;
  bool _userTouchedRepsMin = false;
  bool _userTouchedRepsMax = false;
  bool _userTouchedWeight = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _weightStep =
        settings.weightStep > 0 ? settings.weightStep : widget.unit.defaultStep;

    _sets = widget.initialSets.clamp(_setsMin, _setsMax);
    _repsMinVal = widget.initialRepsMin.clamp(_repsMin, _repsMax);
    _repsMaxVal = widget.initialRepsMax.clamp(_repsMinVal, _repsMax);

    final raw = WeightConv.fromKg(widget.initialWeightKg, widget.unit);
    _weightDisplay = (raw / _weightStep).round() * _weightStep;
    _weightDisplay =
        _weightDisplay.clamp(0.0, _weightRangeMax(widget.unit));

    _name = TextEditingController(text: widget.initialName);
    if (widget.initialName.trim().isNotEmpty) {
      _lastAutofilledFor = widget.initialName.trim().toLowerCase();
    }

    // Run autofill when the user leaves the name field with a known name.
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

  /// If the typed/picked name matches a known exercise name, fetch its most
  /// recent program plan and last actual lifted weight, then update any picker
  /// the user hasn't manually changed.
  Future<void> _maybeAutofillFromName() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final norm = name.toLowerCase();
    if (norm == _lastAutofilledFor) return;

    final programDao = ref.read(programDaoProvider);
    final pe = await programDao.mostRecentProgramExerciseForName(name);
    if (pe == null) {
      // The name isn't in the library yet — nothing to autofill from.
      _lastAutofilledFor = norm;
      return;
    }

    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    double? overrideWeightKg;
    final lastSet = await ref.read(workoutDaoProvider).lastSetForExercise(pe.exerciseId);
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
        _weightDisplay =
            _weightDisplay.clamp(0.0, _weightRangeMax(unit));
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
      if (ln == query) continue; // hide exact match — already typed
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initialName.isEmpty ? 'Add exercise' : 'Edit exercise',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _NameCombobox(
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
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PickerColumn(
                      label: 'SETS',
                      controller: _setsCtrl,
                      itemCount: _setsMax - _setsMin + 1,
                      builder: (i) => PickerText('${i + _setsMin}'),
                      onChanged: (i) {
                        setState(() {
                          _sets = i + _setsMin;
                          _userTouchedSets = true;
                        });
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                  Expanded(
                    child: PickerColumn(
                      label: 'REP MIN',
                      controller: _repsMinCtrl,
                      itemCount: _repsMax - _repsMin + 1,
                      builder: (i) => PickerText('${i + _repsMin}'),
                      onChanged: (i) {
                        setState(() {
                          _repsMinVal = i + _repsMin;
                          _userTouchedRepsMin = true;
                          if (_repsMaxVal < _repsMinVal) {
                            _repsMaxVal = _repsMinVal;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _repsMaxCtrl
                                    .jumpToItem(_repsMaxVal - _repsMin);
                              }
                            });
                          }
                        });
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                  Expanded(
                    child: PickerColumn(
                      label: 'REP MAX',
                      controller: _repsMaxCtrl,
                      itemCount: _repsMax - _repsMin + 1,
                      builder: (i) => PickerText('${i + _repsMin}'),
                      onChanged: (i) {
                        setState(() {
                          _repsMaxVal = i + _repsMin;
                          _userTouchedRepsMax = true;
                          if (_repsMaxVal < _repsMinVal) {
                            _repsMinVal = _repsMaxVal;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _repsMinCtrl
                                    .jumpToItem(_repsMinVal - _repsMin);
                              }
                            });
                          }
                        });
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: PickerColumn(
                label: 'DEFAULT WEIGHT (${unit.short})',
                controller: _weightCtrl,
                itemCount: weightCount,
                builder: (i) => PickerText(
                  _formatWeightLabel(i * _weightStep, unit),
                ),
                onChanged: (i) {
                  setState(() {
                    _weightDisplay = i * _weightStep;
                    _userTouchedWeight = true;
                  });
                  HapticFeedback.selectionClick();
                },
              ),
            ),
            const SizedBox(height: 8),
            WeightStepToggle(
              unit: unit,
              current: _weightStep,
              onChanged: (s) async {
                final oldValue = _weightDisplay;
                setState(() {
                  _weightStep = s;
                  _weightDisplay = (oldValue / _weightStep).round() * _weightStep;
                });
                await ref.read(settingsProvider.notifier).setWeightStep(s);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _weightCtrl.jumpToItem((_weightDisplay / _weightStep).round());
                });
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
            if (widget.canDelete) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  ExerciseEditResult(
                    name: _name.text,
                    sets: 0,
                    repsMin: 0,
                    repsMax: 0,
                    weightKg: 0,
                    delete: true,
                  ),
                ),
                child: const Text('Delete',
                    style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ],
        ),
      ),
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
        const SnackBar(
          content: Text('Pick a name and a valid rep range.'),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(
      context,
      ExerciseEditResult(
        name: name,
        sets: _sets,
        repsMin: _repsMinVal,
        repsMax: _repsMaxVal,
        weightKg: WeightConv.toKg(_weightDisplay, widget.unit),
      ),
    );
  }
}

/// Auto-disposes so each time the sheet opens we re-query and pick up any
/// exercises the user named during a previous sheet session.
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

/// Combobox: free-text TextField anchored to an overlay dropdown that opens
/// on focus and filters live as the user types.
class _NameCombobox extends StatefulWidget {
  const _NameCombobox({
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
  State<_NameCombobox> createState() => _NameComboboxState();
}

class _NameComboboxState extends State<_NameCombobox> {
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
    // Rebuild so the options list reflects new text.
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
    final options = widget
        .optionsBuilder(widget.controller.value)
        .toList(growable: false);

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
                onTapOutside: (_) {
                  widget.focusNode.unfocus();
                },
                child: SizedBox(
                  width: _fieldWidth > 0 ? _fieldWidth : 280,
                  child: Material(
                    color: AppColors.surface,
                    elevation: 8,
                    shadowColor: Colors.black54,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const Divider(
                            height: 1, color: AppColors.divider),
                        itemBuilder: (ctx, i) {
                          final opt = options[i];
                          return InkWell(
                            onTap: () => _select(opt),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Text(
                                opt,
                                style: Theme.of(ctx).textTheme.bodyLarge,
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
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Exercise name',
            suffixIcon: IconButton(
              icon: Icon(
                _overlay.isShowing
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
                color: AppColors.textSecondary,
              ),
              onPressed: () {
                if (widget.focusNode.hasFocus) {
                  widget.focusNode.unfocus();
                } else {
                  widget.focusNode.requestFocus();
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
