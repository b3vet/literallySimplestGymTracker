import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
    final t = LsTheme.of(context);
    final current = session.currentExercise;
    final elapsed = DateTime.now().difference(session.startedAt);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;

    return Scaffold(
      backgroundColor: t.surface.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LsSpace.screen,
                vertical: 10,
              ),
              child: _HeaderRow(
                elapsed: elapsed,
                onClose: () => _confirmExit(session),
                onProgram: () => showProgramStatusSheet(context),
              ),
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
    ActiveSession session,
    PlannedExercise current,
    WeightUnit unit,
  ) {
    final t = LsTheme.of(context);
    final setsLoggedForCurrent = session.loggedSets
        .where((s) => s.exerciseId == current.exerciseId)
        .toList();
    final allTargetsHit = setsLoggedForCurrent.length >= current.targetSets;
    final canPrev = session.cursor.exerciseIdx > 0;
    final canNext = session.cursor.exerciseIdx < session.queue.length - 1;

    // Layout: the LOG SET CTA + sub-footer stay pinned at the bottom (they're
    // action controls, not content). Everything above scrolls as one block in
    // a SingleChildScrollView so the entire screen — eyebrow, name, pills,
    // chip row, set log rows — moves together when content overflows.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: LsGap.sub),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Eyebrow row — current lift left, exercise index right.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const EyebrowLabel('CURRENT LIFT'),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'EXERCISE',
                            style: LsType.monoMicro.copyWith(
                              color: t.surface.text3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                (session.cursor.exerciseIdx + 1)
                                    .toString()
                                    .padLeft(2, '0'),
                                style: LsType.displayM.copyWith(
                                  color: t.accent.accent,
                                  fontSize: 26,
                                ),
                              ),
                              Text(
                                '/${session.queue.length.toString().padLeft(2, '0')}',
                                style: LsType.monoMeta.copyWith(
                                  color: t.surface.text2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: LsGap.sub),
                  // Big exercise name.
                  Text(
                    current.exerciseName.toUpperCase(),
                    style: LsType.displayXL.copyWith(
                      color: t.surface.text,
                      fontSize: 62,
                      height: 0.9,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: LsGap.section),
                  // Meta pills row — bold numbers, regular label.
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      MetaPill(
                        value: '${current.targetSets}',
                        text: 'SETS',
                      ),
                      MetaPill(
                        value: current.targetRepsMin == current.targetRepsMax
                            ? '${current.targetRepsMin}'
                            : '${current.targetRepsMin}-${current.targetRepsMax}',
                        text: 'REPS',
                      ),
                      MetaPill(
                        value: _formatWeightNumber(
                          current.defaultWeightKg,
                          unit,
                        ),
                        text: unit.short,
                      ),
                    ],
                  ),
                  const SizedBox(height: LsGap.loose),
                  // Set chips row — horizontally scrollable when the count
                  // outruns the available width.
                  _SetChipsRow(
                    count: current.targetSets,
                    done: setsLoggedForCurrent.length,
                  ),
                  const SizedBox(height: LsGap.section),
                  // Set log rows — Column (not ListView) so they participate
                  // in the page-level scroll above.
                  for (var i = 0; i < current.targetSets; i++) ...[
                    if (i > 0) const SizedBox(height: LsGap.sub),
                    Builder(builder: (_) {
                      final set = i < setsLoggedForCurrent.length
                          ? setsLoggedForCurrent[i]
                          : null;
                      final isNext = set == null &&
                          i == setsLoggedForCurrent.length;
                      return _SetRow(
                        index: i + 1,
                        set: set,
                        unit: unit,
                        isNext: isNext,
                        onEdit: set == null
                            ? null
                            : () => _editSet(current, set, i),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: LsGap.sub),
          LsButton(
            label: allTargetsHit ? 'NEXT EXERCISE →' : 'LOG SET',
            onPressed: allTargetsHit
                ? () => ref.read(activeSessionProvider.notifier).goNext()
                : () => _openSetLogSheet(current, setsLoggedForCurrent.length),
            expand: true,
            minHeight: LsBox.cta,
          ),
          const SizedBox(height: 12),
          LsSubFooter(
            items: [
              LsSubFooterItem(
                label: '← PREV',
                onTap: canPrev
                    ? () => ref.read(activeSessionProvider.notifier).goPrev()
                    : null,
              ),
              // Surface the partial-finish / discard action sheet — `_confirmExit`
              // already handles both branches (Finish now → save + go to
              // summary; Discard → abandon + go home). The same flow is
              // triggered by the close-X up top, but having an explicit
              // FINISH WORKOUT here is the affordance the user expects.
              LsSubFooterItem(
                label: 'FINISH WORKOUT',
                onTap: () => _confirmExit(session),
                accent: true,
              ),
              LsSubFooterItem(
                label: 'NEXT →',
                onTap: canNext
                    ? () => ref.read(activeSessionProvider.notifier).goNext()
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  String _formatWeightNumber(double kg, WeightUnit unit) {
    final value = WeightConv.fromKg(kg, unit);
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  Widget _finishedPlaceholder(ActiveSession session) {
    final t = LsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent.accentDim,
                borderRadius: BorderRadius.circular(LsRadius.r3),
                border: Border.all(color: t.accent.accent),
              ),
              child: Icon(Icons.check, size: 44, color: t.accent.accent),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'ALL DONE.',
            textAlign: TextAlign.center,
            style: LsType.displayXL.copyWith(
              color: t.surface.text,
              fontSize: 56,
              height: 0.9,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap below to save the session.',
            textAlign: TextAlign.center,
            style: LsType.bodyM.copyWith(color: t.surface.text2),
          ),
          const Spacer(),
          LsButton(
            label: 'FINISH WORKOUT',
            onPressed: () => _finish(session),
            expand: true,
            minHeight: LsBox.cta,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _openSetLogSheet(
    PlannedExercise current,
    int setsAlreadyLogged,
  ) async {
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
    await ref
        .read(activeSessionProvider.notifier)
        .logSet(reps: result.reps, weightKg: result.weightKg, rir: result.rir);
    final restSeconds = ref.read(settingsProvider).restSeconds;
    if (restSeconds > 0) {
      ref.read(restTimerProvider.notifier).start(restSeconds);
    }
  }

  Future<void> _editSet(
    PlannedExercise current,
    WorkoutSet existing,
    int setIdxInExercise,
  ) async {
    final result = await showSetLogSheet(
      context,
      exercise: current,
      setNumber: setIdxInExercise + 1,
      initialReps: existing.reps,
      initialWeightKg: existing.weightKg,
      initialRir: existing.rir,
    );
    if (result == null) return;
    await ref
        .read(activeSessionProvider.notifier)
        .editSet(
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

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.elapsed,
    required this.onClose,
    required this.onProgram,
  });
  final Duration elapsed;
  final VoidCallback onClose;
  final VoidCallback onProgram;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LsIconSquare(icon: Icons.close, onTap: onClose, semanticLabel: 'Exit'),
        const Spacer(),
        Column(
          children: [
            Text(
              _fmt(elapsed),
              style: LsType.displayXL.copyWith(
                color: t.surface.text,
                fontSize: 56,
                height: 1.0,
              ),
            ),
            const SizedBox(height: LsGap.tight),
            Text(
              'ELAPSED',
              style: LsType.monoMeta.copyWith(color: t.surface.text2),
            ),
          ],
        ),
        const Spacer(),
        LsIconSquare(
          icon: Icons.list,
          onTap: onProgram,
          semanticLabel: 'Program',
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// Horizontal row of set chips for the current exercise.
class _SetChipsRow extends StatelessWidget {
  const _SetChipsRow({required this.count, required this.done});
  final int count;
  final int done;

  @override
  Widget build(BuildContext context) {
    // Single horizontal line that scrolls when the chips overflow the screen
    // width. The previous Wrap would push the page taller every time it spilled
    // to a new row — keeping it on one line means the chip row's vertical
    // footprint is constant no matter the target-set count.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            SetChip(
              index: i + 1,
              state: i < done
                  ? SetChipState.current
                  : (i == done ? SetChipState.current : SetChipState.pending),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
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
    final t = LsTheme.of(context);
    final logged = set != null;
    final accent = logged
        ? t.accent.accent
        : (isNext ? t.accent.accent : t.surface.border);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: accent, width: 1.0),
          ),
          foregroundDecoration: !logged && !isNext
              ? _DashedDecoration(color: t.surface.border)
              : null,
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  'SET ${index.toString().padLeft(2, '0')}',
                  style: LsType.monoMeta.copyWith(
                    color: t.surface.text2,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: logged
                    ? Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            WeightConv.format(
                              set!.weightKg,
                              unit,
                            ).toUpperCase(),
                            style: LsType.monoData.copyWith(
                              color: t.accent.accent,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '  ×  ',
                            style: LsType.monoMeta.copyWith(
                              color: t.surface.text2,
                            ),
                          ),
                          Text(
                            '${set!.reps}',
                            style: LsType.monoData.copyWith(
                              color: t.surface.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '· RIR ${set!.rir}',
                            style: LsType.monoMeta.copyWith(
                              color: t.surface.text2,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        isNext ? 'TAP "LOG SET" TO ENTER' : '— PENDING',
                        style: LsType.monoMeta.copyWith(
                          color: isNext ? t.accent.accent : t.surface.text3,
                          fontSize: 16,
                        ),
                      ),
              ),
              if (logged)
                Icon(Icons.edit_outlined, size: 16, color: t.surface.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter that draws a dashed border around the box (foregroundDecoration).
class _DashedDecoration extends Decoration {
  const _DashedDecoration({required this.color});
  final Color color;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedBoxPainter(color);
}

class _DashedBoxPainter extends BoxPainter {
  _DashedBoxPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final radius = const Radius.circular(LsRadius.r3);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, radius));
    final dashed = _dashPath(path, dashWidth: dashWidth, dashSpace: dashSpace);
    canvas.drawPath(dashed, paint);
  }

  static Path _dashPath(
    Path source, {
    required double dashWidth,
    required double dashSpace,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dashWidth).clamp(0, metric.length).toDouble();
        dest.addPath(metric.extractPath(dist, next), Offset.zero);
        dist = next + dashSpace;
      }
    }
    return dest;
  }
}

class _NoActiveWorkoutScaffold extends StatelessWidget {
  const _NoActiveWorkoutScaffold();
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return LsScreen(
      topbar: const LsTopbar(title: 'Workout'),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NO WORKOUT IN PROGRESS',
                style: LsType.displayM.copyWith(color: t.surface.text),
              ),
              const SizedBox(height: 12),
              Text(
                'Start one from the home screen.',
                textAlign: TextAlign.center,
                style: LsType.bodyM.copyWith(color: t.surface.text2),
              ),
              const SizedBox(height: 24),
              LsButton(label: 'HOME', onPressed: () => context.go('/')),
            ],
          ),
        ),
      ),
    );
  }
}
