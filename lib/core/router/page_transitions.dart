import 'dart:math' show max;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Custom page used app-wide in [appRouterProvider]. Replaces Material's
/// default slide-from-end (and Cupertino's right-to-left reveal) with a
/// **"lift"**:
///
///   - Incoming page rises ~1.2% of its height, scales 97% → 100%, fades
///     0 → 1. Curve: `easeOutCubic`.
///   - Outgoing page drops to 96% scale and dims to 40% opacity. Curve:
///     `easeInCubic`.
///   - 340ms forward, 300ms reverse — fast enough that a quick tapper
///     never feels held up, slow enough that the motion reads as
///     intentional.
///
/// The combined effect is a quick depth shift, as if the new screen is
/// rising into focus while the previous one settles behind it. It fits
/// the heavy / industrial / monospace aesthetic of the app (think
/// barbell coming off the floor) and avoids the horizontal sweep that
/// every Material app shares.
///
/// On top of the lift, every page also gets an **interactive iOS-style
/// edge-swipe-back** gesture (drag from the left screen edge to pop). The
/// drag drives the route's own animation controller backwards, so the lift
/// plays in reverse under the finger; releasing past the midpoint (or with
/// enough velocity) completes the pop, otherwise it springs back. This is
/// a faithful reimplementation of Flutter's Cupertino back gesture, wired
/// to our lift transition instead of the horizontal Cupertino slide.
///
/// Used uniformly across the router so the navigation language stays
/// consistent. For modal-feeling routes (Summary, Onboarding) the
/// vertical lift reads especially well — those screens "appear" rather
/// than "arrive from the side".
///
/// Kept as a free function so existing call sites (`liftPage(key:, child:)`)
/// don't need to change; it just constructs a [LiftPage].
Page<T> liftPage<T>({required Widget child, LocalKey? key, String? name}) {
  return LiftPage<T>(key: key, name: name, child: child);
}

/// Declarative [Page] backing the lift transition. Used directly by go_router
/// via `pageBuilder:`.
class LiftPage<T> extends Page<T> {
  const LiftPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _LiftPageRoute<T>(this);
}

class _LiftPageRoute<T> extends PageRoute<T> {
  _LiftPageRoute(LiftPage<T> page) : super(settings: page);

  LiftPage<T> get _page => settings as LiftPage<T>;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: _page.child,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // While a back-swipe is underway, drop the easing curves so the page
    // tracks the finger linearly (matches Cupertino's `linearTransition`).
    final bool linear = popGestureInProgress;
    return _liftTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      linear: linear,
      // The edge-swipe detector wraps the content *inside* the transition so
      // the hit area travels with the page.
      child: _SwipeBackDetector<T>(
        enabledCallback: () => popGestureEnabled,
        onStartPopGesture: () => _startPopGesture<T>(this),
        child: child,
      ),
    );
  }

  static _SwipeBackController<T> _startPopGesture<T>(_LiftPageRoute<T> route) {
    assert(route.popGestureEnabled);
    return _SwipeBackController<T>(
      navigator: route.navigator!,
      controller: route.controller!, // protected access from within the route
      getIsActive: () => route.isActive,
      getIsCurrent: () => route.isCurrent,
    );
  }
}

