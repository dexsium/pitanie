import CoreBluetooth
import Flutter
import UIKit

/// Читает публичное свойство CBPeripheral.ancsAuthorized: разрешил ли iOS часам получать
/// системные уведомления (ANCS). Свойство только для чтения: включить доступ из приложения
/// нельзя, это делает пользователь в системных настройках Bluetooth.
final class AncsProbe: NSObject, CBCentralManagerDelegate {
  static let shared = AncsProbe()
  private var central: CBCentralManager?
  private var waiting: [(id: String, result: FlutterResult)] = []
  private var timer: Timer?

  func status(id: String, result: @escaping FlutterResult) {
    waiting.append((id, result))
    if central == nil {
      central = CBCentralManager(delegate: self, queue: .main, options: nil)
    } else if let c = central, c.state != .unknown {
      centralManagerDidUpdateState(c)
    }
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
      self?.flush(["state": "timeout"])
    }
  }

  private func flush(_ value: [String: Any]) {
    timer?.invalidate()
    let w = waiting
    waiting.removeAll()
    for item in w { item.result(value) }
  }

  func centralManagerDidUpdateState(_ c: CBCentralManager) {
    guard !waiting.isEmpty else { return }
    switch c.state {
    case .poweredOn:
      guard let first = waiting.first, let uuid = UUID(uuidString: first.id) else {
        flush(["state": "poweredOn", "found": false])
        return
      }
      let list = c.retrievePeripherals(withIdentifiers: [uuid])
      guard let p = list.first else {
        flush(["state": "poweredOn", "found": false])
        return
      }
      var out: [String: Any] = [
        "state": "poweredOn",
        "found": true,
        "name": p.name ?? "",
        "connection": p.state.rawValue,
      ]
      if #available(iOS 13.0, *) {
        out["ancsAuthorized"] = p.ancsAuthorized
      }
      flush(out)
    case .poweredOff: flush(["state": "poweredOff"])
    case .unauthorized: flush(["state": "unauthorized"])
    case .unsupported: flush(["state": "unsupported"])
    default: break
    }
  }
}

public class WatchAncsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pitanie/watch_ancs", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(WatchAncsPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result("ok")
    case "status":
      if let id = call.arguments as? String {
        AncsProbe.shared.status(id: id, result: result)
      } else {
        result(FlutterError(
          code: "bad_args",
          message: "аргумент типа \(String(describing: type(of: call.arguments)))",
          details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
