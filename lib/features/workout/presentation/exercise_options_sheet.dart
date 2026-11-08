import 'package:flutter/material.dart';

import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/layout.dart';
import '../domain/active_session.dart';

/// The action a user picked from the in-workout exercise-options sheet. The
/// sheet itself is pure UI — it returns the choice and the caller
/// (`SwapExerciseButton`) orchestrates the follow-up (open the edit sheet,
/// add/remove a set, confirm + skip).
enum ExerciseOption {
  changeExercise,

  /// SOW-14: only offered when the slot has variants (base + variants).
  switchVariant,
  addSet,
  removeSet,
  insertExercise,
  skip,
}

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
        LsSheetHeader(
          eyebrow: 'EXERCISE OPTIONS',
          title: exercise.exerciseName,
        ),
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
        if (exercise.hasVariants && !exercise.skipped) ...[
          const SizedBox(height: LsGap.sub),
          _OptionRow(
            icon: Icons.alt_route,
            label: 'Switch variant',
            subtitle: 'Now: ${exercise.exerciseName}',
            onTap: () => Navigator.pop(context, ExerciseOption.switchVariant),
          ),
        ],
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

/// SOW-14: pick which member of the slot to run — its base or a variant. Lists
/// base first, then the variants in program order, the current one marked.
/// Returns the chosen `exerciseId`, or null when dismissed or the current one
/// was tapped. Same `LsSheet` + option-row language as the options menu.
Future<String?> showVariantPickerSheet(
  BuildContext context, {
  required PlannedExercise exercise,
  required WeightUnit unit,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LsSheet(
      child: _VariantPickerSheet(exercise: exercise, unit: unit),
    ),
  );
}

class _VariantPickerSheet extends StatelessWidget {
  const _VariantPickerSheet({required this.exercise, required this.unit});
  final PlannedExercise exercise;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final members = exercise.members;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LsSheetHeader(
          eyebrow: 'SWITCH VARIANT',
          title: members.isEmpty ? exercise.exerciseName : members.first.name,
        ),
        const SizedBox(height: LsGap.sub),
        Text(
          'REMAINING SETS CARRY OVER',
          style: LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 14),
        ),
        const SizedBox(height: LsGap.loose),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < members.length; i++) ...[
                  if (i > 0) const SizedBox(height: LsGap.sub),
                  _OptionRow(
                    key: ValueKey('variant-row-${members[i].exerciseId}'),
                    icon: members[i].isBase
                        ? Icons.fitness_center
                        : Icons.alt_route,
                    label: members[i].name,
                    subtitle: [
                      WeightConv.format(members[i].defaultWeightKg, unit),
                      if (members[i].isBase) 'base',
                      if (members[i].exerciseId == exercise.exerciseId)
                        'current',
                    ].join(' · '),
                    selected: members[i].exerciseId == exercise.exerciseId,
                    onTap: () => Navigator.pop(
                      context,
                      members[i].exerciseId == exercise.exerciseId
                          ? null
                          : members[i].exerciseId,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: LsGap.tight),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  /// Marks the current choice (variant picker): accent border + check.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final enabled = onTap != null;
    final tint = danger ? LsSignals.danger : t.accent.accent;
    final iconBg = danger
        ? LsSignals.danger.withValues(alpha: 0.12)
        : t.accent.accentDim;
    return Semantics(
      selected: selected,
      child: Opacity(
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
                border: Border.all(
                  color: selected ? t.accent.accent : t.surface.border,
                  width: selected ? 1.4 : 1,
                ),
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
                          style: LsType.monoMeta.copyWith(
                            color: t.surface.text2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  selected
                      ? Icon(Icons.check, size: 20, color: t.accent.accent)
                      : Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: t.surface.text3,
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
