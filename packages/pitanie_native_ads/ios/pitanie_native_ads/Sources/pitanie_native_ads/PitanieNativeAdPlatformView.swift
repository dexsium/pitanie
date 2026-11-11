import Flutter
import UIKit
import YandexMobileAds

/// Платформенное представление нативной рекламы. Загрузка начинается только по команде Dart
/// ("load"), чтобы события не терялись до подписки. Все обращения к SDK идут в главном потоке.
/// Состояния и события отправляются в Dart методом "event": loading, loaded (height), failed,
/// bindFailed, impression, click, disposed. Тексты объявлений и данные пользователя в события
/// не попадают.
final class PitanieNativeAdPlatformView: NSObject, FlutterPlatformView, NativeAdDelegate {
  private let container = UIView()
  private let adView = PitanieNativeAdView(frame: .zero)
  private let loader = NativeAdLoader()
  private var ad: NativeAd?
  private let channel: FlutterMethodChannel
  private let unitId: String
  private let width: CGFloat
  private var loading = false
  private var disposed = false

  init(unitId: String, width: CGFloat, channel: FlutterMethodChannel) {
    self.unitId = unitId
    self.width = width
    self.channel = channel
    super.init()

    container.backgroundColor = .clear
    adView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(adView)
    NSLayoutConstraint.activate([
      adView.topAnchor.constraint(equalTo: container.topAnchor),
      adView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      adView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    adView.isHidden = true

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "load":
        self?.load()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  deinit {
    disposed = true
    ad?.delegate = nil
    ad = nil
    channel.setMethodCallHandler(nil)
  }

  private func send(_ type: String, _ extra: [String: Any] = [:]) {
    guard !disposed else { return }
    var payload = extra
    payload["type"] = type
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod("event", arguments: payload)
    }
  }

  private func load() {
    guard !loading, !disposed, !unitId.isEmpty else { return }
    loading = true
    send("loading")
    let request = AdRequest(adUnitID: unitId)
    let options = NativeAdOptions()
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.loader.loadAd(with: request, options: options) { [weak self] result in
        DispatchQueue.main.async { self?.handle(result) }
      }
    }
  }

  private func handle(_ result: Result<NativeAd, Error>) {
    loading = false
    guard !disposed else { return }
    switch result {
    case .success(let loaded):
      loaded.delegate = self
      do {
        try loaded.bind(with: adView)
        ad = loaded
        adView.isHidden = false
        adView.setNeedsLayout()
        adView.layoutIfNeeded()
        send("loaded", ["height": Double(adView.fittingHeight(width: width))])
      } catch {
        send("bindFailed", ["code": (error as NSError).code])
      }
    case .failure(let error):
      send("failed", ["code": (error as NSError).code])
    }
  }

  // MARK: - NativeAdDelegate (все методы необязательные)

  func nativeAdDidClick(_ ad: NativeAd) {
    send("click")
  }

  func nativeAd(_ ad: NativeAd, didTrackImpression impressionData: ImpressionData?) {
    send("impression")
  }
}
