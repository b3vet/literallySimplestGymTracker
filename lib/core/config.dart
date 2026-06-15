import 'package:flutter/foundation.dart' show kDebugMode;

/// Whether developer-only tools (e.g. "Reset app data" in Settings) are shown.
///
/// Defaults to **debug builds only**, so they never ship in a normal release.
/// Override explicitly at build time if needed:
///
///   flutter run  --dart-define=LS_DEV_TOOLS=true
///   flutter build ipa --dart-define=LS_DEV_TOOLS=false
const bool kDevToolsEnabled =
    bool.fromEnvironment('LS_DEV_TOOLS', defaultValue: kDebugMode);
