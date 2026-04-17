import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/dialogs.dart';
import '../../workout/application/active_workout_controller.dart';
import '../../workout/domain/active_session.dart';
import '../../workout/domain/workout_set.dart';
import '../../workout/presentation/set_log_sheet.dart';
import '../application/history_provider.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sessionDetailProvider(sessionId));
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (d) {
          if (d == null) {
            return const Center(child: Text('Workout not found.'));
          }
          final byExercise = <String, List<WorkoutSet>>{};
          for (final s in d.sets) {
            byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
          }
          final dateStr = DateFormat('EEE, MMM d · HH:mm')
              .format(d.session.startedAt);
          final durMin = d.session.duration.inMinutes;
          final totalVol = d.sets
              .fold<double>(0, (t, s) => t + s.weightKg * s.reps);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(d.dayName ?? 'Workout',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${d.sets.length} sets · ${WeightConv.format(totalVol, unit)} · ${durMin}m',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              for (final entry in byExercise.entries)
                _ExerciseBlock(
                  exerciseId: entry.key,
                  name: d.exerciseNames[entry.key] ?? 'Exercise',
                  sets: entry.value,
                  unit: unit,
                  onEdit: (s) => _editSet(context, ref, s, d.exerciseNames[entry.key] ?? 'Exercise'),
                  onDelete: (s) => _deleteSet(context, ref, s),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editSet(
    BuildContext context,
    WidgetRef ref,
    WorkoutSet existing,
    String exerciseName,
  ) async {
    // Build a lightweight PlannedExercise to satisfy the sheet API.
    final fake = PlannedExercise(
      programExerciseId: 'past',
      exerciseId: existing.exerciseId,
      exerciseName: exerciseName,
      targetSets: 1,
      targetRepsMin: existing.reps,
      targetRepsMax: existing.reps,
      defaultWeightKg: existing.weightKg,
    );
    final result = await showSetLogSheet(
      context,
      exercise: fake,
      setNumber: existing.setIndex + 1,
      initialReps: existing.reps,
      initialWeightKg: existing.weightKg,
      initialRir: existing.rir,
      titleOverride: 'Edit set',
    );
    if (result == null) return;
    await ref.read(workoutDaoProvider).updateSet(
          existing.copyWith(
            reps: result.reps,
            weightKg: result.weightKg,
            rir: result.rir,
          ),
        );
    ref.invalidate(sessionDetailProvider(sessionId));
    ref.invalidate(historyListProvider);
  }

  Future<void> _deleteSet(
    BuildContext context,
    WidgetRef ref,
    WorkoutSet s,
  ) async {
    final ok = await confirmDelete(context, 'this set');
    if (ok != true) return;
    await ref.read(workoutDaoProvider).deleteSet(s.id);
    ref.invalidate(sessionDetailProvider(sessionId));
    ref.invalidate(historyListProvider);
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({
    required this.exerciseId,
    required this.name,
    required this.sets,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
  });
  final String exerciseId;
  final String name;
  final List<WorkoutSet> sets;
  final WeightUnit unit;
  final Future<void> Function(WorkoutSet) onEdit;
  final Future<void> Function(WorkoutSet) onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(name,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          for (var i = 0; i < sets.length; i++)
            _SetRow(
              index: i + 1,
              set: sets[i],
              unit: unit,
              onEdit: () => onEdit(sets[i]),
              onDelete: () => onDelete(sets[i]),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.set,
    required this.unit,
    required this.onEdit,
    required this.onDelete,
  });
  final int index;
  final WorkoutSet set;
  final WeightUnit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      onLongPress: onDelete,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
                width: 56,
                child: Text('Set $index',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ))),
            Expanded(
              child: Text(
                '${WeightConv.format(set.weightKg, unit)}  ×  ${set.reps}  ·  RIR ${set.rir}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const Icon(Icons.edit, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
