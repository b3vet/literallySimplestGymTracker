import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_repository.dart' show WeightUnit;
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../export/application/share_service.dart';
import '../application/summary_card_renderer.dart';
import '../application/summary_text.dart';
import '../domain/workout_summary.dart';
import 'summary_card.dart';

/// Topbar share glyph for a completed workout. Tapping renders the branded PNG
/// card off-screen, builds the text block, and hands BOTH to the native share
/// sheet via [shareServiceProvider].
///
/// Async with a busy spinner; if the image capture fails it falls back to
/// sharing text only (never a half-share), and surfaces a one-shot error
/// snackbar on a hard failure. Reused by the post-workout summary screen and by
/// a completed session opened from history — both build a [WorkoutSummary] (via
/// [WorkoutSummary.fromSession]) and hand it here.
class ShareSummaryButton extends ConsumerStatefulWidget {
  const ShareSummaryButton({
    super.key,
    required this.summary,
    required this.unit,
  });

  /// Headless snapshot of the session to share (text + branded card).
  final WorkoutSummary summary;
  final WeightUnit unit;

  @override
  ConsumerState<ShareSummaryButton> createState() => _ShareSummaryButtonState();
}

class _ShareSummaryButtonState extends ConsumerState<ShareSummaryButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      final t = LsTheme.of(context);
      return SizedBox(
        width: LsBox.topbarIcon,
        height: LsBox.topbarIcon,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: t.accent.accent,
            ),
          ),
        ),
      );
    }
    return LsIconSquare(
      icon: Icons.ios_share,
      onTap: _share,
      semanticLabel: 'Share workout',
    );
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final text = buildSummaryText(widget.summary, widget.unit);
    final share = ref.read(shareServiceProvider);
    final accent = LsTheme.of(context).accent;
    final boundaryKey = GlobalKey();
    try {
      String? pngPath;
      try {
        pngPath = await renderCardOffstage<String>(
          context,
          card: SummaryCard(
            summary: widget.summary,
            unit: widget.unit,
            accent: accent,
            boundaryKey: boundaryKey,
          ),
          capture: () => renderSummaryCardPng(boundaryKey),
        );
      } catch (_) {
        // Image render is best-effort; fall through to a text-only share so the
        // user still gets to share something.
        pngPath = null;
      }

      await share.shareFiles(
        pngPath == null ? const <String>[] : [pngPath],
        text: text,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Couldn’t share. Please try again.')),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
