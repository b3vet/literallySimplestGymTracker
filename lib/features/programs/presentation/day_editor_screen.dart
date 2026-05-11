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
import 'exercise_edit_sheet.dart';

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
      topbar: LsTopbar(title: dayName),
      footer: LsFabPair(
        leftLabel: _editing ? 'DONE' : 'EDIT',
        leftIcon: _editing ? Icons.check : Icons.edit_outlined,
        rightLabel: '+ EXERCISE',
        onLeft: () async {
          if (_editing) {
            setState(() => _editing = false);
            return;
          }
          final d = day.value;
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
        },
        onRight: () => _addExercise(context),
      ),
      child: exercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? _EmptyExercises(text2: t.surface.text2)
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
                            onDelete: () async {
                              await ref
                                  .read(programDaoProvider)
                                  .deleteProgramExercise(v.pe.id);
                              ref.invalidate(
                                  dayExercisesProvider(widget.dayId));
                            },
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
    await ref.read(programDaoProvider).addProgramExercise(
          programDayId: widget.dayId,
          exerciseName: result.name,
          targetSets: result.sets,
          targetRepsMin: result.repsMin,
          targetRepsMax: result.repsMax,
          defaultWeightKg: result.weightKg,
          weightStepKg: result.weightStepKg,
        );
    ref.invalidate(dayExercisesProvider(widget.dayId));
  }

  Future<void> _editExercise(
    BuildContext context,
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
      initialWeightStepKg: v.pe.weightStepKg,
      canDelete: true,
    );
    if (result == null) return;
    if (result.delete) {
      await ref.read(programDaoProvider).deleteProgramExercise(v.pe.id);
    } else {
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
              weightStepKg: result.weightStepKg,
            ),
          );
    }
    ref.invalidate(dayExercisesProvider(widget.dayId));
  }
}

class _ExerciseTile extends ConsumerWidget {
  const _ExerciseTile({
    required this.index,
    required this.view,
    required this.editing,
    required this.onTap,
    required this.onDelete,
  });
  final int index;
  final ProgramExerciseView view;
  final bool editing;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final pe = view.pe;
    final repsValue = pe.targetRepsMin == pe.targetRepsMax
        ? '${pe.targetRepsMin}'
        : '${pe.targetRepsMin}-${pe.targetRepsMax}';
    final weightValue = _weightValue(pe.defaultWeightKg, unit);

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
                  ],
                ),
              ],
            ),
          ),
          if (!editing)
            Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${pe.id}'),
      direction: editing ? DismissDirection.endToStart : DismissDirection.none,
      background: dismissBackground(),
      confirmDismiss: (_) async =>
          await confirmDelete(context, view.exerciseName) ?? false,
      onDismissed: (_) async => onDelete(),
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
