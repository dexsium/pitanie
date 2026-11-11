import Flutter
import UIKit
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Мост к виджетам iOS. Снимок дня кладётся в общую группу приложений (App Group), откуда его
/// читает расширение WidgetKit. Пока группа не настроена в подписи сборки, плагин ничего не
/// делает: isSupported возвращает false, update возвращает false, данные нигде не сохраняются.
public class PitanieWidgetsPlugin: NSObject, FlutterPlugin {
  static let appGroup = "group.com.pitanie.pitanie"
  static let snapshotKey = "pitanie_widget_snapshot"

  private var channel: FlutterMethodChannel?
  private var pendingAction: String?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pitanie_widgets", binaryMessenger: registrar.messenger())
    let instance = PitanieWidgetsPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  private var groupAvailable: Bool {
    return FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: PitanieWidgetsPlugin.appGroup) != nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      guard groupAvailable,
        let args = call.arguments as? [String: Any],
        let json = args["json"] as? String,
        let defaults = UserDefaults(suiteName: PitanieWidgetsPlugin.appGroup)
      else {
        result(false)
        return
      }
      defaults.set(json, forKey: PitanieWidgetsPlugin.snapshotKey)
      #if canImport(WidgetKit)
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
      #endif
      result(true)
    case "initialAction":
      let action = pendingAction
      pendingAction = nil
      result(action)
    case "isSupported":
      result(groupAvailable)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Нажатие на виджет открывает приложение адресом pitanie://widget/<команда>.
  public func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == "pitanie", url.host == "widget" else { return false }
    let action = url.lastPathComponent
    // Если Dart ещё не готов (холодный запуск), команда останется ждать запроса initialAction.
    channel?.invokeMethod("onAction", arguments: action) { [weak self] reply in
      if (reply as? Bool) != true {
        self?.pendingAction = action
      }
    }
    return true
  }
}
