import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/spec.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/layout.dart';
import '../data/tips_content.dart';

class TipsScreen extends StatelessWidget {
  const TipsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return LsScreen(
      topGap: LsGap.loose,
      topbar: const LsTopbar(title: 'Tips'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: EyebrowLabel('COACH · ${tips.length} READS'),
          ),
          const SizedBox(height: LsGap.sub),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: tips.length,
              separatorBuilder: (_, _) => const SizedBox(height: LsGap.sub),
              itemBuilder: (context, i) =>
                  _TipCard(index: i + 1, tip: tips[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.index, required this.tip});
  final int index;
  final Tip tip;
  @override
  Widget build(BuildContext context) {
    final t = LsTheme.of(context);
    return LsCard(
      padding: LsPad.cardSpacious,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '/${index.toString().padLeft(2, '0')}',
                style: LsType.monoMeta.copyWith(
                  color: t.accent.accent,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: LsGap.inline),
              Expanded(
                child: Text(
                  tip.title.toUpperCase(),
                  style: LsType.displayS.copyWith(
                    color: t.surface.text,
                    fontSize: 24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LsGap.sub),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              tip.body,
              style: LsType.bodyL.copyWith(color: t.surface.text2),
            ),
          ),
        ],
      ),
    );
  }
}
