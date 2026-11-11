import Flutter
import UIKit

final class PitanieNativeAdFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any] ?? [:]
    let unitId = params["unitId"] as? String ?? ""
    let width = (params["width"] as? NSNumber).map { CGFloat(truncating: $0) } ?? frame.width
    let channel = FlutterMethodChannel(
      name: "pitanie_native_ad.\(viewId)", binaryMessenger: messenger)
    return PitanieNativeAdPlatformView(unitId: unitId, width: width, channel: channel)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
