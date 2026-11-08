import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/layout.dart';
import '../application/programs_provider.dart';
import '../domain/program_exercise.dart';
import '../domain/program_exercise_variant.dart';
import 'exercise_edit_sheet.dart';

/// SOW-14: a slot's variants — list, add, edit, delete. Opened from the
/// `VARIANTS · N` row of the program editor's exercise sheet. Each variant is
/// an ordinary exercise with its own prescription — sets, rep range, drops,
/// weight and step (DEC-0007 #13). A variant from 1.5.0 (13) has NULLs there
/// and inherits the slot's values; the editor shows them prefilled and saves
/// them explicitly.
Future<void> showVariantsSheet(
  BuildContext context, {
  required String programExerciseId,
  required String baseName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (mq.size.height - mq.padding.top) * 0.85,
        ),
        child: LsSheet(
          child: VariantsSheet(
            programExerciseId: programExerciseId,
            baseName: baseName,
          ),
        ),
      );
    },
  );
}

class VariantsSheet extends ConsumerStatefulWidget {
  const VariantsSheet({
    super.key,
    required this.programExerciseId,
    required this.baseName,
  });
  final String programExerciseId;
  final String baseName;

  @override
  ConsumerState<VariantsSheet> createState() => _VariantsSheetState();
}

class _VariantsSheetState extends ConsumerState<VariantsSheet> {
  /// Last rejection (duplicate, base…), shown inline: a snackbar would land on
  /// the screen behind the sheet.
  String? _error;

  WeightUnit get _unit => ref.read(settingsProvider).unit ?? WeightUnit.kg;

  void _refresh() {
    ref.invalidate(slotVariantsProvider(widget.programExerciseId));
    ref.invalidate(dayVariantsProvider);
  }

  Future<ProgramExercise?> _slot() =>
      ref.read(programExerciseProvider(widget.programExerciseId).future);

  Future<void> _add() async {
    // A new variant starts from the slot's sets, reps and drops; its weight
    // comes from the name autofill (a machine rarely runs the bar's weight).
    final slot = await _slot();
    if (!mounted) return;
    final result = await showExerciseEditSheet(
      context,
      unit: _unit,
      initialName: '',
      initialSets: slot?.targetSets ?? 3,
      initialRepsMin: slot?.targetRepsMin ?? 8,
      initialRepsMax: slot?.targetRepsMax ?? 12,
      initialWeightKg: 0,
      initialWeightStepKg: null,
      initialDropCount: slot?.dropCount ?? 0,
      variantMode: true,
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(programDaoProvider)
          .addVariant(
            programExerciseId: widget.programExerciseId,
            exerciseName: result.name,
            defaultWeightKg: result.weightKg,
            weightStepKg: result.weightStepKg,
            targetSets: result.sets,
            targetRepsMin: result.repsMin,
            targetRepsMax: result.repsMax,
            dropCount: result.dropCount,
          );
      setState(() => _error = null);
    } on VariantConflict catch (e) {
      setState(() => _error = e.message);
    }
    _refresh();
  }

  Future<void> _edit(ProgramExerciseVariantView v) async {
    // NULL (a build-13 variant) shows the slot's value it inherits.
    final slot = await _slot();
    if (!mounted) return;
    final run = slot == null ? null : v.variant.resolvedOn(slot);
    final result = await showExerciseEditSheet(
      context,
      unit: _unit,
      initialName: v.exerciseName,
      initialSets: run?.targetSets ?? v.variant.targetSets ?? 3,
      initialRepsMin: run?.targetRepsMin ?? v.variant.targetRepsMin ?? 8,
      initialRepsMax: run?.targetRepsMax ?? v.variant.targetRepsMax ?? 12,
      initialWeightKg: v.variant.defaultWeightKg,
      initialWeightStepKg: run?.weightStepKg ?? v.variant.weightStepKg,
      initialDropCount: run?.dropCount ?? v.variant.dropCount ?? 0,
      canDelete: true,
      variantMode: true,
    );
    if (result == null || !mounted) return;
    final dao = ref.read(programDaoProvider);
    try {
      if (result.delete) {
        await dao.deleteVariant(v.variant.id);
      } else {
        await dao.editVariant(
          id: v.variant.id,
          exerciseName: result.name,
          defaultWeightKg: result.weightKg,
          weightStepKg: result.weightStepKg,
          targetSets: result.sets,
          targetRepsMin: result.repsMin,
          targetRepsMax: result.repsMax,
          dropCount: result.dropCount,
        );
      }
      setState(() => _error = null);
    } on VariantConflict catch (e) {
      setState(() => _error = e.message);
    }
    _refresh();
  }

