import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/dialogs.dart';
import '../application/programs_provider.dart';
import '../domain/program_exercise.dart';
import 'exercise_edit_sheet.dart';

class DayEditorScreen extends ConsumerWidget {
  const DayEditorScreen({
    super.key,
    required this.programId,
    required this.dayId,
  });
  final String programId;
  final String dayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(dayProvider(dayId));
    final exercises = ref.watch(dayExercisesProvider(dayId));

    return Scaffold(
      appBar: AppBar(
        title: day.maybeWhen(
          data: (d) => Text(d?.name ?? 'Day'),
          orElse: () => const Text('Day'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final d = day.value;
              if (d == null) return;
              final name = await promptName(
                context,
                title: 'Rename day',
                initial: d.name,
              );
              if (name == null || name.isEmpty) return;
              await ref.read(programDaoProvider).renameDay(d.id, name);
              ref.invalidate(dayProvider(dayId));
              ref.invalidate(programDaysProvider(programId));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _addExercise(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Exercise'),
      ),
      body: exercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? const _EmptyExercises()
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                proxyDecorator: (child, _, _) =>
                    Material(color: Colors.transparent, child: child),
                onReorder: (oldIdx, newIdx) async {
                  final reordered = [...list];
                  if (newIdx > oldIdx) newIdx -= 1;
                  final moved = reordered.removeAt(oldIdx);
                  reordered.insert(newIdx, moved);
                  await ref.read(programDaoProvider).reorderProgramExercises(
                        dayId,
                        reordered.map((v) => v.pe.id).toList(),
                      );
                  ref.invalidate(dayExercisesProvider(dayId));
                },
                itemBuilder: (context, i) {
                  final v = list[i];
                  return Padding(
                    key: ValueKey(v.pe.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ExerciseTile(
                      view: v,
                      onTap: () => _editExercise(context, ref, v),
                      onDelete: () async {
                        await ref
                            .read(programDaoProvider)
                            .deleteProgramExercise(v.pe.id);
                        ref.invalidate(dayExercisesProvider(dayId));
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    final result = await showExerciseEditSheet(
      context,
      unit: unit,
      initialName: '',
      initialSets: 3,
      initialRepsMin: 8,
      initialRepsMax: 12,
      initialWeightKg: 0,
    );
    if (result == null) return;
    await ref.read(programDaoProvider).addProgramExercise(
          programDayId: dayId,
          exerciseName: result.name,
          targetSets: result.sets,
          targetRepsMin: result.repsMin,
          targetRepsMax: result.repsMax,
          defaultWeightKg: result.weightKg,
        );
    ref.invalidate(dayExercisesProvider(dayId));
  }

  Future<void> _editExercise(
    BuildContext context,
    WidgetRef ref,
    ProgramExerciseView v,
  ) async {
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    final result = await showExerciseEditSheet(
      context,
      unit: unit,
      initialName: v.exerciseName,
      initialSets: v.pe.targetSets,
      initialRepsMin: v.pe.targetRepsMin,
      initialRepsMax: v.pe.targetRepsMax,
      initialWeightKg: v.pe.defaultWeightKg,
      canDelete: true,
    );
    if (result == null) return;
    if (result.delete) {
      await ref.read(programDaoProvider).deleteProgramExercise(v.pe.id);
    } else {
      // Name may have changed → swap exercise reference.
      final ex = await ref
          .read(programDaoProvider)
          .findOrCreateExercise(result.name);
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
            ),
          );
    }
    ref.invalidate(dayExercisesProvider(dayId));
  }
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({
    required this.view,
    required this.onTap,
    required this.onDelete,
  });
  final ProgramExerciseView view;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final pe = view.pe;
    final repsLabel = pe.targetRepsMin == pe.targetRepsMax
        ? '${pe.targetRepsMin} reps'
        : '${pe.targetRepsMin}–${pe.targetRepsMax} reps';

    return Dismissible(
      key: ValueKey('dismiss-${pe.id}'),
      direction: DismissDirection.endToStart,
      background: dismissBackground(),
      confirmDismiss: (_) async =>
          await confirmDelete(context, view.exerciseName) ?? false,
      onDismissed: (_) async => onDelete(),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.drag_indicator,
                    color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.exerciseName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${pe.targetSets} sets · $repsLabel · '
                        '${WeightConv.format(pe.defaultWeightKg, unit)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyExercises extends StatelessWidget {
  const _EmptyExercises();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No exercises yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap + to plan your first exercise for this day.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
