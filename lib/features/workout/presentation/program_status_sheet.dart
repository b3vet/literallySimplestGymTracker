import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../../programs/application/programs_provider.dart';
import '../application/active_workout_controller.dart';
import '../domain/active_session.dart';

Future<void> showProgramStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.elevated,
    builder: (ctx) => const _ProgramStatusSheet(),
  );
}

class _ProgramStatusSheet extends ConsumerWidget {
  const _ProgramStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeSessionProvider);
    final session = async.value;
    if (session == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No active workout')),
      );
    }
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    final dayAsync = ref.watch(dayProvider(session.programDayId));
    final dayName = dayAsync.maybeWhen(
      data: (d) => d?.name ?? 'Workout',
      orElse: () => 'Workout',
    );

    final completed = _completedCount(session);
    final elapsed = DateTime.now().difference(session.startedAt);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                dayName.toUpperCase(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '$completed of ${session.queue.length} done '
                '· ${_formatDuration(elapsed)} elapsed',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: session.queue.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (ctx, i) {
                  final pe = session.queue[i];
                  final logged = session.loggedSets
                      .where((s) => s.exerciseId == pe.exerciseId)
                      .length;
                  final state = _stateOf(session, i, logged);
                  return _ExerciseRow(
                    index: i + 1,
                    exercise: pe,
                    setsLogged: logged,
                    unit: unit,
                    state: state,
                    onTap: () async {
                      await ref
                          .read(activeSessionProvider.notifier)
                          .goToExerciseIndex(i);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ExState { done, current, upcoming, skipped }

_ExState _stateOf(ActiveSession s, int i, int logged) {
  final cur = s.cursor.exerciseIdx;
  if (logged >= s.queue[i].targetSets) return _ExState.done;
  if (i == cur) return _ExState.current;
  if (i < cur) return _ExState.skipped;
  return _ExState.upcoming;
}

int _completedCount(ActiveSession s) {
  var n = 0;
  for (var i = 0; i < s.queue.length; i++) {
    final logged = s.loggedSets
        .where((x) => x.exerciseId == s.queue[i].exerciseId)
        .length;
    if (logged >= s.queue[i].targetSets) n++;
  }
  return n;
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.index,
    required this.exercise,
    required this.setsLogged,
    required this.unit,
    required this.state,
    required this.onTap,
  });

  final int index;
  final PlannedExercise exercise;
  final int setsLogged;
  final WeightUnit unit;
  final _ExState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final repsLabel = exercise.targetRepsMin == exercise.targetRepsMax
        ? '${exercise.targetRepsMin}'
        : '${exercise.targetRepsMin}–${exercise.targetRepsMax}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            _StateIcon(state: state, index: index),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.exerciseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: state == _ExState.current
                              ? FontWeight.w700
                              : FontWeight.w500,
                          decoration: state == _ExState.skipped
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$setsLogged / ${exercise.targetSets} sets · '
                    '$repsLabel reps · '
                    '${WeightConv.format(exercise.defaultWeightKg, unit)}',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state, required this.index});
  final _ExState state;
  final int index;

  @override
  Widget build(BuildContext context) {
    final (color, child) = switch (state) {
      _ExState.done => (
          AppColors.success,
          const Icon(Icons.check, size: 18, color: Colors.white)
        ),
      _ExState.current => (
          AppColors.primary,
          Text('$index',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ))
        ),
      _ExState.upcoming => (
          AppColors.surface,
          Text('$index',
              style: const TextStyle(color: AppColors.textSecondary))
        ),
      _ExState.skipped => (
          AppColors.surface,
          const Icon(Icons.remove, size: 16, color: AppColors.textSecondary)
        ),
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: state == _ExState.upcoming || state == _ExState.skipped
            ? Border.all(color: AppColors.divider)
            : null,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
