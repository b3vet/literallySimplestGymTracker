import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';

class UnitPickScreen extends ConsumerWidget {
  const UnitPickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    return Scaffold(
      backgroundColor: t.surface.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LsSpace.screen),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const EyebrowLabel('GET STARTED'),
              const SizedBox(height: LsGap.sub),
              Text(
                'PICK YOUR\nUNIT.',
                style: LsType.displayHome.copyWith(color: t.surface.text),
              ),
              const SizedBox(height: LsGap.sub),
              Text(
                'You can change this later in settings.',
                style: LsType.bodyM.copyWith(color: t.surface.text2),
              ),
              const Spacer(),
              _UnitCard(
                unit: WeightUnit.kg,
                title: 'KILOGRAMS',
                subtitle: 'KG · 0.5 KG STEPS',
                onTap: () => _choose(context, ref, WeightUnit.kg),
              ),
              const SizedBox(height: LsGap.item),
              _UnitCard(
                unit: WeightUnit.lb,
                title: 'POUNDS',
                subtitle: 'LB · 1 LB STEPS',
                onTap: () => _choose(context, ref, WeightUnit.lb),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _choose(
      BuildContext context, WidgetRef ref, WeightUnit u) async {
    await ref.read(settingsProvider.notifier).setUnit(u);
    if (context.mounted) context.go('/');
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final WeightUnit unit;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return LsCard(
      onTap: onTap,
      padding: LsPad.cardStd,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: LsType.displayM.copyWith(color: t.surface.text),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: LsType.monoMeta.copyWith(color: t.surface.text2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
        ],
      ),
    );
  }
}
