import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/layout.dart';
import '../../programs/application/programs_provider.dart';
import '../application/active_workout_controller.dart';
import '../domain/active_session.dart';

Future<void> showProgramStatusSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const LsSheet(child: _ProgramStatusSheet()),
  );
}

class _ProgramStatusSheet extends ConsumerWidget {
  const _ProgramStatusSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final async = ref.watch(activeSessionProvider);
    final session = async.value;
    if (session == null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No active workout',
            style: LsType.bodyM.copyWith(color: t.surface.text2),
          ),
        ),
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

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LsSheetHeader(eyebrow: 'PROGRAM', title: dayName),
          const SizedBox(height: LsGap.sub),
          Text(
            '$completed OF ${session.queue.length} DONE · '
            '${_formatDuration(elapsed)} ELAPSED',
            style: LsType.monoMeta.copyWith(
              color: t.surface.text2,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: LsGap.sub),
          Container(height: 1, color: t.surface.border),
          Flexible(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: session.queue.length,
              separatorBuilder: (_, _) =>
                  Container(height: 1, color: t.surface.border),
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
    final t = LsTheme.of(context);
    final repsLabel = exercise.targetRepsMin == exercise.targetRepsMax
        ? '${exercise.targetRepsMin}'
        : '${exercise.targetRepsMin}-${exercise.targetRepsMax}';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            _StateChip(state: state, index: index),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.exerciseName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LsType.displayM.copyWith(
                      color: state == _ExState.skipped
                          ? t.surface.text3
                          : t.surface.text,
                      fontSize: 22,
                      decoration: state == _ExState.skipped
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$setsLogged / ${exercise.targetSets} SETS · '
                    '$repsLabel REPS · '
                    '${WeightConv.format(exercise.defaultWeightKg, unit).toUpperCase()}',
                    style: LsType.monoMeta.copyWith(color: t.surface.text2),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state, required this.index});
  final _ExState state;
  final int index;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final (bg, fg) = switch (state) {
      _ExState.done => (t.accent.accent, t.accent.accentInk),
      _ExState.current => (t.accent.accentDim, t.accent.accent),
      _ExState.upcoming => (t.surface.surface, t.surface.text2),
      _ExState.skipped => (t.surface.surface, t.surface.text3),
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LsRadius.r2),
        border: Border.all(
          color: state == _ExState.done ? t.accent.accent : t.surface.border,
        ),
      ),
      child: state == _ExState.done
          ? Icon(Icons.check, size: 18, color: fg)
          : Text(
              index.toString().padLeft(2, '0'),
              style: LsType.monoMeta.copyWith(color: fg, fontSize: 13),
            ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}H ${m}M';
  return '${m}M';
}
