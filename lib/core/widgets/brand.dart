import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small editorial-style "wordmark" used in app headers. Combines an orange
/// monogram (`LS`) with a thin caption — gives the screens a custom identity
/// instead of a generic AppBar title.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.caption = 'GYM TRACKER'});
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'LS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          caption.toUpperCase(),
          style: AppDisplay.eyebrow.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Editorial "eyebrow" label: small uppercase tracked text on top of a thin
/// accent stripe. Used to label sections without a heavy header.
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(
    this.label, {
    super.key,
    this.color = AppColors.textSecondary,
    this.stripeColor,
  });
  final String label;
  final Color color;
  final Color? stripeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 2,
          color: stripeColor ?? AppColors.primary,
        ),
        const SizedBox(width: 8),
        Text(label.toUpperCase(), style: AppDisplay.eyebrow.copyWith(color: color)),
      ],
    );
  }
}

/// Card with an accent strip on the left edge — a distinctive container style
/// that replaces generic surface containers across the app.
class AccentCard extends StatelessWidget {
  const AccentCard({
    super.key,
    required this.child,
    this.accent = AppColors.primary,
    this.background = AppColors.surface,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 16, 16),
    this.onTap,
  });
  final Widget child;
  final Color accent;
  final Color background;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final card = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
      ),
      child: Stack(
        children: [
          // Accent strip
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// A subtle full-bleed "ticker stripe": horizontal repeating dashes used as a
/// section divider. Cheap to render, gives the screen an editorial texture.
class TickerDivider extends StatelessWidget {
  const TickerDivider({super.key, this.color = AppColors.divider});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, c) {
          final n = (c.maxWidth / 8).floor();
          return Row(
            children: [
              for (var i = 0; i < n; i++) ...[
                Container(width: 4, height: 1, color: color),
                const SizedBox(width: 4),
              ],
            ],
          );
        },
      ),
    );
  }
}
