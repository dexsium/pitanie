import Flutter
import UIKit

/// Регистрирует фабрику платформенного представления нативной рекламы Яндекса.
/// Сам рекламный SDK инициализирует официальный плагин yandex_mobileads (вызов
/// YandexAds.initialize на стороне Dart перед созданием представления): повторной
/// инициализации здесь нет.
public final class PitanieNativeAdsPlugin: NSObject, FlutterPlugin {
  static let viewType = "pitanie/native_ad"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let factory = PitanieNativeAdFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: viewType)
  }
}
