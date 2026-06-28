import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin Dart wrapper over the native `ls/share` `MethodChannel` — a
/// `UIActivityViewController` presenter in `ios/Runner/ShareHandler.swift`. No
/// third-party share plugin (matches the project's hand-rolled-native ethos,
/// like the custom WCSession watch bridge). Shared by data export (SOW-02) and
/// workout-summary share (SOW-02b).
class ShareService {
  const ShareService();

  static const MethodChannel _channel = MethodChannel('ls/share');

  /// Present the iOS share sheet for the given files, optionally with [text]
  /// (used by the summary share to attach the plain-text block alongside the
  /// image card). Throws on a platform error; callers surface it in the UI.
  Future<void> shareFiles(List<String> filePaths, {String? text}) async {
    await _channel.invokeMethod<void>('shareFiles', {
      'paths': filePaths,
      'text': ?text,
    });
  }

  /// The app's bundle version (e.g. `1.3.0+10`), read natively from
  /// `Bundle.main` — keeps export metadata dep-free (no `package_info_plus`).
  Future<String> appVersion() async {
    final v = await _channel.invokeMethod<String>('appVersion');
    return v ?? 'unknown';
  }
}

final shareServiceProvider =
    Provider<ShareService>((ref) => const ShareService());
