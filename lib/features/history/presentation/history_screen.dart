import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/util/weight.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../application/history_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LsTheme.of(context);
    final rows = ref.watch(historyListProvider);
    final unit = ref.watch(settingsProvider).unit ?? WeightUnit.kg;
    return LsScreen(
      topGap: LsGap.loose,
      topbar: const LsTopbar(title: 'History'),
      child: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NO SESSIONS LOGGED',
                      style: LsType.displayM.copyWith(color: t.surface.text),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your first workout is waiting.',
                      textAlign: TextAlign.center,
                      style: LsType.bodyM.copyWith(color: t.surface.text2),
                    ),
                  ],
                ),
              ),
            );
          }
          final now = DateTime.now();
          final monthLabel = DateFormat('MMM yyyy').format(now).toUpperCase();
          final sessionLabel =
              '${list.length} ${list.length == 1 ? "SESSION" : "SESSIONS"}';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Page-content eyebrow (month + count) below the header — the
              // user explicitly asked for this to live under the title.
              Align(
                alignment: Alignment.centerRight,
                child: EyebrowLabel('$monthLabel · $sessionLabel'),
              ),
              const SizedBox(height: LsGap.sub),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: LsGap.sub),
                  itemBuilder: (context, i) =>
                      _SessionTile(row: list[i], unit: unit),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.row, required this.unit});
  final SessionSummaryRow row;
  final WeightUnit unit;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    final dateStr = DateFormat('EEE d').format(row.session.startedAt);
    final durMin = row.session.duration.inMinutes;

    // Merge program (if any) + day into the heading. The third line below
    // the meta pills was removed per user feedback — the heading already
    // tells the user what this session was.
    final dayPart = (row.dayName ?? 'Workout').toUpperCase();
    final heading = row.programName != null
        ? '${row.programName!.toUpperCase()} · $dayPart'
        : dayPart;

    return LsCard(
      onTap: () => context.push('/history/${row.session.id}'),
      padding: LsPad.cardSpacious,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 28,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: LsGap.tight),
              Text(
                dateStr.toUpperCase(),
                style: LsType.monoMeta.copyWith(
                  color: t.surface.text2,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: LsGap.sub),
          Wrap(
            spacing: LsGap.tight,
            runSpacing: LsGap.tight,
            children: [
              MetaPill(value: '${row.setCount}', text: 'SETS'),
              MetaPill(
                value: _weightValue(row.totalVolumeKg, unit),
                text: unit.short,
              ),
              MetaPill(value: '$durMin', text: 'MIN'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Numeric portion of a weight (no unit suffix) for MetaPill's bold-number
/// half.
String _weightValue(double kg, WeightUnit unit) {
  final v = WeightConv.fromKg(kg, unit);
  if (unit == WeightUnit.kg) {
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1);
  }
  return v.round().toString();
}
