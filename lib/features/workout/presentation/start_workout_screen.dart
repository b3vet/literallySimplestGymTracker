import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
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
    final programs = ref.watch(programsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Start workout')),
      body: programs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No programs yet',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Create a program first, then come back here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go('/programs'),
                      child: const Text('Go to Programs'),
                    ),
                  ],
                ),
              ),
            );
          }
          _selectedProgram ??= list.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Program',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      )),
              const SizedBox(height: 8),
              _ProgramChips(
                programs: list,
                selected: _selectedProgram!,
                onSelected: (p) => setState(() => _selectedProgram = p),
              ),
              const SizedBox(height: 24),
              Text('Day',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      )),
              const SizedBox(height: 8),
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

class _ProgramChips extends StatelessWidget {
  const _ProgramChips({
    required this.programs,
    required this.selected,
    required this.onSelected,
  });
  final List<Program> programs;
  final Program selected;
  final ValueChanged<Program> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in programs)
          ChoiceChip(
            label: Text(p.name),
            selected: p.id == selected.id,
            onSelected: (_) => onSelected(p),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: p.id == selected.id
                  ? Colors.white
                  : AppColors.textPrimary,
            ),
            backgroundColor: AppColors.surface,
            side: BorderSide.none,
          ),
      ],
    );
  }
}

class _DaysForProgram extends ConsumerWidget {
  const _DaysForProgram({required this.programId, required this.onStart});
  final String programId;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(programDaysProvider(programId));
    return days.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (e, _) => Text('Failed to load days: $e'),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            'This program has no days. Add one in Programs.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final d in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onStart(d.id),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.name,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          const Icon(Icons.play_arrow,
                              color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
