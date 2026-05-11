import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/layout.dart';
import '../application/programs_provider.dart';
import '../domain/program.dart';

class ProgramsListScreen extends ConsumerWidget {
  const ProgramsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final programs = ref.watch(programsListProvider);
    return LsScreen(
      topbar: const LsTopbar(title: 'Programs'),
      footer: LsButton(
        label: '+ NEW PROGRAM',
        onPressed: () => _createProgram(context, ref),
        expand: true,
        minHeight: LsBox.fab,
      ),
      child: programs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? const _Empty()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Content-area eyebrow: the user explicitly asked for
                  // "LIBRARY · N" to live BELOW the header (it's a count of
                  // page content, not part of the title). Aligned right to
                  // match the home-screen treatment.
                  Align(
                    alignment: Alignment.centerRight,
                    child: EyebrowLabel('LIBRARY · ${list.length}'),
                  ),
                  const SizedBox(height: LsGap.sub),
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: LsGap.item),
                      itemBuilder: (context, i) => _ProgramTile(
                        program: list[i],
                        surfaceTextColor: t.surface.text,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _createProgram(BuildContext context, WidgetRef ref) async {
    final name = await promptName(context, title: 'NEW PROGRAM');
    if (name == null || name.isEmpty) return;
    final program = await ref.read(programDaoProvider).createProgram(name);
    ref.invalidate(programsListProvider);
    if (context.mounted) context.push('/programs/${program.id}');
  }
}

class _ProgramTile extends ConsumerWidget {
  const _ProgramTile({required this.program, required this.surfaceTextColor});
  final Program program;
  final Color surfaceTextColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final daysAsync = ref.watch(programDaysProvider(program.id));

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
      child: LsCard(
        onTap: () => context.push('/programs/${program.id}'),
        padding: LsPad.cardStd,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    program.name,
                    style: LsType.displayM.copyWith(color: t.surface.text),
                  ),
                  const SizedBox(height: 6),
                  daysAsync.maybeWhen(
                    data: (days) => Text(
                      '${days.length} ${days.length == 1 ? "DAY" : "DAYS"}',
                      style: LsType.monoMeta.copyWith(color: t.surface.text2),
                    ),
                    orElse: () => Text(
                      '—',
                      style: LsType.monoMeta.copyWith(color: t.surface.text3),
                    ),
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

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NO PROGRAMS YET',
              style: LsType.displayM.copyWith(color: t.surface.text),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap + to build your first.',
              textAlign: TextAlign.center,
              style: LsType.bodyM.copyWith(color: t.surface.text2),
            ),
          ],
        ),
      ),
    );
  }
}
