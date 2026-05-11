import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../application/rest_timer_controller.dart';

class RestTimerBanner extends ConsumerStatefulWidget {
  const RestTimerBanner({super.key});
  @override
  ConsumerState<RestTimerBanner> createState() => _RestTimerBannerState();
}

class _RestTimerBannerState extends ConsumerState<RestTimerBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 1Hz self-driven tick. The parent's rebuilds don't propagate to a const
    // ConsumerWidget unless its provider state changes — we own our cadence.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final state = ref.watch(restTimerProvider);
    if (!state.running) return const SizedBox.shrink();
    final remaining = state.remaining;
    // Bottom margin separates the banner from the content below.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          LsSpace.screen, LsGap.tight, LsSpace.screen, LsGap.section),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: t.accent.accentDim,
          borderRadius: BorderRadius.circular(LsRadius.r3),
          border: Border.all(color: t.accent.accent),
        ),
        child: Row(
          children: [
            Icon(Icons.timer, color: t.accent.accent, size: 28),
            const SizedBox(width: LsGap.inline),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REST',
                  style: LsType.monoMeta.copyWith(
                    color: t.surface.text2,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fmt(remaining),
                  style: LsType.displayM.copyWith(
                    color: t.accent.accent,
                    fontSize: 36,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            const Spacer(),
            _Chip(
              label: '-15s',
              onTap: () => ref.read(restTimerProvider.notifier).adjust(-15),
            ),
            const SizedBox(width: LsGap.tight),
            _Chip(
              label: '+15s',
              onTap: () => ref.read(restTimerProvider.notifier).adjust(15),
            ),
            const SizedBox(width: LsGap.tight),
            _Chip(
              label: 'Cancel',
              danger: true,
              onTap: () => ref.read(restTimerProvider.notifier).dismiss(),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final fg = danger ? LsSignals.danger : t.surface.text;
    return Material(
      color: t.surface.surface2,
      borderRadius: BorderRadius.circular(LsRadius.r2),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r2),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: t.surface.border),
            borderRadius: BorderRadius.circular(LsRadius.r2),
          ),
          child: Text(
            label,
            style: LsType.monoMeta.copyWith(color: fg, fontSize: 14),
          ),
        ),
      ),
    );
  }
}
