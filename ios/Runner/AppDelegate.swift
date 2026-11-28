import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // The channel Dart's settings calls use (lib/core/device.dart,
  // lib/core/backup.dart), the same name as MainActivity.kt's. A test pins
  // these names to Dart's.
  static let settingsChannel = "com.burrowsoft.piggybow/settings"
  static let openNotificationSettings = "openNotificationSettings"
  static let excludeFromBackup = "excludeFromBackup"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications' iOS setup: without it a reminder doesn't
    // show while the app is open, and a tap on one doesn't reach the app.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PiggybowSettings")
    else { return }
    let channel = FlutterMethodChannel(
      name: AppDelegate.settingsChannel, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case AppDelegate.openNotificationSettings:
        // Me → Open settings, after "Don't Allow": Piggybow's notification
        // settings (iOS 16+), else its page in Settings (iOS 15).
        let name: String
        if #available(iOS 16, *) {
          name = UIApplication.openNotificationSettingsURLString
        } else {
          name = UIApplication.openSettingsURLString
        }
        if let url = URL(string: name) {
          UIApplication.shared.open(url)
        }
        result(nil)
      case AppDelegate.excludeFromBackup:
        // The journal's folder, out of every backup (decision 72, I-1(b)):
        // set on the folder, so a file in it that's replaced stays out too.
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "no-folder", message: nil, details: nil))
          return
        }
        var url = URL(fileURLWithPath: path, isDirectory: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
          result(true)
        } catch {
          result(FlutterError(code: "not-excluded", message: "\(error)", details: nil))
        }
      default:
        // androidSdk, updateWidget and the rest are Android's: Dart reads
        // "not implemented" as nothing to do (readAndroidSdk gives null).
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
