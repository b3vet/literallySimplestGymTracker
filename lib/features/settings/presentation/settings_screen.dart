import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final s = ref.watch(settingsProvider);
    final unit = s.unit ?? WeightUnit.kg;
    return LsScreen(
      topbar: const LsTopbar(title: 'Settings'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Section(
            title: 'UNIT',
            child: _UnitRow(
              current: unit,
              onChange: (u) =>
                  ref.read(settingsProvider.notifier).setUnit(u),
            ),
          ),
          const SizedBox(height: LsGap.loose),
          _Section(
            title: 'REST TIMER',
            child: Material(
              color: t.surface.surface,
              borderRadius: BorderRadius.circular(LsRadius.r3),
              child: InkWell(
                borderRadius: BorderRadius.circular(LsRadius.r3),
                onTap: () async {
                  final picked = await _pickRestSeconds(context, s.restSeconds);
                  if (picked != null) {
                    await ref
                        .read(settingsProvider.notifier)
                        .setRestSeconds(picked);
                  }
                },
                child: Container(
                  padding: LsPad.cardStd,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(LsRadius.r3),
                    border: Border.all(color: t.surface.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Default rest',
                              style: LsType.displayM.copyWith(
                                color: t.surface.text,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              s.restSeconds == 0
                                  ? 'DISABLED'
                                  : '${s.restSeconds}S',
                              style: LsType.monoMeta
                                  .copyWith(color: t.surface.text2),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: t.surface.text3, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: LsGap.loose),
          _Section(
            title: 'ACCENT COLOR',
            child: _AccentSwatches(
              current: s.accent,
              onChange: (a) =>
                  ref.read(settingsProvider.notifier).setAccent(a),
            ),
          ),
          const SizedBox(height: LsGap.loose),
          _Section(
            title: 'THEME',
            child: _ThemeRow(
              current: s.themeMode,
              onChange: (m) =>
                  ref.read(settingsProvider.notifier).setThemeMode(m),
            ),
          ),
          if (Platform.isIOS) ...[
            const SizedBox(height: LsGap.loose),
            _Section(
              title: 'LOCK SCREEN',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: t.surface.surface,
                  borderRadius: BorderRadius.circular(LsRadius.r3),
                  border: Border.all(color: t.surface.border),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: t.accent.accent,
                  title: Text(
                    'Live Activity',
                    style: LsType.bodyL.copyWith(color: t.surface.text),
                  ),
                  subtitle: Text(
                    'Show current exercise + rest timer on the lock screen '
                    'and Dynamic Island during a workout.',
                    style: LsType.bodyS.copyWith(color: t.surface.text2),
                  ),
                  value: s.liveActivityEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setLiveActivityEnabled(v),
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EyebrowLabel(title),
        const SizedBox(height: LsGap.sub),
        child,
      ],
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.current, required this.onChange});
  final WeightUnit current;
  final ValueChanged<WeightUnit> onChange;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LsChoiceChip(
            label: 'KILOGRAMS',
            selected: current == WeightUnit.kg,
            onTap: () => onChange(WeightUnit.kg),
          ),
        ),
        const SizedBox(width: LsGap.inline),
        Expanded(
          child: LsChoiceChip(
            label: 'POUNDS',
            selected: current == WeightUnit.lb,
            onTap: () => onChange(WeightUnit.lb),
          ),
        ),
      ],
    );
  }
}

class _AccentSwatches extends StatelessWidget {
  const _AccentSwatches({required this.current, required this.onChange});
  final LsAccent current;
  final ValueChanged<LsAccent> onChange;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Row(
      children: [
        for (final spec in lsAccents) ...[
          Expanded(
            child: _Swatch(
              color: spec.accent,
              selected: spec.id == current,
              outlineColor: t.surface.text,
              onTap: () => onChange(spec.id),
            ),
          ),
          if (spec != lsAccents.last) const SizedBox(width: LsGap.inline),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.outlineColor,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final Color outlineColor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? outlineColor : Colors.transparent,
              width: 2.5,
            ),
            borderRadius: BorderRadius.circular(LsRadius.r3 + 4),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(LsRadius.r3),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.current, required this.onChange});
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChange;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LsChoiceChip(
            label: 'DARK',
            selected: current == ThemeMode.dark,
            onTap: () => onChange(ThemeMode.dark),
          ),
        ),
        const SizedBox(width: LsGap.inline),
        Expanded(
          child: LsChoiceChip(
            label: 'LIGHT',
            selected: current == ThemeMode.light,
            onTap: () => onChange(ThemeMode.light),
          ),
        ),
        const SizedBox(width: LsGap.inline),
        Expanded(
          child: LsChoiceChip(
            label: 'AUTO',
            selected: current == ThemeMode.system,
            onTap: () => onChange(ThemeMode.system),
          ),
        ),
      ],
    );
  }
}

Future<int?> _pickRestSeconds(BuildContext context, int current) {
  const options = [0, 30, 60, 90, 120, 150, 180, 240, 300];
  final initial = options.indexOf(current).clamp(0, options.length - 1);
  var selectedIndex = initial;
  return showCupertinoModalPopup<int>(
    context: context,
    builder: (ctx) {
      final t = LsTheme.of(ctx);
      return Container(
        height: 320,
        color: t.surface.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 18),
              const EyebrowLabel('DEFAULT REST'),
              const SizedBox(height: 10),
              Expanded(
                // Band drawn as an underlay (see picker_column.dart for the
                // full rationale). In light mode the `accentDimBg` is
                // opaque, so passing it as `selectionOverlay` would hide
                // the selected number completely.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: t.accentDimBg,
                            borderRadius: BorderRadius.circular(LsRadius.r3),
                            border: Border.all(
                              color: t.accent.accent,
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    CupertinoPicker(
                      itemExtent: 48,
                      useMagnifier: false,
                      backgroundColor: Colors.transparent,
                      scrollController:
                          FixedExtentScrollController(initialItem: initial),
                      onSelectedItemChanged: (i) => selectedIndex = i,
                      selectionOverlay: const SizedBox.shrink(),
                      children: [
                        for (final v in options)
                          Center(
                            child: Text(
                              v == 0 ? 'OFF' : '${v}s',
                              style: LsType.monoNumeral.copyWith(
                                color: t.surface.text2,
                                fontSize: 26,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: LsSpace.sheet, vertical: 12),
                child: LsButton(
                  label: 'Done',
                  onPressed: () => Navigator.pop(ctx, options[selectedIndex]),
                  expand: true,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
