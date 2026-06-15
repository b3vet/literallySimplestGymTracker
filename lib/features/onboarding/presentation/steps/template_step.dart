import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spec.dart';
import '../../../../core/widgets/brand.dart';
import '../../data/program_templates.dart';
import '../onboarding_fx.dart';

/// Step 5 — the ending. A horizontally-snapping carousel of three rich template
/// cards; one tap selects, and the bottom CTA ("BUILD MY PROGRAM") turns the
/// choice into a seeded, editable program (see the finale).
class TemplateStep extends StatefulWidget {
  const TemplateStep({
    super.key,
    required this.isActive,
    required this.selectedId,
    required this.onSelect,
  });
  final bool isActive;
  final String? selectedId;
  final ValueChanged<ProgramTemplate> onSelect;

  @override
  State<TemplateStep> createState() => _TemplateStepState();
}

class _TemplateStepState extends State<TemplateStep>
    with TickerProviderStateMixin, StepEntrance<TemplateStep> {
  @override
  bool get isActive => widget.isActive;

  final _controller = PageController(viewportFraction: 0.86);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    widget.onSelect(kProgramTemplates[i]);
    if (_controller.hasClients && _page != i) {
      _controller.animateToPage(
        i,
        duration: LsMotion.base,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LsGap.tight),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Reveal(
                animation: entrance,
                start: 0.0,
                end: 0.22,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 16, height: 2, color: t.accent.accent),
                    const SizedBox(width: 10),
                    Text('ALMOST THERE',
                        style:
                            LsType.monoMeta.copyWith(color: t.surface.text2)),
                  ],
                ),
              ),
              const SizedBox(height: LsGap.sub),
              for (final (i, line)
                  in const ['CHOOSE A', 'STARTING PROGRAM.'].indexed)
                Reveal(
                  animation: entrance,
                  start: 0.04 + i * 0.06,
                  end: 0.26 + i * 0.06,
                  child: Text(line,
                      textAlign: TextAlign.right, style: onbHeadline(t)),
                ),
              const SizedBox(height: LsGap.tight),
              Reveal(
                animation: entrance,
                start: 0.24,
                end: 0.44,
                child: Text(
                  'Pick one. You can edit everything next.',
                  style: LsType.bodyS.copyWith(color: t.surface.text2),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LsGap.section),
        Expanded(
          child: Reveal(
            animation: entrance,
            start: 0.18,
            end: 0.52,
            dy: 22,
            child: PageView.builder(
              controller: _controller,
              itemCount: kProgramTemplates.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final tpl = kProgramTemplates[i];
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    var delta = 0.0;
                    if (_controller.hasClients &&
                        _controller.position.haveDimensions) {
                      delta = (_controller.page ?? _page.toDouble()) - i;
                    } else {
                      delta = (_page - i).toDouble();
                    }
                    final f = (1 - delta.abs()).clamp(0.0, 1.0);
                    final scale = 0.92 + 0.08 * f;
                    final opacity = 0.5 + 0.5 * f;
                    return Transform.scale(
                      scale: scale,
                      child: Opacity(opacity: opacity, child: child),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _TemplateCard(
                      template: tpl,
                      selected: tpl.id == widget.selectedId,
                      onTap: () => _select(i),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: LsGap.sub),
        Reveal(
          animation: entrance,
          start: 0.40,
          end: 0.60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < kProgramTemplates.length; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                AnimatedContainer(
                  duration: LsMotion.base,
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? t.accent.accent : t.surface.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: LsGap.tight),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });
  final ProgramTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LsMotion.base,
        curve: Curves.easeOut,
        padding: LsPad.cardSpacious,
        decoration: BoxDecoration(
          color: selected ? t.accentDimBg : t.surface.surface,
          borderRadius: BorderRadius.circular(LsRadius.r4),
          border: Border.all(
            color: selected ? t.accent.accent : t.surface.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header (fixed) ───────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    template.name.toUpperCase(),
                    style: LsType.displayM
                        .copyWith(color: t.surface.text, fontSize: 28),
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: LsMotion.fast,
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accent.accent,
                      borderRadius: BorderRadius.circular(LsRadius.r2),
                    ),
                    child: Icon(Icons.check,
                        size: 18, color: t.accent.accentInk),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              template.tagline,
              style: LsType.bodyS.copyWith(color: t.surface.text2),
            ),
            const SizedBox(height: LsGap.section),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                MetaPill(value: '${template.dayCount}', text: 'DAYS'),
                MetaPill(value: '${template.exerciseCount}', text: 'LIFTS'),
                MetaPill(value: template.repBandLabel, text: 'REPS'),
              ],
            ),
            const SizedBox(height: LsGap.section),
            Container(height: 1, color: t.surface.border),
            const SizedBox(height: LsGap.sub),
            // ── Full program — every day & exercise, vertically scrollable ─
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var di = 0; di < template.days.length; di++) ...[
                    if (di > 0) const SizedBox(height: LsGap.section),
                    _DayHeader(day: template.days[di], index: di + 1),
                    const SizedBox(height: LsGap.tight),
                    for (final e in template.days[di].exercises) ...[
                      _ExRow(
                        name: e.name,
                        detail: '${e.sets} × ${e.repsMin}–${e.repsMax}',
                      ),
                      const SizedBox(height: 6),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.index});
  final TemplateDay day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      children: [
        Container(width: 14, height: 2, color: t.accent.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'DAY $index · ${day.name}',
            style:
                LsType.monoMeta.copyWith(color: t.surface.text, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${day.exercises.length} LIFTS',
          style: LsType.monoMicro.copyWith(color: t.surface.text3),
        ),
      ],
    );
  }
}

class _ExRow extends StatelessWidget {
  const _ExRow({required this.name, required this.detail});
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LsType.bodyM.copyWith(color: t.surface.text),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          detail,
          style: LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 12),
        ),
      ],
    );
  }
}
