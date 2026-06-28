import Foundation
import Flutter
import UIKit

/// iOS-side handler for the `ls/share` `MethodChannel`.
///
/// Presents a `UIActivityViewController` (the system share sheet) for outbound
/// file + text sharing, and exposes the app's bundle version. Hand-rolled
/// native bridge — no third-party share plugin — matching the project's ethos
/// (see `WCSessionManager` for the watch bridge equivalent).
///
/// WIRE CONTRACT (mirrors `lib/features/export/application/share_service.dart`):
///   method "shareFiles": args ["paths": [String], "text": String?]
///                        -> presents the share sheet, returns null on present.
///   method "appVersion": -> "CFBundleShortVersionString+CFBundleVersion"
///                           (e.g. "1.3.0+10"), or "unknown" if unreadable.
///
/// Added to the **Runner** target. Wired up from
/// `AppDelegate.didInitializeImplicitFlutterEngine`.
final class ShareHandler: NSObject {
  static let shared = ShareHandler()

  private static let channelName = "ls/share"

  /// Wire the method channel onto the engine's binary messenger. Called once
  /// at implicit-engine init, before any Dart UI runs.
  func setup(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "ShareHandler deallocated", details: nil))
        return
      }
      switch call.method {
      case "shareFiles":
        self.handleShareFiles(call, result: result)
      case "appVersion":
        self.handleAppVersion(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NSLog("[ShareHandler] setup")
  }

  // MARK: - shareFiles

  private func handleShareFiles(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let paths = (args?["paths"] as? [String]) ?? []
    let text = args?["text"] as? String

    // Build the activity items: file URLs first, then the optional text.
    var items: [Any] = paths.map { URL(fileURLWithPath: $0) }
    if let text = text {
      items.append(text)
    }

    // All UIKit work on the main thread.
    self.onMain {
      guard let root = self.topViewController() else {
        result(FlutterError(code: "no_root", message: "No root view controller to present from", details: nil))
        return
      }

      let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

      // iPad requires a popover anchor; without it the present call crashes.
      if let popover = activityVC.popoverPresentationController {
        let sourceView = root.view
        popover.sourceView = sourceView
        if let bounds = sourceView?.bounds {
          popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
        }
        popover.permittedArrowDirections = []
      }

      // Return null on successful presentation. We resolve right after kicking
      // off `present(...)` rather than inside its completion closure: UIKit does
      // not guarantee that closure fires if the presentation is interrupted,
      // which would leave the Dart Future hanging.
      root.present(activityVC, animated: true, completion: nil)
      result(nil)
    }
  }

  // MARK: - appVersion

  private func handleAppVersion(result: @escaping FlutterResult) {
    let info = Bundle.main.infoDictionary
    let shortVersion = info?["CFBundleShortVersionString"] as? String
    let buildVersion = info?["CFBundleVersion"] as? String
    if let shortVersion = shortVersion, let buildVersion = buildVersion {
      result("\(shortVersion)+\(buildVersion)")
    } else {
      result("unknown")
    }
  }

  // MARK: - Helpers

  /// Hop to the main thread before any UIKit work.
  private func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
  }

  /// Find the topmost presented view controller from the key window's root,
  /// so the share sheet presents above any already-presented Flutter sheet.
  private func topViewController() -> UIViewController? {
    let windowScenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }

    // Prefer the current key window. During scene activation / foregrounding no
    // window may report `isKeyWindow` transiently; fall back to the first
    // connected scene's first window that actually has a root view controller
    // so the share doesn't silently fail.
    let keyWindow = windowScenes.flatMap { $0.windows }.first { $0.isKeyWindow }
    let fallbackWindow = windowScenes.flatMap { $0.windows }.first { $0.rootViewController != nil }

    guard var top = (keyWindow ?? fallbackWindow)?.rootViewController else { return nil }
    while let presented = top.presentedViewController {
      top = presented
    }
    return top
  }
}
