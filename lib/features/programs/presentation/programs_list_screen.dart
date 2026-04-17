import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../application/programs_provider.dart';
import '../domain/program.dart';

class ProgramsListScreen extends ConsumerWidget {
  const ProgramsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programs = ref.watch(programsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _createProgram(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: programs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? const _Empty()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _ProgramTile(program: list[i]),
              ),
      ),
    );
  }

  Future<void> _createProgram(BuildContext context, WidgetRef ref) async {
    final name = await promptName(context, title: 'New program');
    if (name == null || name.isEmpty) return;
    final program = await ref.read(programDaoProvider).createProgram(name);
    ref.invalidate(programsListProvider);
    if (context.mounted) context.push('/programs/${program.id}');
  }
}

class _ProgramTile extends ConsumerWidget {
  const _ProgramTile({required this.program});
  final Program program;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(program.id),
      direction: DismissDirection.endToStart,
      background: dismissBackground(),
      confirmDismiss: (_) async =>
          await confirmDelete(context, program.name) ?? false,
      onDismissed: (_) async {
        await ref.read(programDaoProvider).deleteProgram(program.id);
        ref.invalidate(programsListProvider);
      },
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/programs/${program.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    program.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center,
                size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text('No programs yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first program.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
