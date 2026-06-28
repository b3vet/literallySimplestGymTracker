import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

/// Captures the off-screen branded summary card (a [RepaintBoundary] tagged with
/// [boundaryKey]) to a PNG in the temp dir and returns its path.
///
/// Caller contract: mount the card inside a `RepaintBoundary(key: boundaryKey)`
/// that is laid out at full size but kept off-screen (see [renderCardOffstage]),
/// then call this after at least one frame has settled.
///
/// Throws on failure; the caller falls back to a text-only share.
Future<String> renderSummaryCardPng(GlobalKey boundaryKey) async {
  final context = boundaryKey.currentContext;
  if (context == null) {
    throw StateError('Summary card boundary is not mounted.');
  }
  final object = context.findRenderObject();
  if (object is! RenderRepaintBoundary) {
    throw StateError('Summary card boundary render object missing.');
  }

  // Guard the unpainted case: toImage() throws if the boundary still needs
  // paint. Pump a bounded number of frames waiting for it to settle so capture
  // never throws on a not-yet-painted boundary (the caller's two endOfFrame
  // awaits usually suffice, but this is a belt-and-braces backstop).
  var guard = 0;
  while (object.debugNeedsPaint && guard < 5) {
    await WidgetsBinding.instance.endOfFrame;
    guard++;
  }

  // pixelRatio 3 → a ~1080×1350 logical card renders at ~3240×4050 px, crisp on
  // any phone and large enough to look sharp in a chat preview.
  final ui.Image image = await object.toImage(pixelRatio: 3);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Failed to encode summary card PNG.');
    }
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/ls-gym-track-summary-$stamp.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file.path;
  } finally {
    image.dispose();
  }
}

/// Mounts [card] off-screen via an [OverlayEntry] (pushed far outside the
/// viewport so it never paints on top of the UI), waits for one frame so it
/// lays out and paints, runs [capture] against the live tree, then removes the
/// overlay — even if [capture] throws.
///
/// Returns whatever [capture] returns. The card must contain a
/// `RepaintBoundary(key: <key>)`; pass that same key into [renderSummaryCardPng]
/// from inside [capture].
Future<T> renderCardOffstage<T>(
  BuildContext context, {
  required Widget card,
  required Future<T> Function() capture,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far off-screen: laid out and painted (so RepaintBoundary has real
      // pixels) but never visible to the user.
      left: -10000,
      top: -10000,
      child: Material(type: MaterialType.transparency, child: card),
    ),
  );
  overlay.insert(entry);
  try {
    // Let the entry build + lay out + paint before we snapshot it.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    return await capture();
  } finally {
    entry.remove();
  }
}
