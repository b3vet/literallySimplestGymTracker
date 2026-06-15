import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../data/program_templates.dart';
import 'onboarding_fx.dart';

/// The finale: instead of a spinner, the chosen program visibly assembles —
/// day cards stack in, a plate "clacks" onto the barbell for each, exercise
/// counts tally up, and a final accent flash locks it to READY. Pure visual;
/// the host runs the DB seed + gate write + navigation on its own timeline and
/// keeps this on screen until it's ready to hand off into the editor.
class BuildFinale extends StatefulWidget {
  const BuildFinale({super.key, required this.template});
  final ProgramTemplate template;

  @override
  State<BuildFinale> createState() => _BuildFinaleState();
}

class _BuildFinaleState extends State<BuildFinale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );

  final _clacked = <int>{};
  bool _locked = false;

  // Timeline anchors.
  static const _barEnd = 0.16;
  static const _flashStart = 0.84;
  late final double _slice =
      (_flashStart - _barEnd) / widget.template.dayCount;

  @override
  void initState() {
    super.initState();
    _c.addListener(_haptics);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (reduceMotionOf(context)) {
        _c.value = 1; // skip the theater
      } else {
        _c.forward();
      }
    });
  }

  void _haptics() {
    final v = _c.value;
    for (var di = 0; di < widget.template.dayCount; di++) {
      final at = _barEnd + di * _slice;
      if (v >= at && !_clacked.contains(di)) {
        _clacked.add(di);
        HapticFeedback.lightImpact();
      }
    }
    if (v >= _flashStart && !_locked) {
      _locked = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_haptics);
    _c.dispose();
    super.dispose();
  }

  double _dayProgress(int di, double v) =>
      ((v - (_barEnd + di * _slice)) / _slice).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final rm = reduceMotionOf(context);
    final tpl = widget.template;
    return Container(
      color: t.surface.bg,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final ready = v >= _flashStart;
            // Running totals as days load.
            var lifts = 0;
            var sets = 0;
            for (var di = 0; di < tpl.dayCount; di++) {
              final p = rm ? 1.0 : _dayProgress(di, v);
              lifts += (p * tpl.days[di].exercises.length).round();
              sets += (p *
                      tpl.days[di].exercises
                          .fold<int>(0, (s, e) => s + e.sets))
                  .round();
            }
            return Stack(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: LsSpace.screen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: 16, height: 2, color: t.accent.accent),
                          const SizedBox(width: 10),
                          AnimatedSwitcher(
                            duration: LsMotion.base,
                            child: Text(
                              ready ? 'READY' : 'BUILDING',
                              key: ValueKey(ready),
                              style: LsType.monoMeta
                                  .copyWith(color: t.surface.text2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: LsGap.sub),
                      Text(
                        tpl.name.toUpperCase(),
                        style: LsType.displayL.copyWith(color: t.surface.text),
                      ),
                      const SizedBox(height: LsGap.loose),
                      // Barbell sleeve — one plate per day clacks on.
                      _Barbell(
                        dayCount: tpl.dayCount,
                        loaded: rm
                            ? tpl.dayCount
                            : _clacked.length,
                      ),
                      const SizedBox(height: LsGap.loose),
                      for (var di = 0; di < tpl.dayCount; di++) ...[
                        if (di > 0) const SizedBox(height: LsGap.sub),
                        _DayBuildCard(
                          name: tpl.days[di].name,
                          total: tpl.days[di].exercises.length,
                          progress: rm ? 1.0 : _dayProgress(di, v),
                        ),
                      ],
                      const SizedBox(height: LsGap.loose),
                      Text(
                        '$lifts LIFTS · $sets SETS LOADED',
                        textAlign: TextAlign.center,
                        style: LsType.monoMeta.copyWith(
                          color: t.surface.text3,
                          letterSpacing: 1.9,
                        ),
                      ),
                      const Spacer(flex: 3),
                    ],
                  ),
                ),
                // Lock flash sweep.
                if (!rm && v >= _flashStart)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity:
                            (1 - ((v - _flashStart) / (1 - _flashStart))) * 0.12,
                        child: Container(color: t.accent.accent),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Barbell extends StatelessWidget {
  const _Barbell({required this.dayCount, required this.loaded});
  final int dayCount;
  final int loaded;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return SizedBox(
      height: 26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(height: 4, width: double.infinity, color: t.surface.borderStrong),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < dayCount; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                AnimatedScale(
                  scale: i < loaded ? 1 : 0,
                  duration: LsMotion.base,
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: 12,
                    height: 26,
                    decoration: BoxDecoration(
                      color: t.accent.accent,
                      borderRadius: BorderRadius.circular(LsRadius.r1),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DayBuildCard extends StatelessWidget {
  const _DayBuildCard({
    required this.name,
    required this.total,
    required this.progress,
  });
  final String name;
  final int total;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final count = (progress * total).round();
    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - progress) * 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: t.surface.surface,
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(
              color: progress >= 1
                  ? t.accent.accent.withValues(alpha: 0.5)
                  : t.surface.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  style: LsType.displayM
                      .copyWith(color: t.surface.text, fontSize: 26),
                ),
              ),
              Text(
                '$count ${count == 1 ? 'LIFT' : 'LIFTS'}',
                style: LsType.monoMeta.copyWith(color: t.surface.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
