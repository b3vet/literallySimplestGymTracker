import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/layout.dart';
import '../../share/domain/workout_summary.dart';
import '../../share/presentation/share_summary_button.dart';
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
    final t = LsTheme.of(context);
    final data = ref.watch(sessionDetailProvider(sessionId));
    final prs = ref.watch(sessionPrsProvider(sessionId));
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;

    // Share affordance: present only once the session has loaded, so the card /
    // text are built from real data. A completed history session shares the same
    // branded card + text block as the post-workout summary (SOW-02b AC #1).
    final detail = data.value;
    Widget? shareButton;
    if (detail != null) {
      final summary = WorkoutSummary.fromSession(
        date: detail.session.startedAt,
        duration: detail.session.duration,
        sets: detail.sets,
        exerciseNames: detail.exerciseNames,
        prs: prs.value ?? const {},
        programName: detail.programName,
        dayName: detail.dayName,
      );
      shareButton = ShareSummaryButton(summary: summary, unit: unit);
    }

    return LsScreen(
      topbar: LsTopbar(title: 'Workout', trailing: shareButton),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (d) {
          if (d == null) {
            return Center(
              child: Text(
                'Workout not found.',
                style: LsType.bodyM.copyWith(color: t.surface.text2),
              ),
            );
          }
          final byExercise = <String, List<WorkoutSet>>{};
          for (final s in d.sets) {
            byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
          }
          final dateStr = DateFormat(
            'EEE · MMM d · HH:mm',
          ).format(d.session.startedAt);
          final durMin = d.session.duration.inMinutes;
          final totalVol = d.sets.fold<double>(
            0,
            (t, s) => t + s.weightKg * s.reps,
          );
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // Heading block — date, day name, stat strip.
              Align(
                alignment: Alignment.centerRight,
                child: EyebrowLabel(dateStr.toUpperCase()),
              ),
              const SizedBox(height: LsGap.sub),
              Text(
                (d.dayName ?? 'WORKOUT').toUpperCase(),
                textAlign: TextAlign.right,
                style: LsType.displayHero.copyWith(color: t.surface.text),
              ),
              const SizedBox(height: LsGap.section + LsGap.item),
              Wrap(
                spacing: LsGap.tight,
                runSpacing: LsGap.tight,
                alignment: WrapAlignment.end,
                children: [
                  MetaPill(value: '${d.sets.length}', text: 'SETS'),
                  MetaPill(
                    value: _weightValue(totalVol, unit),
                    text: unit.short,
                  ),
                  MetaPill(value: '$durMin', text: 'MIN'),
                ],
              ),
              const SizedBox(height: LsGap.loose),
              for (final entry in byExercise.entries)
                _ExerciseBlock(
                  exerciseId: entry.key,
                  name: d.exerciseNames[entry.key] ?? 'Exercise',
                  sets: entry.value,
                  unit: unit,
                  onEdit: (s) => _editSet(
                    context,
                    ref,
                    s,
                    d.exerciseNames[entry.key] ?? 'Exercise',
                  ),
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
      titleOverride: 'EDIT SET',
    );
    if (result == null) return;
    await ref
        .read(workoutDaoProvider)
        .updateSet(
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
    final t = LsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LsGap.item),
      child: LsCard(
        padding: LsPad.cardStd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: LsGap.tight),
              child: Text(
                name.toUpperCase(),
                style: LsType.displayM.copyWith(color: t.surface.text),
              ),
            ),
            for (var i = 0; i < sets.length; i++)
              _SetRow(
                index: i + 1,
                set: sets[i],
                unit: unit,
                onEdit: () => onEdit(sets[i]),
                onDelete: () => onDelete(sets[i]),
              ),
          ],
        ),
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
    final t = LsTheme.of(context);
    return InkWell(
      onTap: onEdit,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                'SET $index',
                style: LsType.monoMeta.copyWith(color: t.surface.text2),
              ),
            ),
            Expanded(
              child: Text(
                '${WeightConv.format(set.weightKg, unit).toUpperCase()}  ×  '
                '${set.reps}  ·  RIR ${set.rir}',
                style: LsType.monoData.copyWith(
                  color: t.surface.text,
                  fontSize: 18,
                ),
              ),
            ),
            Icon(Icons.edit_outlined, size: 14, color: t.surface.text3),
          ],
        ),
      ),
    );
  }
}

/// Numeric portion of a weight (no unit suffix) for MetaPill's bold-number
/// half.
String _weightValue(double kg, WeightUnit unit) {
  final v = WeightConv.fromKg(kg, unit);
  if (unit == WeightUnit.kg) {
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }
  return v.round().toString();
}
