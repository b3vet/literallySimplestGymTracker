import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'program_delete.dart';
import 'variants_sheet.dart';

class DayEditorScreen extends ConsumerStatefulWidget {
  const DayEditorScreen({
    super.key,
    required this.programId,
    required this.dayId,
  });
  final String programId;
  final String dayId;

  @override
  ConsumerState<DayEditorScreen> createState() => _DayEditorScreenState();
}

class _DayEditorScreenState extends ConsumerState<DayEditorScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final day = ref.watch(dayProvider(widget.dayId));
    final program = ref.watch(programProvider(widget.programId));
    final exercises = ref.watch(dayExercisesProvider(widget.dayId));

    final dayName = day.maybeWhen(
      data: (d) => d?.name ?? 'DAY',
      orElse: () => 'DAY',
    );
    final programName = program.maybeWhen(
      data: (p) => p?.name ?? 'PROGRAM',
      orElse: () => '—',
    );

    return LsScreen(
      topGap: LsGap.loose,
      topbar: LsTopbar(
        title: dayName,
        trailing: LsIconSquare(
          icon: Icons.copy_all,
          semanticLabel: 'Duplicate day',
          onTap: () => _duplicate(context),
        ),
      ),
      footer: LsFabPair(
        leftLabel: _editing ? 'DONE' : 'EDIT',
        leftIcon: _editing ? Icons.check : Icons.edit_outlined,
        rightLabel: '+ EXERCISE',
        // EDIT mode (SOW-15): delete buttons on the exercise rows, DELETE
        // DAY, and the rename that EDIT used to open directly.
        onLeft: () => setState(() => _editing = !_editing),
        onRight: () => _addExercise(context),
      ),
      child: exercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _EmptyExercises(text2: t.surface.text2)),
                  if (_editing) _editFooter(context, dayName),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Page-content eyebrow (program · day context) below the
                  // header, not part of it.
                  Align(
                    alignment: Alignment.centerRight,
                    child: EyebrowLabel(
                      '${programName.toUpperCase()} · ${list.length} EX',
                    ),
                  ),
                  const SizedBox(height: LsGap.sub),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: EdgeInsets.zero,
                      buildDefaultDragHandles: false,
                      itemCount: list.length,
                      footer:
                          _editing ? _editFooter(context, dayName) : null,
                      proxyDecorator: (child, _, _) =>
                          Material(color: Colors.transparent, child: child),
                      onReorder: (oldIdx, newIdx) async {
                        final reordered = [...list];
                        if (newIdx > oldIdx) newIdx -= 1;
                        final moved = reordered.removeAt(oldIdx);
                        reordered.insert(newIdx, moved);
                        await ref
                            .read(programDaoProvider)
                            .reorderProgramExercises(
                              widget.dayId,
                              reordered.map((v) => v.pe.id).toList(),
                            );
                        ref.invalidate(dayExercisesProvider(widget.dayId));
                      },
                      itemBuilder: (context, i) {
                        final v = list[i];
                        return Padding(
                          key: ValueKey(v.pe.id),
                          padding: const EdgeInsets.only(bottom: LsGap.sub),
                          child: _ExerciseTile(
                            index: i,
                            view: v,
                            editing: _editing,
                            onTap: () => _editExercise(context, v),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// EDIT mode, after the last exercise: rename the day, or delete it.
  Widget _editFooter(BuildContext context, String dayName) => Padding(
        padding: const EdgeInsets.only(top: LsGap.sub, bottom: LsGap.sub),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LsButton(
              label: 'RENAME DAY',
              icon: Icons.edit_outlined,
              variant: LsButtonVariant.ghost,
              expand: true,
              onPressed: () => _rename(context),
            ),
            const SizedBox(height: LsGap.tight),
            LsButton(
              label: 'DELETE DAY',
              icon: Icons.delete_outline,
              variant: LsButtonVariant.danger,
              expand: true,
              onPressed: () => _deleteDay(context, dayName),
            ),
          ],
        ),
      );

  Future<void> _rename(BuildContext context) async {
    final d = ref.read(dayProvider(widget.dayId)).value;
    if (d == null) return;
    final name = await promptName(
      context,
      title: 'RENAME DAY',
      initial: d.name,
    );
    if (name == null || name.isEmpty) return;
    await ref.read(programDaoProvider).renameDay(d.id, name);
    ref.invalidate(dayProvider(widget.dayId));
    ref.invalidate(programDaysProvider(widget.programId));
  }

  /// SOW-15: same confirm as the program editor's day row (with the
  /// workout-in-progress warning), then back to the program editor.
  Future<void> _deleteDay(BuildContext context, String dayName) async {
    final router = GoRouter.of(context);
    await deleteDayFlow(
      context,
      ref,
      programId: widget.programId,
      dayId: widget.dayId,
      label: dayName,
      onConfirmed: () {
        if (router.canPop()) {
          router.pop();
        } else {
          router.go('/programs/${widget.programId}');
        }
      },
    );
  }

  /// SOW-13: copy this day (slots, targets) into the same program, appended
  /// last, then replace this editor with the copy's.
  Future<void> _duplicate(BuildContext context) async {
    final d = ref.read(dayProvider(widget.dayId)).value;
    if (d == null) return;
    final name = await promptName(
      context,
      title: 'DUPLICATE DAY',
      initial: '${d.name} COPY',
    );
    if (name == null || name.isEmpty) return;
    final copy =
        await ref.read(programDaoProvider).duplicateDay(d.id, name: name);
    ref.invalidate(programDaysProvider(widget.programId));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.pushReplacement('/programs/${widget.programId}/days/${copy.id}');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(
          "Copied. Changes here don't touch ${d.name.toUpperCase()}.",
        ),
      ));
  }

  Future<void> _addExercise(BuildContext context) async {
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    final result = await showExerciseEditSheet(
      context,
      unit: unit,
      initialName: '',
      initialSets: 3,
      initialRepsMin: 8,
      initialRepsMax: 12,
      initialWeightKg: 0,
      initialWeightStepKg: null,
    );
    if (result == null) return;
    try {
      await ref.read(programDaoProvider).addProgramExercise(
            programDayId: widget.dayId,
            exerciseName: result.name,
            targetSets: result.sets,
            targetRepsMin: result.repsMin,
            targetRepsMax: result.repsMax,
            defaultWeightKg: result.weightKg,
            weightStepKg: result.weightStepKg,
            dropCount: result.dropCount,
          );
    } on VariantConflict catch (e) {
      if (context.mounted) _showConflict(context, e);
      return;
    }
    ref.invalidate(dayExercisesProvider(widget.dayId));
  }

  /// SOW-14 day rule: the sheet has closed, so the refusal goes in a snackbar
  /// on this screen.
  void _showConflict(BuildContext context, VariantConflict e) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }

  Future<void> _editExercise(
    BuildContext context,
    ProgramExerciseView v,
  ) async {
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    final variants = await ref
        .read(programDaoProvider)
        .listVariants(v.pe.id);
    if (!context.mounted) return;
    final result = await showExerciseEditSheet(
      context,
      unit: unit,
      initialName: v.exerciseName,
      initialSets: v.pe.targetSets,
      initialRepsMin: v.pe.targetRepsMin,
      initialRepsMax: v.pe.targetRepsMax,
      initialWeightKg: v.pe.defaultWeightKg,
      initialWeightStepKg: v.pe.weightStepKg,
      initialDropCount: v.pe.dropCount,
      canDelete: true,
      variantCount: variants.length,
    );
    if (result == null) return;
    if (result.delete) {
      // SOW-15: the same guarded confirm → delete as the row's button and the
      // swipe (variants, History, and the workout in progress).
      if (!context.mounted) return;
      await deleteExerciseFlow(
        context,
        ref,
        programExerciseId: v.pe.id,
        dayId: widget.dayId,
        label: v.exerciseName,
      );
      return;
    } else {
      final ex = await ref
          .read(programDaoProvider)
          .findOrCreateExercise(result.name);
      try {
        await ref.read(programDaoProvider).updateProgramExercise(
              ProgramExercise(
                id: v.pe.id,
                programDayId: v.pe.programDayId,
                exerciseId: ex.id,
                position: v.pe.position,
                targetSets: result.sets,
                targetRepsMin: result.repsMin,
                targetRepsMax: result.repsMax,
                defaultWeightKg: result.weightKg,
                weightStepKg: result.weightStepKg,
                dropCount: result.dropCount,
              ),
            );
      } on VariantConflict catch (e) {
        if (context.mounted) _showConflict(context, e);
        return;
      }
    }
    ref.invalidate(dayExercisesProvider(widget.dayId));
    ref.invalidate(dayVariantsProvider(widget.dayId));
    ref.invalidate(programExerciseProvider(v.pe.id));
    // VARIANTS row: the slot's edits are saved above, then the variants sheet
    // opens on the (possibly renamed) base.
    if (result.manageVariants && !result.delete && context.mounted) {
      await showVariantsSheet(
        context,
        programExerciseId: v.pe.id,
        baseName: result.name.trim(),
      );
      ref.invalidate(dayVariantsProvider(widget.dayId));
    }
  }
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({
    required this.index,
    required this.view,
    required this.editing,
    required this.onTap,
  });
  final int index;
  final ProgramExerciseView view;
  final bool editing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final pe = view.pe;
    final repsValue = pe.targetRepsMin == pe.targetRepsMax
        ? '${pe.targetRepsMin}'
        : '${pe.targetRepsMin}-${pe.targetRepsMax}';
    final weightValue = _weightValue(pe.defaultWeightKg, unit);
    final variantCount = ref
            .watch(dayVariantsProvider(pe.programDayId))
            .value?[pe.id]
            ?.length ??
        0;

    final card = LsCard(
      onTap: editing ? null : onTap,
      padding: LsPad.cardSpacious,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_indicator,
              color: t.surface.text3,
              size: 20,
            ),
          ),
          const SizedBox(width: LsGap.inline),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.exerciseName.toUpperCase(),
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: LsGap.sub),
                Wrap(
                  spacing: LsGap.tight,
                  runSpacing: LsGap.tight,
                  children: [
                    MetaPill(value: '${pe.targetSets}', text: 'SETS'),
                    MetaPill(value: repsValue, text: 'REPS'),
                    MetaPill(value: weightValue, text: unit.short),
                    if (pe.dropCount > 0)
                      MetaPill(value: '×${pe.dropCount}', text: 'DROP'),
                    if (variantCount > 0)
                      MetaPill(value: '+$variantCount', text: 'VAR'),
                  ],
                ),
              ],
            ),
          ),
          if (editing)
            DeleteRowButton(
              name: view.exerciseName,
              onPressed: () => deleteExerciseFlow(
                context,
                ref,
                programExerciseId: pe.id,
                dayId: pe.programDayId,
                label: view.exerciseName,
              ),
            )
          else
            Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
        ],
      ),
    );

    // The swipe, the row's delete button and the edit sheet's DELETE all run
    // the same confirm → delete (program_delete.dart).
    return Dismissible(
      key: ValueKey('dismiss-${pe.id}'),
      direction: editing ? DismissDirection.endToStart : DismissDirection.none,
      background: dismissBackground(),
      confirmDismiss: (_) => confirmExerciseDelete(
        context,
        ref,
        label: view.exerciseName,
        programExerciseId: pe.id,
      ),
      onDismissed: (_) => deleteExerciseConfirmed(
        ProviderScope.containerOf(context, listen: false),
        programExerciseId: pe.id,
        dayId: pe.programDayId,
      ),
      child: card,
    );
  }
}

/// Numeric portion of a weight, formatted in the user's display unit. Stripped
/// of the unit suffix so MetaPill can render it bold alongside a separate
/// `KG`/`LB` caption.
String _weightValue(double kg, WeightUnit unit) {
  final v = WeightConv.fromKg(kg, unit);
  if (unit == WeightUnit.kg) {
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
  }
  return v.round().toString();
}

class _EmptyExercises extends StatelessWidget {
  const _EmptyExercises({required this.text2});
  final Color text2;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Tap + EXERCISE to plan your first lift.',
          textAlign: TextAlign.center,
          style: LsType.bodyM.copyWith(color: text2),
        ),
      ),
    );
  }
}
