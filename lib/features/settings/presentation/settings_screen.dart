import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Unit'),
          _Card(
            child: RadioGroup<WeightUnit>(
              groupValue: s.unit,
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setUnit(v);
                }
              },
              child: Column(
                children: [
                  for (final u in WeightUnit.values)
                    RadioListTile<WeightUnit>(
                      value: u,
                      activeColor: AppColors.primary,
                      tileColor: AppColors.surface,
                      title:
                          Text(u == WeightUnit.kg ? 'Kilograms' : 'Pounds'),
                      subtitle: Text(u.short),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader('Weight step'),
          _Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _WeightStepToggle(
                unit: s.unit ?? WeightUnit.kg,
                current: s.weightStep,
                onChanged: (step) =>
                    ref.read(settingsProvider.notifier).setWeightStep(step),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader('Rest timer'),
          _Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                tileColor: Colors.transparent,
                title: const Text('Default rest'),
                subtitle:
                    Text(s.restSeconds == 0 ? 'Disabled' : '${s.restSeconds}s'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary),
                onTap: () async {
                  final picked =
                      await _pickRestSeconds(context, s.restSeconds);
                  if (picked != null) {
                    await ref
                        .read(settingsProvider.notifier)
                        .setRestSeconds(picked);
                  }
                },
              ),
            ),
          ),
          if (Platform.isIOS) ...[
            const SizedBox(height: 24),
            _SectionHeader('Lock screen'),
            _Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.primary,
                  title: const Text('Live Activity'),
                  subtitle: const Text(
                      'Show the current exercise and rest timer on the lock '
                      'screen and Dynamic Island during a workout.'),
                  value: s.liveActivityEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setLiveActivityEnabled(v),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<int?> _pickRestSeconds(BuildContext context, int current) {
  const options = [0, 30, 60, 90, 120, 150, 180, 240, 300];
  final initial =
      options.indexOf(current).clamp(0, options.length - 1);
  var selectedIndex = initial;
  return showCupertinoModalPopup<int>(
    context: context,
    builder: (ctx) => Container(
      height: 280,
      color: AppColors.elevated,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Text('Default rest between sets',
              style: Theme.of(ctx).textTheme.bodyLarge),
          Expanded(
            child: CupertinoPicker(
              itemExtent: 40,
              useMagnifier: true,
              magnification: 1.1,
              scrollController:
                  FixedExtentScrollController(initialItem: initial),
              onSelectedItemChanged: (i) => selectedIndex = i,
              children: [
                for (final s in options)
                  Center(child: Text(s == 0 ? 'Off' : '${s}s')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, options[selectedIndex]),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: Text(title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              )),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _WeightStepToggle extends StatelessWidget {
  const _WeightStepToggle({
    required this.unit,
    required this.current,
    required this.onChanged,
  });
  final WeightUnit unit;
  final double current;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = unit == WeightUnit.kg ? const [0.5, 1.0] : const [1.0, 2.5];
    return SegmentedButton<double>(
      segments: [
        for (final o in options)
          ButtonSegment(
            value: o,
            label: Text(
              '${o == o.roundToDouble() ? o.toStringAsFixed(0) : o} ${unit.short}',
            ),
          ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.divider),
      ),
    );
  }
}
