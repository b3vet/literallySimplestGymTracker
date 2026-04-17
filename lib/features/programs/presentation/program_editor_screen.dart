import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dialogs.dart';
import '../application/programs_provider.dart';
import '../domain/program_day.dart';

class ProgramEditorScreen extends ConsumerWidget {
  const ProgramEditorScreen({super.key, required this.programId});
  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(programProvider(programId));
    final days = ref.watch(programDaysProvider(programId));

    return Scaffold(
      appBar: AppBar(
        title: program.maybeWhen(
          data: (p) => Text(p?.name ?? 'Program'),
          orElse: () => const Text('Program'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final p = program.value;
              if (p == null) return;
              final name = await promptName(
                context,
                title: 'Rename program',
                initial: p.name,
              );
              if (name == null || name.isEmpty) return;
              await ref.read(programDaoProvider).renameProgram(p.id, name);
              ref.invalidate(programProvider(programId));
              ref.invalidate(programsListProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _addDay(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Day'),
      ),
      body: days.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? const _EmptyDays()
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: list.length,
                proxyDecorator: (child, _, _) => Material(
                  color: Colors.transparent,
                  child: child,
                ),
                onReorder: (oldIdx, newIdx) async {
                  final reordered = [...list];
                  if (newIdx > oldIdx) newIdx -= 1;
                  final moved = reordered.removeAt(oldIdx);
                  reordered.insert(newIdx, moved);
                  await ref.read(programDaoProvider).reorderDays(
                        programId,
                        reordered.map((d) => d.id).toList(),
                      );
                  ref.invalidate(programDaysProvider(programId));
                },
                itemBuilder: (context, i) {
                  final d = list[i];
                  return Padding(
                    key: ValueKey(d.id),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DayTile(programId: programId, day: d),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _addDay(BuildContext context, WidgetRef ref) async {
    final name = await promptName(context, title: 'Add day');
    if (name == null || name.isEmpty) return;
    final day = await ref.read(programDaoProvider).createDay(programId, name);
    ref.invalidate(programDaysProvider(programId));
    if (context.mounted) {
      context.push('/programs/$programId/days/${day.id}');
    }
  }
}

class _DayTile extends ConsumerWidget {
  const _DayTile({required this.programId, required this.day});
  final String programId;
  final ProgramDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('dismiss-${day.id}'),
      direction: DismissDirection.endToStart,
      background: dismissBackground(),
      confirmDismiss: (_) async =>
          await confirmDelete(context, day.name) ?? false,
      onDismissed: (_) async {
        await ref.read(programDaoProvider).deleteDay(day.id);
        ref.invalidate(programDaysProvider(programId));
      },
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              context.push('/programs/$programId/days/${day.id}'),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.drag_indicator,
                    color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    day.name,
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

class _EmptyDays extends StatelessWidget {
  const _EmptyDays();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No days yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Add a day like "Push" or "Pull" to get started.',
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
