import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Custom page transition used app-wide in [appRouterProvider]. Replaces
/// Material's default slide-from-end (and Cupertino's right-to-left
/// reveal) with a **"lift"**:
///
///   - Incoming page rises ~1.2% of its height, scales 97% → 100%, fades
///     0 → 1. Curve: `easeOutCubic`.
///   - Outgoing page drops to 96% scale and dims to 40% opacity. Curve:
///     `easeInCubic`.
///   - 240ms forward, 200ms reverse — fast enough that a quick tapper
///     never feels held up, slow enough that the motion reads as
///     intentional.
///
/// The combined effect is a quick depth shift, as if the new screen is
/// rising into focus while the previous one settles behind it. It fits
/// the heavy / industrial / monospace aesthetic of the app (think
/// barbell coming off the floor) and avoids the horizontal sweep that
/// every Material app shares.
///
/// Used uniformly across the router so the navigation language stays
/// consistent. For modal-feeling routes (Summary, Onboarding) the
/// vertical lift reads especially well — those screens "appear" rather
/// than "arrive from the side".
Page<T> liftPage<T>({required Widget child, LocalKey? key, String? name}) {
  return CustomTransitionPage<T>(
    key: key,
    name: name,
    child: child,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Curves are split into forward/reverse so a *pop* feels like the
      // opposite of a push, not just a rewind of the push curve.
      final inCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final outCurve = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeInCubic,
        reverseCurve: Curves.easeOutCubic,
      );

      // Incoming motion — driven by `animation`. This page entering.
      // SlideTransition's offset is in fractions of the child size, so
      // (0, 0.012) ≈ 10px on a typical phone — present but unobtrusive.
      final inScale = Tween<double>(begin: 0.97, end: 1.0).animate(inCurve);
      final inOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(inCurve);
      final inOffset = Tween<Offset>(
        begin: const Offset(0, 0.012),
        end: Offset.zero,
      ).animate(inCurve);

      // Outgoing motion — driven by `secondaryAnimation`. This page is
      // being pushed *under* another page. We dim and shrink slightly so
      // a brief depth/stack effect lands, then the new page sits on top.
      final outScale = Tween<double>(begin: 1.0, end: 0.96).animate(outCurve);
      final outOpacity = Tween<double>(begin: 1.0, end: 0.4).animate(outCurve);

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
    },
  );
}
