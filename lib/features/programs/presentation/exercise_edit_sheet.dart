import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';

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

class _ExerciseEditSheet extends StatefulWidget {
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
  State<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends State<_ExerciseEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _sets;
  late final TextEditingController _repsMin;
  late final TextEditingController _repsMax;
  late final TextEditingController _weight;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _sets = TextEditingController(text: widget.initialSets.toString());
    _repsMin = TextEditingController(text: widget.initialRepsMin.toString());
    _repsMax = TextEditingController(text: widget.initialRepsMax.toString());
    final weightDisplay =
        WeightConv.fromKg(widget.initialWeightKg, widget.unit);
    _weight = TextEditingController(
      text: widget.unit == WeightUnit.kg
          ? (weightDisplay == weightDisplay.roundToDouble()
              ? weightDisplay.toStringAsFixed(0)
              : weightDisplay.toStringAsFixed(1))
          : weightDisplay.round().toString(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _sets.dispose();
    _repsMin.dispose();
    _repsMax.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            TextField(
              controller: _name,
              autofocus: widget.initialName.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Exercise name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numField(_sets, label: 'Sets')),
                const SizedBox(width: 12),
                Expanded(child: _numField(_repsMin, label: 'Rep min')),
                const SizedBox(width: 12),
                Expanded(child: _numField(_repsMax, label: 'Rep max')),
              ],
            ),
            const SizedBox(height: 12),
            _numField(
              _weight,
              label: 'Default weight (${widget.unit.short})',
              decimal: widget.unit == WeightUnit.kg,
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

  Widget _numField(TextEditingController c,
      {required String label, bool decimal = false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(labelText: label),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final sets = int.tryParse(_sets.text) ?? 0;
    final repsMin = int.tryParse(_repsMin.text) ?? 0;
    final repsMax = int.tryParse(_repsMax.text) ?? 0;
    final weightInput = double.tryParse(_weight.text) ?? 0;

    if (name.isEmpty || sets < 1 || repsMin < 1 || repsMax < repsMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in valid sets and rep range.')),
      );
      return;
    }

    Navigator.pop(
      context,
      ExerciseEditResult(
        name: name,
        sets: sets,
        repsMin: repsMin,
        repsMax: repsMax,
        weightKg: WeightConv.toKg(weightInput, widget.unit),
      ),
    );
  }
}
