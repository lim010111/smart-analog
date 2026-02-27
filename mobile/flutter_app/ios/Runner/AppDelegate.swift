import Flutter
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let widgetHostChannel = "com.smartanalog.flutter_app/widget_host"
  private let widgetReadFileName = "widget_snapshot_read_v1.json"
  private let widgetReadSubdirectory = "snapshots"
  private let widgetAppGroup = "group.com.smartanalog.flutterApp"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let finished = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: widgetHostChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterError(code: "deallocated", message: "AppDelegate released", details: nil))
          return
        }

        switch call.method {
        case "syncWidgetReadPayload":
          guard let payload = call.arguments as? [String: Any] else {
            result(FlutterError(code: "invalid_args", message: "Expected map payload", details: nil))
            return
          }
          result(self.writeWidgetPayload(payload))

        case "refreshHomeWidgets":
          self.reloadWidgets()
          result(true)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return finished
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func writeWidgetPayload(_ payload: [String: Any]) -> Bool {
    guard let appGroupUrl = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: widgetAppGroup
    ) else {
      return false
    }

    let snapshotsDir = appGroupUrl.appendingPathComponent(widgetReadSubdirectory, isDirectory: true)
    let snapshotFile = snapshotsDir.appendingPathComponent(widgetReadFileName)
    do {
      let data = try JSONSerialization.data(withJSONObject: payload, options: [])
      try FileManager.default.createDirectory(
        at: snapshotsDir,
        withIntermediateDirectories: true,
        attributes: nil
      )
      try data.write(to: snapshotFile, options: .atomic)
      reloadWidgets()
      return true
    } catch {
      return false
    }
  }

  private func reloadWidgets() {
    #if canImport(WidgetKit)
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
    #endif
  }
}
