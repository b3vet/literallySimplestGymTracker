import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spec.dart';

/// Editorial wordmark for the home header. The "LS" square uses the user's
/// accent fill; the "GYM TRACKER" caption is mono-meta in text-2.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.caption = 'GYM TRACKER'});
  final String caption;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: LsBox.brandLs,
          height: LsBox.brandLs,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.accent.accent,
            borderRadius: BorderRadius.circular(LsRadius.r3),
          ),
          child: Text(
            'LS',
            style: _antonioWeight(700).copyWith(
              color: t.accent.accentInk,
              fontSize: LsBox.brandLsLabel,
              letterSpacing: 0.6,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(width: LsGap.inline),
        Text(
          caption.toUpperCase(),
          style: LsType.monoMeta.copyWith(color: t.surface.text2, fontSize: 14),
        ),
      ],
    );
  }
}

/// Local helper that mirrors the `_antonio` factory in `app_theme.dart` —
/// `LsType` only exposes finished styles, but the LS monogram needs a tighter
/// `fontSize`/`letterSpacing` combination than any of them, so we construct
/// it inline. Antonio is registered as discrete weights in pubspec, so a
/// plain `fontWeight:` picks the right physical file.
TextStyle _antonioWeight(int wght) => TextStyle(
  fontFamily: 'Antonio',
  fontWeight: FontWeight.values[((wght.clamp(100, 900)) ~/ 100) - 1],
);

/// Editorial "eyebrow" label. Renders as `[accent stripe] LABEL` on a single
/// line. The stripe is drawn — do NOT prepend a literal `—` character.
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(
    this.label, {
    super.key,
    this.color,
    this.stripeColor,
    this.style,
  });
  final String label;
  final Color? color;
  final Color? stripeColor;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final textColor = color ?? t.surface.text2;
    final stripe = stripeColor ?? t.accent.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 2, color: stripe),
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: (style ?? LsType.monoMeta).copyWith(color: textColor),
        ),
      ],
    );
  }
}

/// Mono-meta pill used for stat tags. Splits the content into a **bold
/// numeric value** + a regular caption (e.g. `3 SETS`, `8-12 REPS`,
/// `60 KG`). The two halves share the pill but render at the same baseline
/// with different weights so the numeric data dominates visually.
class MetaPill extends StatelessWidget {
  const MetaPill({
    super.key,
    required this.value,
    required this.text,
    this.active = false,
  });

  /// Numeric/data portion — rendered bold. Examples: `3`, `8-12`, `60`.
  final String value;

  /// Regular label appearing after the value. Examples: `SETS`, `REPS`, `KG`.
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final fgValue = active ? t.accent.accentInk : t.surface.text;
    final fgText = active ? t.accent.accentInk : t.surface.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? t.accent.accent : t.surface.surface2,
        borderRadius: BorderRadius.circular(LsRadius.r2),
        border: Border.all(color: active ? t.accent.accent : t.surface.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value.toUpperCase(),
            style: LsType.monoData.copyWith(
              color: fgValue,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: LsType.monoMeta.copyWith(
              color: fgText,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered set indicator chip (`01`, `02`, …). State drives the visual
/// treatment — see `SetChipState`.
enum SetChipState { current, done, pending, skipped }

class SetChip extends StatelessWidget {
  const SetChip({
    super.key,
    required this.index,
    required this.state,
    this.onTap,
  });
  final int index;
  final SetChipState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final label = index.toString().padLeft(2, '0');
    late final Color bg;
    late final Color fg;
    late final Color borderColor;
    switch (state) {
      case SetChipState.current:
        bg = t.accent.accent;
        fg = t.accent.accentInk;
        borderColor = t.accent.accent;
      case SetChipState.done:
        bg = t.surface.surface;
        fg = t.surface.text;
        borderColor = t.surface.borderStrong;
      case SetChipState.pending:
        bg = t.surface.surface;
        fg = t.surface.text2;
        borderColor = t.surface.border;
      case SetChipState.skipped:
        bg = t.surface.surface;
        fg = t.surface.text3;
        borderColor = t.surface.border;
    }
    final chip = Container(
      width: LsBox.setChipW,
      height: LsBox.setChipH,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LsRadius.r2),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: LsType.monoData.copyWith(
          color: fg,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          decoration: state == SetChipState.skipped
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(LsRadius.r2),
      onTap: onTap,
      child: chip,
    );
  }
}

/// Square icon chip — back, close, settings, list. `LsBox.topbarIcon`-sized
/// (44pt) by default, surface background with hairline border, r3 corners.
/// Used as the topbar leading element across all screens.
class LsIconSquare extends StatelessWidget {
  const LsIconSquare({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
    this.size = LsBox.topbarIcon,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: t.surface.surface,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface.surface,
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: t.surface.border),
          ),
          child: Icon(
            icon,
            size: 22,
            color: t.surface.text,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}
