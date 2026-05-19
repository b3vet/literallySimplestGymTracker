import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/spec.dart';
import 'brand.dart';
import 'layout.dart';

/// Inline rename prompt — used by Programs/Days/Exercises long-press menu.
/// Presents as a small modal sheet (matches screen 05 in the spec). The
/// underline above "RENAME" is the EyebrowLabel stripe, never a literal `—`.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  String? initial,
  String hint = 'Name',
}) {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Same wrapper pattern as `showExerciseEditSheet` — Flutter's
    // `showModalBottomSheet` does NOT apply `viewInsets.bottom` itself, so
    // without this Padding the sheet stays anchored at the bottom and the
    // keyboard covers it. Capping height to `screen.height - safeTop
    // - viewInsets.bottom` keeps the sheet from sailing off the top of
    // the screen when the keyboard is open.
    builder: (ctx) {
      final t = LsTheme.of(ctx);
      final mq = MediaQuery.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mq.size.height - mq.padding.top - mq.viewInsets.bottom,
          ),
          child: LsSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EyebrowLabel(title.toUpperCase()),
                const SizedBox(height: LsGap.section),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: LsType.displayM.copyWith(
                    color: t.surface.text,
                    fontSize: 28,
                  ),
                  decoration: InputDecoration(
                    hintText: hint.toUpperCase(),
                    hintStyle: LsType.displayM.copyWith(
                      color: t.surface.text3,
                      fontSize: 28,
                    ),
                  ),
                ),
                const SizedBox(height: LsGap.loose),
                Row(
                  children: [
                    Expanded(
                      child: LsButton(
                        label: 'Cancel',
                        variant: LsButtonVariant.ghost,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: LsGap.inline),
                    Expanded(
                      child: LsButton(
                        label: 'Save',
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<bool?> confirmDelete(BuildContext context, String label) =>
    showDialog(
      context: context,
      builder: (ctx) {
        final t = LsTheme.of(ctx);
        return AlertDialog(
          title: const Text('DELETE?'),
          content: Text(
            'This will delete "$label" and everything inside it.',
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
              child: const Text('DELETE'),
            ),
          ],
        );
      },
    );

Widget dismissBackground() => Builder(
      builder: (context) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: LsSignals.danger,
          borderRadius: BorderRadius.circular(LsRadius.r3),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
    );