/// The lift effect itself. Split out so it can be driven either by curved
/// animations (normal push/pop) or linearly (during an interactive swipe).
Widget _liftTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required bool linear,
  required Widget child,
}) {
  // Curves are split into forward/reverse so a *pop* feels like the opposite
  // of a push, not just a rewind of the push curve. During a drag we bypass
  // the curve entirely so motion is 1:1 with the finger.
  final Animation<double> inDriver = linear
      ? animation
      : CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
  final Animation<double> outDriver = linear
      ? secondaryAnimation
      : CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeInCubic,
          reverseCurve: Curves.easeOutCubic,
        );

  // Incoming motion — driven by `animation`. This page entering.
  // SlideTransition's offset is in fractions of the child size, so
  // (0, 0.012) ≈ 10px on a typical phone — present but unobtrusive.
  final inScale = Tween<double>(begin: 0.97, end: 1.0).animate(inDriver);
  final inOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(inDriver);
  final inOffset = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).animate(inDriver);

  // Outgoing motion — driven by `secondaryAnimation`. This page is being
  // pushed *under* another page. We dim and shrink slightly so a brief
  // depth/stack effect lands, then the new page sits on top.
  final outScale = Tween<double>(begin: 1.0, end: 0.96).animate(outDriver);
  final outOpacity = Tween<double>(begin: 1.0, end: 0.4).animate(outDriver);

  return FadeTransition(
    opacity: inOpacity,
    child: SlideTransition(
      position: inOffset,
      child: ScaleTransition(
        scale: inScale,
        child: FadeTransition(
          opacity: outOpacity,
          child: ScaleTransition(scale: outScale, child: child),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  EDGE-SWIPE BACK GESTURE
// ─────────────────────────────────────────────────────────────────────────────
//
// A faithful reimplementation of Flutter's (private) Cupertino back gesture,
// wired to our own [_LiftPageRoute] so we keep the lift transition while
// gaining the native left-edge swipe-to-pop. Built entirely on public APIs
// (HorizontalDragGestureRecognizer + the route's AnimationController), so it's
// independent of Cupertino internals.

const double _kBackGestureWidth = 20.0;
const double _kMinFlingVelocity = 1.0; // Screen widths per second.
const Duration _kDroppedSwipePageAnimationDuration = Duration(
  milliseconds: 350,
);

/// Catches a drag starting at the leading screen edge and hands it to a
/// [_SwipeBackController], which drives the route's animation controller.
class _SwipeBackDetector<T> extends StatefulWidget {
  const _SwipeBackDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final Widget child;
  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_SwipeBackController<T>> onStartPopGesture;

  @override
  State<_SwipeBackDetector<T>> createState() => _SwipeBackDetectorState<T>();
}

class _SwipeBackDetectorState<T> extends State<_SwipeBackDetector<T>> {
  _SwipeBackController<T>? _backGestureController;
  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // If torn down mid-drag, let the navigator know the gesture ended.
    if (_backGestureController != null) {
      final controller = _backGestureController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller!.navigator.mounted) {
          controller.navigator.didStopUserGesture();
        }
      });
      _backGestureController = null;
    }
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _backGestureController?.dragUpdate(
      _convertToLogical(details.primaryDelta! / context.size!.width),
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    _backGestureController?.dragEnd(
      _convertToLogical(
        details.velocity.pixelsPerSecond.dx / context.size!.width,
      ),
    );
    _backGestureController = null;
  }

  void _handleDragCancel() {
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
  }

  double _convertToLogical(double value) {
    return switch (Directionality.of(context)) {
      TextDirection.rtl => -value,
      TextDirection.ltr => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    // Devices with a notch get a wider edge-drag area on the notched side.
    final double dragAreaWidth = switch (Directionality.of(context)) {
      TextDirection.rtl => MediaQuery.paddingOf(context).right,
      TextDirection.ltr => MediaQuery.paddingOf(context).left,
    };
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0.0,
          width: max(dragAreaWidth, _kBackGestureWidth),
          top: 0.0,
          bottom: 0.0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

/// Drives the route's [AnimationController] in response to drag input. Works
/// in logical coordinates: 0.0 = previous page (dismissed), 1.0 = this page on
/// top.
class _SwipeBackController<T> {
  _SwipeBackController({
    required this.navigator,
    required this.controller,
    required this.getIsActive,
    required this.getIsCurrent,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsActive;
  final ValueGetter<bool> getIsCurrent;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    // Curve eyeballed against native iOS.
    const Curve animationCurve = Curves.fastEaseInToSlowEaseOut;
    final bool isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      // Already navigated away from (e.g. a programmatic pop landed mid-drag):
      // direction depends only on whether it's still in the stack.
      animateForward = getIsActive();
    } else if (velocity.abs() >= _kMinFlingVelocity) {
      // Released with enough horizontal velocity — fling in that direction.
      animateForward = velocity <= 0;
    } else {
      // Otherwise settle to whichever side is closer.
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      controller.animateTo(
        1.0,
        duration: _kDroppedSwipePageAnimationDuration,
        curve: animationCurve,
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      if (controller.isAnimating) {
        controller.animateBack(
          0.0,
          duration: _kDroppedSwipePageAnimationDuration,
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      // Hold userGestureInProgress true until the settle finishes so the
      // transition curve doesn't snap mid-flight.
      late AnimationStatusListener statusCallback;
      statusCallback = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(statusCallback);
      };
      controller.addStatusListener(statusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
