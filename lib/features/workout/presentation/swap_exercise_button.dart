import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../programs/presentation/exercise_edit_sheet.dart';
import '../application/active_workout_controller.dart';
import '../domain/active_session.dart';
import 'exercise_options_sheet.dart';

/// Topbar-style button in the leading slot of the active workout header. Sized
/// 44×44 to match the other topbar icons. Tapping opens the exercise-options
/// sheet, which branches to: change exercise (the full edit sheet), add/remove
/// a set (quick volume adjustments), or skip the exercise for this session.
/// When the slot is overridden (substituted or edited from plan) the button
/// adopts the accent border / icon tint so the user can see at a glance that
/// this slot has been modified.
class SwapExerciseButton extends ConsumerWidget {
  const SwapExerciseButton({
    super.key,
    required this.queueIdx,
    required this.exercise,
  });

  final int queueIdx;
  final PlannedExercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final overridden = exercise.isOverridden;
    return Material(
      color: overridden ? t.accent.accentDim : t.surface.surface,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: () => _openOptions(context, ref),
        child: Container(
          width: LsBox.topbarIcon,
          height: LsBox.topbarIcon,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(
              color: overridden ? t.accent.accent : t.surface.border,
            ),
          ),
          child: Icon(
            Icons.tune,
            size: 22,
            color: overridden ? t.accent.accent : t.surface.text,
            semanticLabel: 'Exercise options',
          ),
        ),
      ),
    );
  }

  Future<void> _openOptions(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(activeSessionProvider.notifier);
    final option = await showExerciseOptionsSheet(
      context,
      exercise: exercise,
      canAddSet: exercise.targetSets < kMaxTargetSets,
      canRemoveSet: exercise.targetSets > 1,
    );
    if (option == null || !context.mounted) return;

    switch (option) {
      case ExerciseOption.changeExercise:
        await _openEditSheet(context, ref, notifier);
      case ExerciseOption.addSet:
        await notifier.addSetToCurrent();
      case ExerciseOption.removeSet:
        // Confirm only when the removal will delete an already-logged set;
        // trimming a pending slot is low-stakes and needs no prompt.
        if (notifier.removeSetWouldDeleteLogged()) {
          final ok = await _confirm(
            context,
            title: 'Remove your last logged set?',
            message:
                'This deletes the last set you logged for ${exercise.exerciseName} and lowers the target by one.',
            confirmLabel: 'Remove set',
          );
          if (!ok) return;
        }
        await notifier.removeSetFromCurrent();
      case ExerciseOption.insertExercise:
        await _openInsertSheet(context, ref, notifier);
      case ExerciseOption.skip:
        final ok = await _confirm(
          context,
          title: 'Skip ${exercise.exerciseName}?',
          message:
              'It drops out of this session and stays out. Sets you already logged are kept.',
          confirmLabel: 'Skip exercise',
        );
        if (!ok) return;
        await notifier.skipCurrentExercise();
    }
  }

  Future<void> _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    ActiveWorkoutController notifier,
  ) async {
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    final result = await showExerciseEditSheet(
      context,
      unit: unit,
      initialName: exercise.exerciseName,
      initialSets: exercise.targetSets,
      initialRepsMin: exercise.targetRepsMin,
      initialRepsMax: exercise.targetRepsMax,
      initialWeightKg: exercise.defaultWeightKg,
      initialWeightStepKg: exercise.weightStepKg,
      initialDropCount: exercise.dropCount,
      // Workout-local edits never delete the queue slot.
      canDelete: false,
      // "REVERT TO PLAN" only makes sense for slots already overridden — and
      // never for inserted exercises (there's no plan slot behind them).
      canRevert: exercise.isOverridden && !exercise.isInserted,
    );
    if (result == null) return;
    if (result.revert) {
      await notifier.revertSubstitution(queueIdx);
      return;
    }
    await notifier.substituteExercise(
      queueIdx: queueIdx,
      exerciseName: result.name,
      targetSets: result.sets,
      targetRepsMin: result.repsMin,
      targetRepsMax: result.repsMax,
      defaultWeightKg: result.weightKg,
      weightStepKg: result.weightStepKg,
      dropCount: result.dropCount,
    );
  }

  Future<void> _openInsertSheet(
    BuildContext context,
    WidgetRef ref,
    ActiveWorkoutController notifier,
  ) async {
    final unit = ref.read(settingsProvider).unit ?? WeightUnit.kg;
    // Reuse the exercise editor in empty / "ADD EXERCISE" mode: the name field
    // autofocuses with autocomplete, and picking a known movement autofills
    // sets/reps/weight from history.
    final result = await showExerciseEditSheet(
      context,
      unit: unit,
      initialName: '',
      initialSets: 3,
      initialRepsMin: 8,
      initialRepsMax: 12,
      initialWeightKg: 0,
      initialWeightStepKg: null,
      canDelete: false,
      canRevert: false,
    );
    if (result == null || result.revert) return;
    await notifier.insertExercise(
      name: result.name,
      targetSets: result.sets,
      targetRepsMin: result.repsMin,
      targetRepsMax: result.repsMax,
      defaultWeightKg: result.weightKg,
      weightStepKg: result.weightStepKg,
      dropCount: result.dropCount,
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        message: Text(message),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
      ),
    );
    return result ?? false;
  }
}