  Future<void> _delete(ProgramExerciseVariantView v) async {
    await ref.read(programDaoProvider).deleteVariant(v.variant.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final async = ref.watch(slotVariantsProvider(widget.programExerciseId));
    final list = async.value ?? const <ProgramExerciseVariantView>[];
    final slot = ref
        .watch(programExerciseProvider(widget.programExerciseId))
        .value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LsSheetHeader(eyebrow: 'VARIANTS', title: widget.baseName),
        const SizedBox(height: LsGap.sub),
        Text(
          'EACH WITH ITS OWN SETS, REPS & WEIGHT',
          style: LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 14),
        ),
        const SizedBox(height: LsGap.loose),
        if (async.isLoading && list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No variants yet. Add the machine or dumbbell version of this '
              'lift with its own sets, reps and weight, then switch to it from '
              'the workout menu.',
              style: LsType.bodyM.copyWith(color: t.surface.text2),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: LsGap.sub),
              itemBuilder: (context, i) {
                final v = list[i];
                return Dismissible(
                  key: ValueKey('variant-${v.variant.id}'),
                  direction: DismissDirection.endToStart,
                  background: dismissBackground(),
                  confirmDismiss: (_) async =>
                      await confirmDelete(context, v.exerciseName) ?? false,
                  onDismissed: (_) => _delete(v),
                  child: _VariantTile(
                    name: v.exerciseName,
                    prescription: variantPrescriptionLabel(
                      slot == null ? null : v.variant.resolvedOn(slot),
                      v.variant,
                      unit,
                    ),
                    dropCount:
                        (slot == null
                            ? null
                            : v.variant.resolvedOn(slot).dropCount) ??
                        v.variant.dropCount ??
                        0,
                    onTap: () => _edit(v),
                  ),
                );
              },
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: LsGap.sub),
          Text(
            _error!,
            style: LsType.monoMeta.copyWith(color: LsSignals.danger),
          ),
        ],
        const SizedBox(height: LsGap.loose),
        LsButton(
          label: '+ ADD VARIANT',
          onPressed: _add,
          expand: true,
          minHeight: LsBox.cta,
        ),
        const SizedBox(height: LsGap.tight),
      ],
    );
  }
}

/// A variant's prescription in one line: `4×6-8 · 40 KG` (`4×8` for a fixed
/// rep count). [run] is the variant resolved on its slot; while the slot is
/// still loading it falls back to the variant's own values, then to the
/// weight alone.
String variantPrescriptionLabel(
  ProgramExercise? run,
  ProgramExerciseVariant variant,
  WeightUnit unit,
) {
  final weight = WeightConv.format(variant.defaultWeightKg, unit).toUpperCase();
  final sets = run?.targetSets ?? variant.targetSets;
  final min = run?.targetRepsMin ?? variant.targetRepsMin;
  final max = run?.targetRepsMax ?? variant.targetRepsMax;
  if (sets == null || min == null || max == null) return weight;
  final reps = min == max ? '$min' : '$min-$max';
  return '$sets×$reps · $weight';
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.name,
    required this.prescription,
    required this.dropCount,
    required this.onTap,
  });
  final String name;
  final String prescription;
  final int dropCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: t.surface.surface2,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: t.surface.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LsType.displayS.copyWith(
                        color: t.surface.text,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: LsGap.tight,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          prescription,
                          style: LsType.monoData.copyWith(
                            color: t.surface.text,
                            fontSize: 18,
                          ),
                        ),
                        if (dropCount > 0)
                          MetaPill(value: '×$dropCount', text: 'DROP'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: t.surface.text3),
            ],
          ),
        ),
      ),
    );
  }
}
