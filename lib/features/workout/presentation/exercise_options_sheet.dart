import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/layout.dart';
import '../domain/active_session.dart';

/// The action a user picked from the in-workout exercise-options sheet. The
/// sheet itself is pure UI — it returns the choice and the caller
/// (`SwapExerciseButton`) orchestrates the follow-up (open the edit sheet,
/// add/remove a set, confirm + skip).
enum ExerciseOption { changeExercise, addSet, removeSet, insertExercise, skip }

/// Bottom sheet opened from the active-workout header's leading button. Branches
/// the single current exercise into a menu of mutations. Matches the app's
/// modal pattern (`LsSheet` + `LsSheetHeader`).
Future<ExerciseOption?> showExerciseOptionsSheet(
  BuildContext context, {
  required PlannedExercise exercise,
  required bool canAddSet,
  required bool canRemoveSet,
}) {
  return showModalBottomSheet<ExerciseOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LsSheet(
      child: _ExerciseOptionsSheet(
        exercise: exercise,
        canAddSet: canAddSet,
        canRemoveSet: canRemoveSet,
      ),
    ),
  );
}

class _ExerciseOptionsSheet extends StatelessWidget {
  const _ExerciseOptionsSheet({
    required this.exercise,
    required this.canAddSet,
    required this.canRemoveSet,
  });

  final PlannedExercise exercise;
  final bool canAddSet;
  final bool canRemoveSet;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final n = exercise.targetSets;
    final reps = exercise.targetRepsMin == exercise.targetRepsMax
        ? '${exercise.targetRepsMin}'
        : '${exercise.targetRepsMin}-${exercise.targetRepsMax}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LsSheetHeader(eyebrow: 'EXERCISE OPTIONS', title: exercise.exerciseName),
        const SizedBox(height: LsGap.sub),
        Text(
          'NOW $n ${n == 1 ? 'SET' : 'SETS'} · $reps REPS',
          style: LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 14),
        ),
        const SizedBox(height: LsGap.loose),
        _OptionRow(
          icon: Icons.swap_horiz,
          label: 'Change exercise',
          subtitle: 'Swap movement or edit targets',
          onTap: () => Navigator.pop(context, ExerciseOption.changeExercise),
        ),
        const SizedBox(height: LsGap.sub),
        _OptionRow(
          icon: Icons.add,
          label: 'Add set',
          subtitle: canAddSet ? 'Now $n → ${n + 1} sets' : 'At maximum',
          onTap: canAddSet
              ? () => Navigator.pop(context, ExerciseOption.addSet)
              : null,
        ),
        const SizedBox(height: LsGap.sub),
        _OptionRow(
          icon: Icons.remove,
          label: 'Remove set',
          subtitle: canRemoveSet
              ? 'Now $n → ${n - 1} sets'
              : 'Minimum 1 set — skip to drop',
          onTap: canRemoveSet
              ? () => Navigator.pop(context, ExerciseOption.removeSet)
              : null,
        ),
        const SizedBox(height: LsGap.sub),
        _OptionRow(
          icon: Icons.playlist_add,
          label: 'Insert exercise',
          subtitle: 'Add a movement after this one',
          onTap: () => Navigator.pop(context, ExerciseOption.insertExercise),
        ),
        const SizedBox(height: LsGap.sub),
        _OptionRow(
          icon: Icons.do_not_disturb_on_outlined,
          label: 'Skip exercise',
          subtitle: 'Drop from this session',
          danger: true,
          onTap: () => Navigator.pop(context, ExerciseOption.skip),
        ),
        const SizedBox(height: LsGap.tight),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final enabled = onTap != null;
    final tint = danger ? LsSignals.danger : t.accent.accent;
    final iconBg = danger
        ? LsSignals.danger.withValues(alpha: 0.12)
        : t.accent.accentDim;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: t.surface.surface2,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        child: InkWell(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LsRadius.r3),
              border: Border.all(color: t.surface.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(LsRadius.r2),
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: LsType.displayS.copyWith(
                          color: danger ? LsSignals.danger : t.surface.text,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle.toUpperCase(),
                        style: LsType.monoMeta.copyWith(color: t.surface.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: t.surface.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
