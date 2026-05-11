import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spec.dart';
import 'brand.dart';

/// Hairline divider (1px) using the surface `border` token.
class LsHairline extends StatelessWidget {
  const LsHairline({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Container(height: 1, color: color ?? t.surface.border);
  }
}

/// Topbar used on most screens. The screen title is `displayL` and right-
/// aligned. A back chip sits on the leading side; primary actions never live
/// here — they go in the FAB pair.
class LsTopbar extends StatelessWidget {
  const LsTopbar({
    super.key,
    required this.title,
    this.eyebrow,
    this.showBack = true,
    this.onBack,
    this.trailing,
  });
  final String title;
  final Widget? eyebrow;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack)
            LsIconSquare(
              icon: Icons.chevron_left,
              onTap: onBack ?? () => Navigator.maybeOf(context)?.maybePop(),
              semanticLabel: 'Back',
            )
          else
            const SizedBox(width: 40, height: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: eyebrow!,
                  ),
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: LsType.displayL.copyWith(color: t.surface.text),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Screen frame: a SafeArea + 16px horizontal padding column whose first child
/// is a topbar (optional) and whose body is supplied via `child`. Optional
/// `footer` renders pinned at the bottom (FAB pair etc.).
///
/// The body is separated from the topbar by [topGap] — defaults to
/// `LsGap.section` (16) so list-screens have a clear gap between the title
/// row and the first row of content.
class LsScreen extends StatelessWidget {
  const LsScreen({
    super.key,
    required this.child,
    this.topbar,
    this.footer,
    this.padding = const EdgeInsets.symmetric(horizontal: LsSpace.screen),
    this.bgOverride,
    this.topGap = LsGap.section,
  });
  final Widget child;
  final Widget? topbar;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final Color? bgOverride;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Scaffold(
      backgroundColor: bgOverride ?? t.surface.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (topbar != null) Padding(padding: padding, child: topbar),
            if (topbar != null) SizedBox(height: topGap),
            Expanded(
              child: Padding(padding: padding, child: child),
            ),
            if (footer != null)
              Padding(
                padding: padding.add(const EdgeInsets.only(bottom: 16)),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Footer FAB pair (used on screens 04/06/16/17). Ghost left + primary right.
///
/// The buttons use `LsBox.fab` (64pt) so they're tall enough to comfortably
/// host the new 18px button text plus 18pt vertical padding without
/// crowding.
class LsFabPair extends StatelessWidget {
  const LsFabPair({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.onLeft,
    required this.onRight,
    this.leftIcon,
    this.rightIcon,
    this.subRow,
    this.rightVariant = LsButtonVariant.primary,
  });
  final String leftLabel;
  final String rightLabel;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final IconData? leftIcon;
  final IconData? rightIcon;
  final Widget? subRow;
  final LsButtonVariant rightVariant;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: LsButton(
                label: leftLabel,
                icon: leftIcon,
                variant: LsButtonVariant.secondary,
                onPressed: onLeft,
                minHeight: LsBox.fab,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LsButton(
                label: rightLabel,
                icon: rightIcon,
                variant: rightVariant,
                onPressed: onRight,
                minHeight: LsBox.fab,
              ),
            ),
          ],
        ),
        if (subRow != null) ...[const SizedBox(height: 12), subRow!],
      ],
    );
  }
}

