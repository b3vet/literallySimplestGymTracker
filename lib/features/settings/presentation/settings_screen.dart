import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/db/maintenance.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../../../core/util/weight.dart';
import '../../../main.dart' show databaseProvider;
import '../../export/application/export_controller.dart';
import '../../programs/application/programs_provider.dart';
import '../../workout/application/plate_format.dart';
import '../../workout/presentation/set_log_sheet.dart' show showBarChooserSheet;

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
            title: 'PLATES',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PlateNavRow(
                  title: 'Default bar',
                  value: WeightConv.format(s.barWeightKg, unit).toUpperCase(),
                  onTap: () => showBarChooserSheet(context, ref, unit),
                ),
                const SizedBox(height: LsGap.item),
                _PlateNavRow(
                  title: 'Available plates',
                  value: _plateInventorySummary(s.plateInventoryKg, unit),
                  onTap: () => _pickPlateInventory(
                    context,
                    ref,
                    unit,
                    s.plateInventoryKg,
                  ),
                ),
              ],
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
          const SizedBox(height: LsGap.loose),
          _Section(
            title: 'DATA',
            child: _ExportDataRow(
              state: ref.watch(exportControllerProvider),
              onTap: () =>
                  ref.read(exportControllerProvider.notifier).exportAndShare(),
            ),
          ),
          if (kDevToolsEnabled) ...[
            const SizedBox(height: LsGap.loose),
            _Section(
              title: 'DEVELOPER',
              child: _ResetDataRow(onReset: () => _resetAppData(context, ref)),
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

/// The canonical full plate set (kg), largest-first — the universe of
/// denominations the "Available plates" sheet offers as toggle chips.
const List<double> _allPlateDenomsKg = <double>[25, 20, 15, 10, 5, 2.5, 1.25];

/// One-line summary of the selected plate set in the display unit, e.g.
/// "25 · 20 · 15 · 10 · 5 · 2.5 · 1.25". Falls back to a placeholder when the
/// user has somehow deselected everything.
String _plateInventorySummary(List<double> inventoryKg, WeightUnit unit) {
  if (inventoryKg.isEmpty) return 'NONE SELECTED';
  final sorted = [...inventoryKg]..sort((a, b) => b.compareTo(a));
  return sorted.map((kg) => PlateFormat.plateNum(kg, unit)).join(' · ');
}

/// Toggle-chip sheet for choosing which plate denominations are on hand. Writes
/// the selected set (kg) via [SettingsNotifier.setPlateInventoryKg]. Chips are
/// labelled in the display unit; values stored are always kg.
Future<void> _pickPlateInventory(
  BuildContext context,
  WidgetRef ref,
  WeightUnit unit,
  List<double> currentKg,
) {
  final selected = {...currentKg};
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => LsSheet(
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final t = LsTheme.of(ctx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: LsGap.sub),
              const EyebrowLabel('AVAILABLE PLATES'),
              const SizedBox(height: LsGap.sub),
              Text(
                'Pick the plate pairs you own. The set-logger breakdown only '
                'suggests these.',
                style: LsType.bodyM.copyWith(color: t.surface.text2),
              ),
              const SizedBox(height: LsGap.loose),
              Wrap(
                spacing: LsGap.inline,
                runSpacing: LsGap.inline,
                children: [
                  for (final kg in _allPlateDenomsKg)
                    LsChoiceChip(
                      label: PlateFormat.plateNum(kg, unit),
                      selected: selected.contains(kg),
                      onTap: () => setSheetState(() {
                        if (selected.contains(kg)) {
                          // Keep at least one plate — an empty inventory would
                          // make every weight misleadingly read "BAR ONLY".
                          if (selected.length > 1) selected.remove(kg);
                        } else {
                          selected.add(kg);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: LsGap.loose),
              LsButton(
                label: 'DONE',
                expand: true,
                minHeight: LsBox.cta,
                onPressed: () {
                  final next = _allPlateDenomsKg
                      .where(selected.contains)
                      .toList();
                  ref
                      .read(settingsProvider.notifier)
                      .setPlateInventoryKg(next);
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Developer action: wipe every row of user data, then flip the onboarding
/// flag so the router's refresh listener drops the user back into a fresh
/// first-run wizard. Confirmed first — it's destructive and irreversible.
Future<void> _resetAppData(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = LsTheme.of(ctx);
      return AlertDialog(
        title: const Text('RESET APP DATA?'),
        content: Text(
          'Deletes all programs and history, then restarts onboarding. '
          'This cannot be undone.',
          style: LsType.bodyM.copyWith(color: t.surface.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: LsType.button.copyWith(color: t.surface.text2),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LsSignals.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(88, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESET'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  await wipeAllData(ref.read(databaseProvider));
  ref.invalidate(programsListProvider);
  // Last — this triggers the redirect into onboarding (unmounting Settings).
  await ref.read(settingsProvider.notifier).setOnboardingComplete(false);
}

class _ResetDataRow extends StatelessWidget {
  const _ResetDataRow({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: onReset,
        child: Container(
          padding: LsPad.cardStd,
          decoration: BoxDecoration(
            color: t.surface.surface,
            borderRadius: BorderRadius.circular(LsRadius.r3),
            border: Border.all(color: LsSignals.danger.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reset app data',
                      style: LsType.displayM.copyWith(color: LsSignals.danger),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'DELETE EVERYTHING · REPLAY ONBOARDING',
                      style: LsType.monoMeta.copyWith(color: t.surface.text2),
                    ),
                  ],
                ),
              ),
              Icon(Icons.delete_outline, color: LsSignals.danger, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exports the full workout history (CSV + JSON) to the native share sheet.
/// Mirrors the nav-row card pattern. While [ExportPreparing] the row is
/// disabled and swaps its trailing glyph for a spinner; [ExportError] shows the
/// failure message inline while keeping the row tappable for a retry.
class _ExportDataRow extends StatelessWidget {
  const _ExportDataRow({required this.state, required this.onTap});
  final ExportState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final preparing = state is ExportPreparing;
    final error = state is ExportError ? state as ExportError : null;
    final subtitle = preparing
        ? 'PREPARING…'
        : error?.message ?? 'ALL HISTORY · CSV + JSON';
    final subtitleColor =
        error != null ? LsSignals.danger : t.surface.text2;
    return Material(
      color: t.surface.surface,
      borderRadius: BorderRadius.circular(LsRadius.r3),
      child: InkWell(
        borderRadius: BorderRadius.circular(LsRadius.r3),
        onTap: preparing ? null : onTap,
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
                      'Export data',
                      style: LsType.displayM.copyWith(color: t.surface.text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: LsType.monoMeta.copyWith(color: subtitleColor),
                    ),
                  ],
                ),
              ),
              if (preparing)
                const CupertinoActivityIndicator()
              else
                Icon(Icons.ios_share, color: t.surface.text3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable settings row (title + current value + chevron) used by the PLATES
/// section. Mirrors the REST TIMER row's card pattern.
class _PlateNavRow extends StatelessWidget {
  const _PlateNavRow({
    required this.title,
    required this.value,
    required this.onTap,
  });
  final String title;
  final String value;
  final VoidCallback onTap;

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
                      title,
                      style: LsType.displayM.copyWith(color: t.surface.text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: LsType.monoMeta.copyWith(color: t.surface.text2),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.surface.text3, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
