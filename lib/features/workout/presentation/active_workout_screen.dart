import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/weight.dart';
import '../application/active_workout_controller.dart';
import '../application/rest_timer_controller.dart';
import '../domain/active_session.dart';
import '../domain/workout_set.dart';
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
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error: $e'))),
      data: (session) {
        if (session == null) {
          // Workout finished or none — bounce to home.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/');
          });
          return const Scaffold();
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _confirmExit(session),
        ),
        title: Text(_formatDuration(elapsed)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: current == null
            ? _finishedPlaceholder(session)
            : _exerciseView(session, current, unit),
      ),
    );
  }

  Widget _exerciseView(
      ActiveSession session, PlannedExercise current, WeightUnit unit) {
    final setsLoggedForCurrent = session.loggedSets
        .where((s) => s.exerciseId == current.exerciseId)
        .toList();
    final allTargetsHit = setsLoggedForCurrent.length >= current.targetSets;
    return Column(
      children: [
        const RestTimerBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exercise ${session.cursor.exerciseIdx + 1} of ${session.queue.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(current.exerciseName.toUpperCase(),
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 4),
              Text(
                'Target: ${current.targetSets} × '
                '${current.targetRepsMin == current.targetRepsMax ? current.targetRepsMin : "${current.targetRepsMin}–${current.targetRepsMax}"} '
                '@ ${WeightConv.format(current.defaultWeightKg, unit)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: current.targetSets,
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
        _BottomBar(
          primaryLabel:
              allTargetsHit ? 'NEXT EXERCISE' : 'LOG SET',
          onPrimary: allTargetsHit
              ? () => ref
                  .read(activeSessionProvider.notifier)
                  .skipCurrentExercise()
              : () => _openSetLogSheet(current, setsLoggedForCurrent.length),
          secondaryLabel: 'Finish exercise',
          onSecondary:
              setsLoggedForCurrent.isEmpty || allTargetsHit
                  ? null
                  : () => ref
                      .read(activeSessionProvider.notifier)
                      .skipCurrentExercise(),
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
          const Icon(Icons.check_circle_outline,
              size: 64, color: AppColors.success),
          const SizedBox(height: 16),
          Text('All exercises done',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'Tap finish to save the workout.',
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
      initialWeightKg:
          lastWeight?.weightKg ?? current.defaultWeightKg,
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
      await ref.read(activeSessionProvider.notifier).abandon();
      if (mounted) context.go('/');
    }
  }

  Future<void> _finish(ActiveSession session) async {
    ref.read(restTimerProvider.notifier).dismiss();
    final sid = await ref.read(activeSessionProvider.notifier).finish();
    if (sid != null && mounted) {
      context.go('/workout/summary/$sid');
    }
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
    final textColor = set == null
        ? AppColors.textSecondary
        : AppColors.textPrimary;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                'Set $index',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            Expanded(
              child: Text(
                set == null
                    ? (isNext ? '— — —  (next)' : '— — —')
                    : '${WeightConv.format(set!.weightKg, unit)}  ×  ${set!.reps}  ·  RIR ${set!.rir}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: textColor,
                    ),
              ),
            ),
            if (set != null)
              const Icon(Icons.edit, size: 16, color: AppColors.textSecondary),
          ],
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
