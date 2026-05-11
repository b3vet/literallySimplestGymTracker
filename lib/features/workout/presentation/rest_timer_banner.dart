import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
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
    // Self-driven 1Hz tick — the parent screen's rebuilds don't propagate to
    // a const ConsumerWidget unless its provider state changes, so we manage
    // our own redraw cadence here.
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
    final state = ref.watch(restTimerProvider);
    if (!state.running) return const SizedBox.shrink();
    final remaining = state.remaining;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rest · ${_fmt(remaining)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ),
          _RoundBtn(
            icon: Icons.remove,
            onTap: () => ref.read(restTimerProvider.notifier).adjust(-15),
          ),
          const SizedBox(width: 8),
          _RoundBtn(
            icon: Icons.add,
            onTap: () => ref.read(restTimerProvider.notifier).adjust(15),
          ),
          const SizedBox(width: 8),
          _RoundBtn(
            icon: Icons.close,
            onTap: () => ref.read(restTimerProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: AppColors.textPrimary),
      ),
    );
  }
}
