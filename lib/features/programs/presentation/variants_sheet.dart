import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/layout.dart';
import '../application/programs_provider.dart';
import '../domain/program_exercise_variant.dart';
import 'exercise_edit_sheet.dart';

/// SOW-14: a slot's variants — list, add, edit, delete. Opened from the
/// `VARIANTS · N` row of the program editor's exercise sheet. Each variant is
/// an ordinary exercise with its own target weight and step; sets, reps and
/// drop count stay on the slot.
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

  Future<void> _add() async {
    final result = await showExerciseEditSheet(
      context,
      unit: _unit,
      initialName: '',
      initialSets: 1,
      initialRepsMin: 1,
      initialRepsMax: 1,
      initialWeightKg: 0,
      initialWeightStepKg: null,
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
          );
      setState(() => _error = null);
    } on VariantConflict catch (e) {
      setState(() => _error = e.message);
    }
    _refresh();
  }

  Future<void> _edit(ProgramExerciseVariantView v) async {
    final result = await showExerciseEditSheet(
      context,
      unit: _unit,
      initialName: v.exerciseName,
      initialSets: 1,
      initialRepsMin: 1,
      initialRepsMax: 1,
      initialWeightKg: v.variant.defaultWeightKg,
      initialWeightStepKg: v.variant.weightStepKg,
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LsSheetHeader(eyebrow: 'VARIANTS', title: widget.baseName),
        const SizedBox(height: LsGap.sub),
        Text(
          'SAME SETS & REPS · OWN WEIGHT',
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
              'lift with its own weight, then switch to it from the workout '
              'menu.',
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
                    weight: WeightConv.format(
                      v.variant.defaultWeightKg,
                      unit,
                    ).toUpperCase(),
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

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.name,
    required this.weight,
    required this.onTap,
  });
  final String name;
  final String weight;
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
                child: Text(
                  name.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LsType.displayS.copyWith(
                    color: t.surface.text,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                weight,
                style: LsType.monoData.copyWith(
                  color: t.surface.text,
                  fontSize: 18,
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
