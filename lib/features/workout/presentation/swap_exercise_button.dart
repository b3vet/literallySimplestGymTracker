import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../programs/presentation/exercise_edit_sheet.dart';
import '../application/active_workout_controller.dart';
import '../domain/active_session.dart';

/// Topbar-style swap/edit button rendered in the leading slot of the
/// active workout header. Sized 44×44 to match the other topbar icons
/// (`LsIconSquare`). Tapping opens the standard exercise-edit sheet
/// pre-populated with the current [PlannedExercise] values; on save the
/// controller writes a session-scoped override (the program template
/// stays untouched). When the slot is already overridden, the button
/// adopts the accent border / icon tint so the user can see at a glance
/// that this slot has been substituted.
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
        onTap: () => _openSheet(context, ref),
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
            Icons.swap_horiz,
            size: 22,
            color: overridden ? t.accent.accent : t.surface.text,
            semanticLabel: 'Change exercise',
          ),
        ),
      ),
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
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
      // Workout-local edits never delete the queue slot.
      canDelete: false,
      // "REVERT TO PLAN" only makes sense for slots already overridden — for
      // unmodified slots, hiding it keeps the sheet tidy.
      canRevert: exercise.isOverridden,
    );
    if (result == null) return;
    final notifier = ref.read(activeSessionProvider.notifier);
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
    );
  }
}
