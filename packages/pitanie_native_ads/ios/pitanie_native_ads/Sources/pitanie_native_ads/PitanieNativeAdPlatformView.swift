import Flutter
import UIKit
import YandexMobileAds

/// Вся работа с нативным рекламным SDK: загрузчик, объявление, привязка к карточке и события.
/// SDK Яндекса требует главный поток, а его типы изолированы на главном акторе, поэтому класс
/// целиком @MainActor (в том числе делегат NativeAdDelegate). Создаётся и вызывается только
/// из блоков Task { @MainActor }.
@MainActor
private final class NativeAdHost: NSObject, NativeAdDelegate {
  private let adView = PitanieNativeAdView(frame: .zero)
  private let loader = NativeAdLoader()
  private var ad: NativeAd?
  private let unitId: String
  private let width: CGFloat
  private let emit: @MainActor (String, [String: Any]) -> Void
  private var loading = false
  private var disposed = false

  init(
    container: UIView,
    unitId: String,
    width: CGFloat,
    emit: @escaping @MainActor (String, [String: Any]) -> Void
  ) {
    self.unitId = unitId
    self.width = width
    self.emit = emit
    super.init()
    adView.translatesAutoresizingMaskIntoConstraints = false
    adView.isHidden = true
    container.addSubview(adView)
    NSLayoutConstraint.activate([
      adView.topAnchor.constraint(equalTo: container.topAnchor),
      adView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      adView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
  }

  func load() {
    guard !loading, !disposed, !unitId.isEmpty else { return }
    loading = true
    emit("loading", [:])
    let request = AdRequest(adUnitID: unitId)
    let options = NativeAdOptions()
    loader.loadAd(with: request, options: options) { [weak self] result in
      Task { @MainActor in self?.handle(result) }
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
        emit("loaded", ["height": Double(adView.fittingHeight(width: width))])
      } catch {
        emit("bindFailed", ["code": (error as NSError).code])
      }
    case .failure(let error):
      emit("failed", ["code": (error as NSError).code])
    }
  }

  func dispose() {
    disposed = true
    ad?.delegate = nil
    ad = nil
    adView.removeFromSuperview()
  }

  // MARK: - NativeAdDelegate (методы необязательные)

  func nativeAdDidClick(_ ad: NativeAd) {
    emit("click", [:])
  }

  func nativeAd(_ ad: NativeAd, didTrackImpression impressionData: ImpressionData?) {
    emit("impression", [:])
  }
}

/// Платформенное представление нативной рекламы. Загрузка начинается только по команде Dart
/// ("load"), чтобы события не терялись до подписки. События уходят в Dart методом "event":
/// loading, loaded (height), failed, bindFailed, impression, click. Тексты объявлений и данные
/// пользователя в события не попадают.
final class PitanieNativeAdPlatformView: NSObject, FlutterPlatformView {
  private let container = UIView()
  private let channel: FlutterMethodChannel
  private let unitId: String
  private let width: CGFloat
  private var host: NativeAdHost?

  init(unitId: String, width: CGFloat, channel: FlutterMethodChannel) {
    self.unitId = unitId
    self.width = width
    self.channel = channel
    super.init()
    container.backgroundColor = .clear
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "load" {
        Task { @MainActor in self?.startLoad() }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  @MainActor
  private func startLoad() {
    if host == nil {
      host = NativeAdHost(container: container, unitId: unitId, width: width) {
        [weak self] type, extra in
        var payload = extra
        payload["type"] = type
        self?.channel.invokeMethod("event", arguments: payload)
      }
    }
    host?.load()
  }

  deinit {
    channel.setMethodCallHandler(nil)
    let h = host
    host = nil
    Task { @MainActor in h?.dispose() }
  }
}
