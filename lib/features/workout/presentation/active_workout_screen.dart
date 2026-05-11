import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../application/active_workout_controller.dart';
import '../application/rest_timer_controller.dart';
import '../domain/active_session.dart';
import '../domain/workout_set.dart';
import 'program_status_sheet.dart';
import 'rest_timer_banner.dart';
import 'set_log_sheet.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});
  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  Timer? _ticker;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeSessionProvider);
    return async.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (session) {
        if (session == null) {
          if (_exiting) return const Scaffold();
          return const _NoActiveWorkoutScaffold();
        }
        return _buildScaffold(session);
      },
    );
  }

  Widget _buildScaffold(ActiveSession session) {
    final current = session.currentExercise;
    final elapsed = DateTime.now().difference(session.startedAt);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _HeaderBar(
              elapsed: elapsed,
              onClose: () => _confirmExit(session),
              onProgram: () => showProgramStatusSheet(context),
            ),
            const RestTimerBanner(),
            Expanded(
              child: current == null
                  ? _finishedPlaceholder(session)
                  : _exerciseView(session, current, unit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exerciseView(
      ActiveSession session, PlannedExercise current, WeightUnit unit) {
    final setsLoggedForCurrent = session.loggedSets
        .where((s) => s.exerciseId == current.exerciseId)
        .toList();
    final allTargetsHit = setsLoggedForCurrent.length >= current.targetSets;
    final canPrev = session.cursor.exerciseIdx > 0;
    final canNext = session.cursor.exerciseIdx < session.queue.length - 1;
    final completedCount = _completedCount(session);

    return Column(
      children: [
        // Hero block — exercise index + name
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    (session.cursor.exerciseIdx + 1)
                        .toString()
                        .padLeft(2, '0'),
                    style: AppDisplay.megaNumber.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '/ ${session.queue.length.toString().padLeft(2, '0')}',
                      style: AppDisplay.stat.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '$completedCount DONE',
                      style: AppDisplay.eyebrow,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const EyebrowLabel('Current lift'),
              const SizedBox(height: 8),
              Text(
                current.exerciseName.toUpperCase(),
                style: AppDisplay.hero,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MetaPill(label: '${current.targetSets} SETS'),
                  const SizedBox(width: 8),
                  _MetaPill(
                    label: current.targetRepsMin == current.targetRepsMax
                        ? '${current.targetRepsMin} REPS'
                        : '${current.targetRepsMin}–${current.targetRepsMax} REPS',
                  ),
                  const SizedBox(width: 8),
                  _MetaPill(
                    label: WeightConv.format(current.defaultWeightKg, unit)
                        .toUpperCase(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _ExerciseDots(session: session),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: TickerDivider(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            itemCount: current.targetSets,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final set = i < setsLoggedForCurrent.length
                  ? setsLoggedForCurrent[i]
                  : null;
              return _LoggedSetRow(
                index: i + 1,
                set: set,
                unit: unit,
                isNext: set == null && i == setsLoggedForCurrent.length,
                onEdit: set == null ? null : () => _editSet(current, set, i),
              );
            },
          ),
        ),
        _NavigatorBar(canPrev: canPrev, canNext: canNext, ref: ref),
        _BottomBar(
          primaryLabel: allTargetsHit ? 'NEXT EXERCISE →' : 'LOG SET',
          onPrimary: allTargetsHit
              ? () => ref.read(activeSessionProvider.notifier).goNext()
              : () => _openSetLogSheet(current, setsLoggedForCurrent.length),
          secondaryLabel: 'Finish exercise',
          onSecondary: setsLoggedForCurrent.isEmpty || allTargetsHit
              ? null
              : () => ref.read(activeSessionProvider.notifier).goNext(),
        ),
      ],
    );
  }

  Widget _finishedPlaceholder(ActiveSession session) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Center(
            child: Icon(Icons.check_circle, size: 88, color: AppColors.success),
          ),
          const SizedBox(height: 24),
          Text('ALL DONE.',
              textAlign: TextAlign.center,
              style: AppDisplay.hero.copyWith(color: AppColors.success)),
          const SizedBox(height: 8),
          Text(
            'Tap below to save the session.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => _finish(session),
            child: const Text('FINISH WORKOUT'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _openSetLogSheet(
      PlannedExercise current, int setsAlreadyLogged) async {
    final lastWeight = await ref
        .read(workoutDaoProvider)
        .lastSetForExercise(current.exerciseId);
    if (!mounted) return;
    final result = await showSetLogSheet(
      context,
      exercise: current,
      setNumber: setsAlreadyLogged + 1,
      initialReps: null,
      initialWeightKg: lastWeight?.weightKg ?? current.defaultWeightKg,
      initialRir: 0,
    );
    if (result == null) return;
    await ref.read(activeSessionProvider.notifier).logSet(
          reps: result.reps,
          weightKg: result.weightKg,
          rir: result.rir,
        );
    final restSeconds = ref.read(settingsProvider).restSeconds;
    if (restSeconds > 0) {
      ref.read(restTimerProvider.notifier).start(restSeconds);
    }
  }

  Future<void> _editSet(
      PlannedExercise current, WorkoutSet existing, int setIdxInExercise) async {
    final result = await showSetLogSheet(
      context,
      exercise: current,
      setNumber: setIdxInExercise + 1,
      initialReps: existing.reps,
      initialWeightKg: existing.weightKg,
      initialRir: existing.rir,
    );
    if (result == null) return;
    await ref.read(activeSessionProvider.notifier).editSet(
          existing.copyWith(
            reps: result.reps,
            weightKg: result.weightKg,
            rir: result.rir,
          ),
        );
  }

  Future<void> _confirmExit(ActiveSession session) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Exit workout?'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'finish'),
            child: const Text('Finish now'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard workout'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (action == 'finish') {
      if (!mounted) return;
      await _finish(session);
    } else if (action == 'discard') {
      _exiting = true;
      await ref.read(activeSessionProvider.notifier).abandon();
      if (mounted) context.go('/');
    }
  }

  Future<void> _finish(ActiveSession session) async {
    _exiting = true;
    ref.read(restTimerProvider.notifier).dismiss();
    final sid = await ref.read(activeSessionProvider.notifier).finish();
    if (!mounted) return;
    if (sid != null) {
      context.go('/workout/summary/$sid');
    } else {
      context.go('/');
    }
  }
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

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.elapsed,
    required this.onClose,
    required this.onProgram,
  });
  final Duration elapsed;
  final VoidCallback onClose;
  final VoidCallback onProgram;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: onClose,
            tooltip: 'Exit',
          ),
          const Spacer(),
          Column(
            children: [
              Text(_fmt(elapsed), style: AppDisplay.stat),
              Text('ELAPSED',
                  style: AppDisplay.eyebrow
                      .copyWith(color: AppColors.textMuted, fontSize: 9)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.format_list_bulleted,
                color: AppColors.textSecondary),
            onPressed: onProgram,
            tooltip: 'Program',
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _NavigatorBar extends StatelessWidget {
  const _NavigatorBar({
    required this.canPrev,
    required this.canNext,
    required this.ref,
  });
  final bool canPrev;
  final bool canNext;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          _NavBtn(
            label: '← PREV',
            enabled: canPrev,
            onTap: () =>
                ref.read(activeSessionProvider.notifier).goPrev(),
          ),
          const SizedBox(width: 12),
          _NavBtn(
            label: 'NEXT →',
            enabled: canNext,
            onTap: () =>
                ref.read(activeSessionProvider.notifier).goNext(),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: enabled ? AppColors.surface : AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoActiveWorkoutScaffold extends StatelessWidget {
  const _NoActiveWorkoutScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('NO WORKOUT IN PROGRESS', style: AppDisplay.eyebrow),
              const SizedBox(height: 12),
              Text(
                'Start one from the home screen.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('HOME'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseDots extends ConsumerWidget {
  const _ExerciseDots({required this.session});
  final ActiveSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: session.queue.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final pe = session.queue[i];
          final logged = session.loggedSets
              .where((s) => s.exerciseId == pe.exerciseId)
              .length;
          final isCurrent = i == session.cursor.exerciseIdx;
          final isDone = logged >= pe.targetSets;
          final isSkipped = !isDone && i < session.cursor.exerciseIdx;

          final Color fill;
          final Color border;
          final Color text;
          if (isDone) {
            fill = AppColors.success.withValues(alpha: 0.15);
            border = AppColors.success;
            text = AppColors.success;
          } else if (isCurrent) {
            fill = AppColors.primary;
            border = AppColors.primary;
            text = Colors.white;
          } else if (isSkipped) {
            fill = Colors.transparent;
            border = AppColors.divider;
            text = AppColors.textMuted;
          } else {
            fill = Colors.transparent;
            border = AppColors.divider;
            text = AppColors.textSecondary;
          }

          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => ref
                .read(activeSessionProvider.notifier)
                .goToExerciseIndex(i),
            child: Container(
              width: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: 1.5),
              ),
              child: Text(
                (i + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  color: text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.5,
                  decoration:
                      isSkipped ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoggedSetRow extends StatelessWidget {
  const _LoggedSetRow({
    required this.index,
    required this.set,
    required this.unit,
    required this.isNext,
    required this.onEdit,
  });
  final int index;
  final WorkoutSet? set;
  final WeightUnit unit;
  final bool isNext;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final logged = set != null;
    final accentColor = logged
        ? AppColors.primary
        : (isNext ? AppColors.primary.withValues(alpha: 0.5) : AppColors.divider);
    final bg = logged ? AppColors.surface : AppColors.surface.withValues(alpha: 0.5);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor, width: 1),
          ),
          child: Row(
            children: [
              Text(
                'SET ${index.toString().padLeft(2, '0')}',
                style: AppDisplay.mono.copyWith(
                  color: logged ? AppColors.textSecondary : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: logged
                    ? Row(
                        children: [
                          Text(
                            WeightConv.format(set!.weightKg, unit),
                            style: AppDisplay.stat,
                          ),
                          Text('  ×  ',
                              style: TextStyle(color: AppColors.textMuted)),
                          Text(
                            '${set!.reps}',
                            style: AppDisplay.stat,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'RIR ${set!.rir}',
                            style: AppDisplay.mono,
                          ),
                        ],
                      )
                    : Text(
                        isNext ? 'TAP "LOG SET" TO ENTER' : '—  pending',
                        style: AppDisplay.mono,
                      ),
              ),
              if (logged)
                const Icon(Icons.edit_outlined,
                    size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 64,
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondary,
                child: Text(secondaryLabel!.toUpperCase()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
