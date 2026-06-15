import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spec.dart';
import '../onboarding_fx.dart';

/// Step 4 — claim a color. Tapping a swatch writes the accent live (the whole
/// theme rebuilds) and an accent disc floods out from the tap to mask the hard
/// color-cut, so it reads as the color *spreading* through the app. Because we
/// collect accent here, the finale and the editor handoff bloom in the user's
/// own color.
class AccentStep extends StatefulWidget {
  const AccentStep({
    super.key,
    required this.isActive,
    required this.accent,
    required this.onSelect,
  });
  final bool isActive;
  final LsAccent accent;
  final ValueChanged<LsAccent> onSelect;

  @override
  State<AccentStep> createState() => _AccentStepState();
}

class _AccentStepState extends State<AccentStep>
    with TickerProviderStateMixin, StepEntrance<AccentStep> {
  @override
  bool get isActive => widget.isActive;

  final _stackKey = GlobalKey();

  late final AnimationController _flood = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  Offset? _floodOrigin;
  Color _floodColor = const Color(0x00000000);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _breathe.stop();
    } else if (!_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _flood.dispose();
    _breathe.dispose();
    super.dispose();
  }

  void _tap(LsAccentSpec spec, TapDownDetails details) {
    if (spec.id == widget.accent) return;
    HapticFeedback.mediumImpact();
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && !reduceMotionOf(context)) {
      setState(() {
        _floodOrigin = box.globalToLocal(details.globalPosition);
        _floodColor = spec.accent;
      });
      _flood.forward(from: 0);
    }
    widget.onSelect(spec.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Stack(
      key: _stackKey,
      children: [
        if (_floodOrigin != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _flood,
                builder: (context, _) => CustomPaint(
                  painter: _FloodPainter(
                    origin: _floodOrigin!,
                    color: _floodColor,
                    t: _flood.value,
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Reveal(
                    animation: entrance,
                    start: 0.0,
                    end: 0.22,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 16, height: 2, color: t.accent.accent),
                        const SizedBox(width: 10),
                        Text('MAKE IT YOURS',
                            style: LsType.monoMeta
                                .copyWith(color: t.surface.text2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: LsGap.sub),
                  for (final (i, line) in const ['PICK YOUR', 'COLOR.'].indexed)
                    Reveal(
                      animation: entrance,
                      start: 0.06 + i * 0.07,
                      end: 0.30 + i * 0.07,
                      child: Text(line, style: onbHeadline(t)),
                    ),
                ],
              ),
              const SizedBox(height: LsGap.sub),
              Reveal(
                animation: entrance,
                start: 0.26,
                end: 0.46,
                child: Text(
                  'Sets the accent across the whole app.',
                  style: LsType.bodyS.copyWith(color: t.surface.text2),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  for (final (i, spec) in lsAccents.indexed) ...[
                    if (i > 0) const SizedBox(width: LsGap.inline),
                    Expanded(
                      child: Reveal(
                        animation: entrance,
                        start: (0.20 + i * 0.06).clamp(0.0, 1.0),
                        end: (0.44 + i * 0.06).clamp(0.0, 1.0),
                        dy: 18,
                        child: _Swatch(
                          spec: spec,
                          selected: spec.id == widget.accent,
                          breathe: _breathe,
                          onTapDown: (d) => _tap(spec, d),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              Reveal(
                animation: entrance,
                start: 0.46,
                end: 0.66,
                child: const _BrandPreview(),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.spec,
    required this.selected,
    required this.breathe,
    required this.onTapDown,
  });
  final LsAccentSpec spec;
  final bool selected;
  final Animation<double> breathe;
  final GestureTapDownCallback onTapDown;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return GestureDetector(
      onTapDown: onTapDown,
      // onTap kept so the row has a tap target even where onTapDown handles it.
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: selected ? 1.06 : 1.0,
            duration: LsMotion.fast,
            curve: Curves.easeOut,
            child: AnimatedBuilder(
              animation: breathe,
              builder: (context, child) => AspectRatio(
                aspectRatio: 1,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected
                          ? t.surface.text.withValues(
                              alpha: 0.6 + breathe.value * 0.4)
                          : Colors.transparent,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(LsRadius.r3 + 4),
                  ),
                  child: child,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: spec.accent,
                  borderRadius: BorderRadius.circular(LsRadius.r3),
                ),
                child: selected
                    ? Icon(Icons.check, color: spec.accentInk, size: 20)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            spec.label.toUpperCase(),
            style: LsType.monoMicro.copyWith(
              color: selected ? t.surface.text : t.surface.text3,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ],
      ),
    );
  }
}

/// A miniature of the home hero so the user previews their color in context.
class _BrandPreview extends StatelessWidget {
  const _BrandPreview();
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.surface.surface,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        border: Border.all(color: t.surface.border),
      ),
      child: Row(
        children: [
          Container(width: 16, height: 2, color: t.accent.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TRAIN HEAVY.',
                    style: LsType.displayS
                        .copyWith(color: t.surface.text, fontSize: 22)),
                Text('LOG CLEAN.',
                    style:
                        LsType.displayS.copyWith(color: t.accent.accent, fontSize: 22)),
              ],
            ),
          ),
          Icon(Icons.bolt, color: t.accent.accent, size: 22),
        ],
      ),
    );
  }
}

class _FloodPainter extends CustomPainter {
  _FloodPainter({required this.origin, required this.color, required this.t});
  final Offset origin;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    var maxR = 0.0;
    for (final c in corners) {
      maxR = math.max(maxR, (c - origin).distance);
    }
    final r = Curves.easeOutCubic.transform(t) * maxR;
    final alpha = math.sin(t * math.pi) * 0.18;
    canvas.drawCircle(
      origin,
      r,
      Paint()..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_FloodPainter old) =>
      old.t != t || old.origin != origin || old.color != color;
}
