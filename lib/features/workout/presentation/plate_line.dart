import 'package:flutter/material.dart';

import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../../../core/theme/app_theme.dart';
import '../application/plate_format.dart';
import '../domain/plate_math.dart';

/// A single passive line showing the per-side plate breakdown for the current
/// weight. Reused under the set-logger weight picker and on the active-workout
/// card. Read-only except for the optional bar-weight affordance ([onBarTap]),
/// which is the only tap target — the readout itself adds zero logging taps.
class PlateLine extends StatelessWidget {
  const PlateLine({
    super.key,
    required this.result,
    required this.unit,
    this.onBarTap,
    this.showEyebrow = true,
  });

  /// The solved breakdown (recompute synchronously as the weight wheel turns).
  final PlateResult result;
  final WeightUnit unit;

  /// Tap handler for the "BAR n" segment (opens the caller's bar chooser).
  /// Null ⇒ the eyebrow is non-interactive (e.g. the read-only card surface).
  final VoidCallback? onBarTap;

  /// When false, only the breakdown is shown without the "PER SIDE · BAR n"
  /// eyebrow (compact card placement where space is tight).
  final bool showEyebrow;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showEyebrow) _eyebrow(context, t),
        const SizedBox(width: 12),
        Expanded(child: _breakdown(t)),
      ],
    );
  }

  Widget _eyebrow(BuildContext context, LsTheme t) {
    final label = Text(
      PlateFormat.eyebrow(result.barKg, unit),
      style: LsType.monoMeta.copyWith(color: t.surface.text2),
    );
    if (onBarTap == null) return label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBarTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          const SizedBox(width: 6),
          Icon(Icons.fitness_center, size: 13, color: t.surface.text3),
        ],
      ),
    );
  }

  Widget _breakdown(LsTheme t) {
    // BAR ONLY / EMPTY BAR — a single muted token, right-aligned.
    if (result.barOnly) {
      return Text(
        result.belowBar ? 'EMPTY BAR' : 'BAR ONLY',
        textAlign: TextAlign.right,
        style: LsType.monoData.copyWith(color: t.surface.text2),
      );
    }

    final children = <Widget>[];
    if (!result.exact) {
      children.add(Text(
        '≈ ${PlateFormat.approxTotal(result, unit)}',
        style: LsType.monoData.copyWith(color: t.accent.accentHi),
      ));
      children.add(const SizedBox(width: 10));
    }
    children.add(Text(
      PlateFormat.plates_(result, unit),
      style: LsType.monoData.copyWith(color: t.accent.accent),
    ));
    if (!result.exact) {
      // How far short of the requested weight (honest-by-design, §4 mock).
      children.add(const SizedBox(width: 8));
      children.add(Text(
        '(−${PlateFormat.deltaNum(result, unit)})',
        style: LsType.monoMeta.copyWith(color: t.surface.text2),
      ));
    }

    // FittedBox keeps a long breakdown (many small plates) on one line.
    return Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
