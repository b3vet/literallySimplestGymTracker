import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/layout.dart';
import '../application/programs_provider.dart';
import '../domain/program_day.dart';

class ProgramEditorScreen extends ConsumerStatefulWidget {
  const ProgramEditorScreen({super.key, required this.programId});
  final String programId;

  @override
  ConsumerState<ProgramEditorScreen> createState() =>
      _ProgramEditorScreenState();
}

class _ProgramEditorScreenState extends ConsumerState<ProgramEditorScreen> {
  bool _editing = false;

  /// One-time "your program is ready" coaching strip, shown only when the
  /// editor is reached straight out of the onboarding finale. Dismisses on the
  /// first interaction (or after a few idle seconds) and never returns.
  bool _showCoach = false;
  Timer? _coachTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final justOnboarded = ref.read(justOnboardedProgramIdProvider);
      if (justOnboarded == widget.programId) {
        // Consume the flag so it only ever fires once.
        ref.read(justOnboardedProgramIdProvider.notifier).set(null);
        setState(() => _showCoach = true);
        _coachTimer = Timer(
          const Duration(seconds: 7),
          () {
            if (mounted) setState(() => _showCoach = false);
          },
        );
      }
    });
  }

  void _dismissCoach() {
    _coachTimer?.cancel();
    if (_showCoach) setState(() => _showCoach = false);
  }

  void _startWorkout() {
    _dismissCoach();
    context.push('/workout/start');
  }

  @override
  void dispose() {
    _coachTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final program = ref.watch(programProvider(widget.programId));
    final days = ref.watch(programDaysProvider(widget.programId));

    final programName = program.maybeWhen(
      data: (p) => p?.name ?? 'PROGRAM',
      orElse: () => 'PROGRAM',
    );

    return LsScreen(
      topGap: LsGap.loose,
      topbar: LsTopbar(title: programName),
      footer: LsFabPair(
        leftLabel: _editing ? 'DONE' : 'EDIT',
        leftIcon: _editing ? Icons.check : Icons.edit_outlined,
        rightLabel: '+ DAY',
        onLeft: () async {
          if (_editing) {
            setState(() => _editing = false);
            return;
          }
          final p = program.value;
          if (p == null) return;
          final name = await promptName(
            context,
            title: 'RENAME PROGRAM',
            initial: p.name,
          );
          if (name == null || name.isEmpty) return;
          await ref.read(programDaoProvider).renameProgram(p.id, name);
          ref.invalidate(programProvider(widget.programId));
          ref.invalidate(programsListProvider);
        },
        onRight: () => _addDay(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CoachCaption(
            visible: _showCoach,
            onStartWorkout: _startWorkout,
          ),
          Expanded(
            child: Listener(
              // Only the day list dismisses the coach on interaction — NOT the
              // caption, or a pointer-down would tear down the START button
              // before its onTap could fire.
              onPointerDown: (_) {
                if (_showCoach) _dismissCoach();
              },
              child: days.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) => list.isEmpty
            ? _EmptyDays(text2: t.surface.text2)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Content-area eyebrow → page content, not topbar.
                  Align(
                    alignment: Alignment.centerRight,
                    child: EyebrowLabel('PROGRAM · ${list.length} DAYS'),
                  ),
                  const SizedBox(height: LsGap.sub),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: EdgeInsets.zero,
                      buildDefaultDragHandles: false,
                      itemCount: list.length,
                      proxyDecorator: (child, _, _) =>
                          Material(color: Colors.transparent, child: child),
                      onReorder: (oldIdx, newIdx) async {
                        final reordered = [...list];
                        if (newIdx > oldIdx) newIdx -= 1;
                        final moved = reordered.removeAt(oldIdx);
                        reordered.insert(newIdx, moved);
                        await ref.read(programDaoProvider).reorderDays(
                              widget.programId,
                              reordered.map((d) => d.id).toList(),
                            );
                        ref.invalidate(
                            programDaysProvider(widget.programId));
                      },
                      itemBuilder: (context, i) {
                        final d = list[i];
                        return Padding(
                          key: ValueKey(d.id),
                          // Day cards need more breathing room between them
                          // than the tighter `LsGap.item` gives.
                          padding: const EdgeInsets.only(bottom: LsGap.sub),
                          child: _DayTile(
                            index: i,
                            programId: widget.programId,
                            day: d,
                            editing: _editing,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              ),
              ),
            ),
          ],
        ),
    );
  }

  Future<void> _addDay(BuildContext context) async {
    final name = await promptName(context, title: 'ADD DAY');
    if (name == null || name.isEmpty) return;
    final day = await ref
        .read(programDaoProvider)
        .createDay(widget.programId, name);
    ref.invalidate(programDaysProvider(widget.programId));
    if (context.mounted) {
      context.push('/programs/${widget.programId}/days/${day.id}');
    }
  }
}

