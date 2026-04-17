import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../workout/application/active_workout_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeSession = ref.watch(activeSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Literally Simplest Gym Tracker'),
        titleTextStyle: Theme.of(context).textTheme.headlineSmall,
        actions: [
          IconButton(
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () => context.push('/tips'),
            tooltip: 'Tips',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (activeSession.value != null) ...[
                _ResumeBanner(onResume: () => context.push('/workout/active')),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: activeSession.value != null
                    ? () => context.push('/workout/active')
                    : () => context.push('/workout/start'),
                child: Text(
                  activeSession.value != null
                      ? 'RESUME WORKOUT'
                      : 'START WORKOUT',
                ),
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: 'Programs',
                onPressed: () => context.push('/programs'),
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: 'History',
                onPressed: () => context.push('/history'),
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: 'Stats',
                onPressed: () => context.push('/stats'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.onResume});
  final VoidCallback onResume;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onResume,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.play_arrow, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Workout in progress — tap to resume'),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
