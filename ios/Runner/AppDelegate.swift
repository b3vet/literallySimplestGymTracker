import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // PHASE 0 — wire the Pigeon watch bridge onto the engine's messenger.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchBridge") {
      WCSessionManager.shared.bootstrap(messenger: registrar.messenger())
    }
    // SOW-02 — wire the `ls/share` MethodChannel (UIActivityViewController).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShareHandler") {
      ShareHandler.shared.setup(messenger: registrar.messenger())
    }
  }
}