class _DayTile extends ConsumerWidget {
  const _DayTile({
    required this.index,
    required this.programId,
    required this.day,
    required this.editing,
  });
  final int index;
  final String programId;
  final ProgramDay day;
  final bool editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final exercisesAsync = ref.watch(dayExercisesProvider(day.id));

    final card = LsCard(
      onTap: editing
          ? null
          : () => context.push('/programs/$programId/days/${day.id}'),
      padding: LsPad.cardSpacious,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_indicator,
              color: t.surface.text3,
              size: 20,
            ),
          ),
          const SizedBox(width: LsGap.inline),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.name.toUpperCase(),
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: LsGap.tight),
                exercisesAsync.maybeWhen(
                  data: (list) => Text(
                    '${list.length} '
                    '${list.length == 1 ? "EXERCISE" : "EXERCISES"}',
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
          if (!editing)
            Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('dismiss-${day.id}'),
      direction: editing ? DismissDirection.endToStart : DismissDirection.none,
      background: dismissBackground(),
      confirmDismiss: (_) async =>
          await confirmDelete(context, day.name) ?? false,
      onDismissed: (_) async {
        await ref.read(programDaoProvider).deleteDay(day.id);
        ref.invalidate(programDaysProvider(programId));
      },
      child: card,
    );
  }
}

class _EmptyDays extends StatelessWidget {
  const _EmptyDays({required this.text2});
  final Color text2;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Add a day like "PUSH" or "PULL" to get started.',
          textAlign: TextAlign.center,
          style: LsType.bodyM.copyWith(color: text2),
        ),
      ),
    );
  }
}

/// First-arrival coach strip. Collapses (height + fade) to nothing once
/// dismissed, so the editor returns to its normal layout with no leftover gap.
class _CoachCaption extends StatelessWidget {
  const _CoachCaption({required this.visible, required this.onStartWorkout});
  final bool visible;
  final VoidCallback onStartWorkout;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return AnimatedSize(
      duration: LsMotion.base,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: LsMotion.base,
        opacity: visible ? 1 : 0,
        child: visible
            ? Padding(
                padding: const EdgeInsets.only(bottom: LsGap.sub),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: t.accentDimBg,
                    borderRadius: BorderRadius.circular(LsRadius.r3),
                    border: Border.all(
                      color: t.accent.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: t.accent.accent, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your program is ready. Tap any day below to '
                              'edit it.',
                              style:
                                  LsType.bodyS.copyWith(color: t.surface.text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // The explicit "way to start lifting" — straight to the
                      // day picker, since you can't start a workout from here.
                      Material(
                        color: t.accent.accent,
                        borderRadius: BorderRadius.circular(LsRadius.r2),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(LsRadius.r2),
                          onTap: onStartWorkout,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow,
                                    size: 18, color: t.accent.accentInk),
                                const SizedBox(width: 6),
                                Text(
                                  'START A WORKOUT',
                                  style: LsType.button.copyWith(
                                    color: t.accent.accentInk,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.arrow_forward,
                                    size: 16, color: t.accent.accentInk),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}
