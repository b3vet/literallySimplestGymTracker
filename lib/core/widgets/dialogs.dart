import 'dart:async';

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

/// [details] are extra lines under the standard one that spell out what goes
/// with it (SOW-15: "2 exercises will be removed."). [warning], when given, is
/// a red paragraph after them — e.g. that the workout in progress will end.
Future<bool?> confirmDelete(
  BuildContext context,
  String label, {
  List<String> details = const [],
  String? warning,
}) =>
    showDialog(
      context: context,
      builder: (ctx) {
        final t = LsTheme.of(ctx);
        return AlertDialog(
          title: const Text('DELETE?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will delete "$label" and everything inside it.',
                style: LsType.bodyM.copyWith(color: t.surface.text2),
              ),
              for (final line in details) ...[
                const SizedBox(height: 8),
                Text(
                  line,
                  style: LsType.bodyM.copyWith(color: t.surface.text2),
                ),
              ],
              if (warning != null) ...[
                const SizedBox(height: 12),
                Text(
                  warning,
                  style: LsType.bodyM.copyWith(color: LsSignals.danger),
                ),
              ],
            ],
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

/// SOW-15: the visible delete control on an editable row (EDIT mode), next to
/// the swipe. Red, 44 × 44 tap target, read out as `Delete <name>` with a tap
/// action (the `Semantics` excludes the InkWell's own node, so it re-declares
/// `onTap` — D-0017 review #3). While the future [onPressed] returns is
/// pending, further taps are ignored (review #4: two fast taps stacked two
/// confirm dialogs).
class DeleteRowButton extends StatefulWidget {
  const DeleteRowButton({
    super.key,
    required this.name,
    required this.onPressed,
  });
  final String name;
  final FutureOr<void> Function() onPressed;

  @override
  State<DeleteRowButton> createState() => _DeleteRowButtonState();
}

class _DeleteRowButtonState extends State<DeleteRowButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onPressed();
    } finally {
      if (mounted) _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: 'Delete ${widget.name}',
      excludeSemantics: true,
      onTap: _tap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          onTap: _tap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.remove_circle_outline,
              color: LsSignals.danger,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
