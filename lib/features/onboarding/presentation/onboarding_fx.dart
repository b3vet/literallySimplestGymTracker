// Shared motion primitives for the onboarding wizard.
//
// The whole wizard is built on one rule from the UX spec: motion layers on top
// of an always-interactive screen, and every animation collapses cleanly when
// the OS asks for reduced motion. These helpers encode that so each step stays
// readable instead of drowning in AnimationController boilerplate.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Whether the OS "reduce motion" accessibility setting is on. Every bespoke
/// animation in the wizard checks this and degrades to a static / single-fade
/// presentation (per DESIGN_SYSTEM §3.4).
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// One shared size for EVERY wizard step headline. The steps used to mix the
/// 76pt home-hero scale with the 38pt screen-title scale, which read as six
/// unrelated screens. A single size makes them feel like one instrument.
/// Tuned to fit the busiest step's content — change it here to rescale all.
const double kOnbHeadlineSize = 46;

/// The standard wizard-step headline style (condensed Antonio caps), coloured
/// for the current surface. Use everywhere a step renders its big title.
TextStyle onbHeadline(LsTheme t) => TextStyle(
      fontFamily: 'Antonio',
      fontWeight: FontWeight.w700,
      fontSize: kOnbHeadlineSize,
      height: 1.02,
      letterSpacing: -0.5,
      color: t.surface.text,
    );

/// A single element's staggered entrance: fade + a short directional "rise"
/// (the lift gesture applied to one widget), driven off a shared [animation]
/// over the [start]..[end] slice of its 0→1 range.
///
/// Under reduce-motion the child is shown immediately with no transform — the
/// host fades the whole step in once instead.
class Reveal extends StatelessWidget {
  const Reveal({
    super.key,
    required this.animation,
    required this.start,
    required this.end,
    required this.child,
    this.dy = 14,
    this.dx = 0,
    this.curve = Curves.easeOutCubic,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final Widget child;

  /// Vertical / horizontal travel (in logical px) the child covers as it
  /// fades in. Defaults echo the app's ~10px "lift".
  final double dy;
  final double dx;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) return child;
    final a = CurvedAnimation(
      parent: animation,
      curve: Interval(start.clamp(0, 1), end.clamp(0, 1), curve: curve),
    );
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, child) {
        final v = a.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx * (1 - v), dy * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }
}

/// A box that "fills" with a color from one edge as [t] goes 0→1 — used for
/// the LS monogram and the loop's index squares "powering on". At t=0 only the
/// hairline outline shows; at t=1 the box is a solid fill.
class FillWipe extends StatelessWidget {
  const FillWipe({
    super.key,
    required this.t,
    required this.fill,
    required this.size,
    required this.child,
    this.radius = LsRadius.r2,
    this.outline,
    this.alignment = Alignment.bottomCenter,
  });

  /// 0 → empty (outline only), 1 → fully filled.
  final double t;
  final Color fill;
  final double size;
  final Widget child;
  final double radius;
  final Color? outline;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final clamped = t.clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: outline != null ? Border.all(color: outline!) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: alignment,
              heightFactor: 1,
              child: FractionallySizedBox(
                heightFactor: clamped,
                widthFactor: 1,
                child: Container(color: fill),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Faint static instrument grid drawn behind the whole wizard so the
/// background is never a flat void. Matches the design system's 32px grid at
/// the `grid` token's very-low alpha.
class WizardGridBackdrop extends StatelessWidget {
  const WizardGridBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridPainter(t.surface.grid),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 32.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

/// Mixin for a wizard step's `State` that owns a single entrance controller and
/// (re)plays it whenever the step becomes the active page. Steps build eagerly
/// inside the host `PageView`, so the entrance must be gated on activation
/// rather than `initState` — otherwise an off-screen step would burn its
/// animation before the user ever sees it.
///
/// The State must expose [isActive] (typically `=> widget.isActive`).
mixin StepEntrance<T extends StatefulWidget>
    on State<T>, TickerProviderStateMixin<T> {
  bool get isActive;

  late final AnimationController entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isActive) entrance.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isActive && !entrance.isAnimating && entrance.value == 0) {
      entrance.forward();
    }
  }

  @override
  void dispose() {
    entrance.dispose();
    super.dispose();
  }
}