/// Bottom-sheet body wrapper. Provides:
///   • drag-handle bar (a 4×40 pill against the sheet's own background)
///   • sheet-tone surface fill + r5 top corners
///   • optional bottom-only safe-area + viewInsets adjustment for the keyboard
///
/// Use as the topmost widget inside every `showModalBottomSheet` `builder:`.
/// The handle reads from the surface palette so it stays visible against both
/// the dark and light sheet tones.
class LsSheet extends StatelessWidget {
  const LsSheet({
    super.key,
    required this.child,
    this.padding = LsPad.sheet,
    this.fillBackground = true,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool fillBackground;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: fillBackground
          ? BoxDecoration(
              color: t.surface.surface,
              borderRadius: LsRadius.sheet,
              border: Border(top: BorderSide(color: t.surface.border)),
            )
          : null,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.surface.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary / secondary / ghost / danger button. Sizes match the design (54px
/// minimum height, r3 radius, mono-uppercase Antonio button text).
enum LsButtonVariant { primary, secondary, ghost, danger }

class LsButton extends StatelessWidget {
  const LsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = LsButtonVariant.primary,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.minHeight = LsBox.button,
  });
  final String label;
  final VoidCallback? onPressed;
  final LsButtonVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool expand;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    late final Color bg;
    late final Color fg;
    Color? border;
    switch (variant) {
      case LsButtonVariant.primary:
        bg = t.accent.accent;
        fg = t.accent.accentInk;
      case LsButtonVariant.secondary:
        bg = t.surface.surface2;
        fg = t.surface.text;
        border = t.surface.borderStrong;
      case LsButtonVariant.ghost:
        bg = Colors.transparent;
        fg = t.surface.text;
      case LsButtonVariant.danger:
        bg = Colors.transparent;
        fg = LsSignals.danger;
        border = LsSignals.danger.withValues(alpha: 0.4);
    }
    final disabled = onPressed == null;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
        ],
        Text(label.toUpperCase(), style: LsType.button.copyWith(color: fg)),
        if (trailingIcon != null) ...[
          const SizedBox(width: 10),
          Icon(trailingIcon, size: 18, color: fg),
        ],
      ],
    );
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        child: InkWell(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          onTap: onPressed,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LsRadius.r3),
              border: border != null ? Border.all(color: border) : null,
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Mono sub-footer row (`← PREV · FINISH EXERCISE · NEXT →`) used under the
/// active workout FAB pair.
class LsSubFooter extends StatelessWidget {
  const LsSubFooter({super.key, required this.items});
  final List<LsSubFooterItem> items;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final item in items)
          InkWell(
            onTap: item.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text(
                item.label.toUpperCase(),
                style: LsType.monoMeta.copyWith(
                  fontSize: 16,
                  color: item.onTap == null
                      ? t.surface.text3
                      : (item.accent ? t.accent.accent : t.surface.text2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LsSubFooterItem {
  const LsSubFooterItem({required this.label, this.onTap, this.accent = false});
  final String label;
  final VoidCallback? onTap;
  final bool accent;
}

/// Card container: flat surface + hairline border + r3 corner.
class LsCard extends StatelessWidget {
  const LsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LsSpace.card),
    this.onTap,
    this.surfaceTone = LsSurfaceTone.surface,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final LsSurfaceTone surfaceTone;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final bg = switch (surfaceTone) {
      LsSurfaceTone.surface => t.surface.surface,
      LsSurfaceTone.surface2 => t.surface.surface2,
      LsSurfaceTone.surface3 => t.surface.surface3,
    };
    final card = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LsRadius.r3),
        border: Border.all(color: t.surface.border),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

enum LsSurfaceTone { surface, surface2, surface3 }

/// "Choice chip" — used in segmented controls (`KILOGRAMS / POUNDS`,
/// `DARK / LIGHT / AUTO`, weight step toggles). Stateless: the parent owns
/// selection.
class LsChoiceChip extends StatelessWidget {
  const LsChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.expand = false,
    this.height = LsBox.choiceChip,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final bg = selected ? t.accent.accent : t.surface.surface2;
    final fg = selected ? t.accent.accentInk : t.surface.text;
    final borderColor = selected ? t.accent.accent : t.surface.borderStrong;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (selected) ...[
          Icon(Icons.check, size: 16, color: fg),
          const SizedBox(width: 8),
        ],
        Text(
          label.toUpperCase(),
          style: LsType.button.copyWith(color: fg, fontSize: 20),
        ),
      ],
    );
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: borderColor),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Bottom-sheet header (mono eyebrow + display-M title row). Used at the top
/// of every modal sheet for visual consistency.
class LsSheetHeader extends StatelessWidget {
  const LsSheetHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.trailing,
  });
  final String eyebrow;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowLabel(eyebrow),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: LsType.displayM.copyWith(
                  color: t.surface.text,
                  fontSize: 28,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}
