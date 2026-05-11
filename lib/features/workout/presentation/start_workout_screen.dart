import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../../programs/application/programs_provider.dart';
import '../../programs/domain/program.dart';
import '../application/active_workout_controller.dart';

class StartWorkoutScreen extends ConsumerStatefulWidget {
  const StartWorkoutScreen({super.key});
  @override
  ConsumerState<StartWorkoutScreen> createState() =>
      _StartWorkoutScreenState();
}

class _StartWorkoutScreenState extends ConsumerState<StartWorkoutScreen> {
  Program? _selectedProgram;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final programs = ref.watch(programsListProvider);
    return LsScreen(
      topGap: LsGap.loose,
      topbar: const LsTopbar(title: 'Start'),
      child: programs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NO PROGRAMS YET',
                      style: LsType.displayM.copyWith(color: t.surface.text),
                    ),
                    const SizedBox(height: LsGap.sub),
                    Text(
                      'Create a program first, then come back here.',
                      textAlign: TextAlign.center,
                      style: LsType.bodyM.copyWith(color: t.surface.text2),
                    ),
                    const SizedBox(height: LsGap.loose),
                    LsButton(
                      label: 'GO TO PROGRAMS',
                      onPressed: () => context.go('/programs'),
                      minHeight: LsBox.fab,
                    ),
                  ],
                ),
              ),
            );
          }
          _selectedProgram ??= list.first;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              // PROGRAM eyebrow right-aligned (matches design screenshot 15).
              Align(
                alignment: Alignment.centerRight,
                child: const EyebrowLabel('PROGRAM'),
              ),
              const SizedBox(height: LsGap.sub),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in list)
                    LsChoiceChip(
                      label: p.name.toUpperCase(),
                      selected: p.id == _selectedProgram!.id,
                      onTap: () => setState(() => _selectedProgram = p),
                      height: 60,
                    ),
                ],
              ),
              const SizedBox(height: LsGap.loose),
              const EyebrowLabel('DAY'),
              const SizedBox(height: LsGap.sub),
              _DaysForProgram(
                programId: _selectedProgram!.id,
                onStart: (dayId) => _start(dayId),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _start(String dayId) async {
    try {
      await ref.read(activeSessionProvider.notifier).start(dayId);
      if (mounted) context.go('/workout/active');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }
}

class _DaysForProgram extends ConsumerWidget {
  const _DaysForProgram({required this.programId, required this.onStart});
  final String programId;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final days = ref.watch(programDaysProvider(programId));
    return days.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text(
        'Failed to load days: $e',
        style: LsType.bodyM.copyWith(color: t.surface.text2),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            'This program has no days. Add one in Programs.',
            style: LsType.bodyM.copyWith(color: t.surface.text2),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < list.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: LsGap.sub),
                child: _DayCard(
                  index: i + 1,
                  dayId: list[i].id,
                  dayName: list[i].name,
                  onStart: () => onStart(list[i].id),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Aggregated metadata for the day card on the Start Workout screen.
class _DayMeta {
  const _DayMeta({
    required this.exerciseCount,
    required this.estimatedMin,
    required this.lastMin,
  });
  final int exerciseCount;
  final int estimatedMin;

  /// Duration of the last completed session of this day, in minutes. Null
  /// when this day has never been completed.
  final int? lastMin;
}

final _dayMetaProvider = FutureProvider.family.autoDispose<_DayMeta, String>(
  (ref, dayId) async {
    final programDao = ref.watch(programDaoProvider);
    final workoutDao = ref.watch(workoutDaoProvider);
    final exercises = await programDao.listProgramExercises(dayId);
    final restSec = ref.read(settingsProvider).restSeconds;
    // Rough budget: 30s per set for the lift itself + rest between sets.
    final estSec = exercises.fold<int>(
        0, (s, e) => s + e.pe.targetSets * (30 + (restSec.clamp(0, 300))));
    final last = await workoutDao.lastCompletedSessionForDay(dayId);
    return _DayMeta(
      exerciseCount: exercises.length,
      estimatedMin: (estSec / 60).round(),
      lastMin: last?.duration.inMinutes,
    );
  },
);

class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.index,
    required this.dayId,
    required this.dayName,
    required this.onStart,
  });
  final int index;
  final String dayId;
  final String dayName;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final metaAsync = ref.watch(_dayMetaProvider(dayId));
    final meta = metaAsync.value;
    String metaLine;
    if (meta == null) {
      metaLine = '— · — · —';
    } else {
      final exLabel = meta.exerciseCount == 1
          ? '1 EXERCISE'
          : '${meta.exerciseCount} EXERCISES';
      final estLabel = meta.estimatedMin == 0
          ? '~—'
          : '~${meta.estimatedMin}M';
      final lastLabel =
          meta.lastMin == null ? 'NEW' : 'LAST ${meta.lastMin}M';
      metaLine = '$exLabel · $estLabel · $lastLabel';
    }
    return LsCard(
      onTap: onStart,
      padding: LsPad.cardSpacious,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAY $index · ${dayName.toUpperCase()}',
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 30,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: LsGap.tight),
                Text(
                  metaLine,
                  style: LsType.monoMeta.copyWith(color: t.surface.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: LsGap.inline),
          _PlayButton(onTap: onStart),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: t.accent.accent,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: SizedBox(
          width: LsBox.playButton,
          height: LsBox.playButton,
          child: Icon(Icons.play_arrow,
              color: t.accent.accentInk, size: 26),
        ),
      ),
    );
  }
}

