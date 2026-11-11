// Реклама Яндекса (РСЯ) через официальный плагин yandex_mobileads. Блоки созданы в кабинете РСЯ:
//   главная (баннер)    R-M-20382283-2
//   статистика (баннер) R-M-20382283-3
// Нативный блок R-M-20382283-1 (планировщик) во Flutter-плагине Яндекса не поддерживается, поэтому
// он показывается собственным платформенным представлением (packages/pitanie_native_ads, iOS).
// Реклама подключена только на iOS: блоки созданы для iOS-приложения.
// Запросу передаётся только идентификатор блока: без таргетинга, возраста, пола, местоположения
// и любых данных приложения. Согласие на обработку данных не выдаётся (реклама без персонализации).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

import 'ad_provider.dart';
import 'ads_models.dart';
import 'native_ad_config.dart';
import 'yandex_native_ad.dart';

class YandexAdProvider extends AdProvider {
  const YandexAdProvider();

  static const homeBannerId = 'R-M-20382283-2';
  static const statsBannerId = 'R-M-20382283-3';

  /// Блок для размещения; null — для размещения в РСЯ нет подходящего блока.
  static String? unitFor(AdPlacement p) => switch (p) {
        AdPlacement.homeBanner => homeBannerId,
        AdPlacement.statsBanner => statsBannerId,
        // Нативные блоки во Flutter-плагине Яндекса недоступны, поэтому на странице питания
        // стоит баннер. Пока для неё нет своего блока, используется блок главной страницы:
        // когда в РСЯ будет создан отдельный баннерный блок, заменить идентификатор здесь.
        AdPlacement.nutritionBanner => homeBannerId,
        AdPlacement.plannerNative => kNativeAdUnitId, // нативный блок: см. native_ad_config.dart
        AdPlacement.bonusRewarded => null, // видеореклама пока не используется
      };

  @override
  String get name => 'Яндекс (РСЯ)';
  @override
  bool get available => Platform.isIOS;
  @override
  bool get reportsOwnEvents => true;
  @override
  bool providesLabel(AdPlacement p) => p.format == AdFormat.native;

  @override
  Future<Widget?> buildAd(AdPlacement placement, {AdEvents? events}) async {
    final unit = unitFor(placement);
    if (unit == null || events == null) return null;
    try {
      // Один раз на приложение: повторные вызовы возвращают тот же результат.
      await YandexAds.initialize();
    } catch (_) {
      return null;
    }
    if (placement.format == AdFormat.native) {
      return YandexNativeAd(unitId: unit, events: events);
    }
    return _YandexBanner(unitId: unit, events: events);
  }
}

/// Баннер, который загружается сам после появления на экране и сообщает о результате.
/// При ошибке или долгом ожидании сворачивается в пустое место.
class _YandexBanner extends StatefulWidget {
  final String unitId;
  final AdEvents events;
  const _YandexBanner({required this.unitId, required this.events});

  @override
  State<_YandexBanner> createState() => _YandexBannerState();
}

class _YandexBannerState extends State<_YandexBanner> {
  BannerAd? _ad;
  StreamSubscription<BannerAdLoadState>? _sub;
  Timer? _timeout;
  bool _started = false;
  bool _done = false;

  void _finish(bool ok) {
    if (_done) return;
    _done = true;
    _timeout?.cancel();
    if (ok) {
      widget.events.onLoaded();
    } else {
      widget.events.onFailed();
    }
  }

  Future<void> _start(int width) async {
    try {
      final ad = BannerAd(adSize: BannerAdSize.sticky(width: width));
      _sub = ad.loadStateStream.listen((s) {
        if (s is BannerAdLoadStateLoaded) _finish(true);
        if (s is BannerAdLoadStateError) _finish(false);
      });
      _timeout = Timer(const Duration(seconds: 20), () => _finish(false));
      await ad.load(AdRequest(adUnitId: widget.unitId));
      if (!mounted) {
        await ad.destroy();
        return;
      }
      setState(() => _ad = ad);
    } catch (_) {
      _finish(false);
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _sub?.cancel();
    _ad?.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (!_started && c.maxWidth.isFinite && c.maxWidth > 0) {
        _started = true;
        final w = c.maxWidth.floor();
        WidgetsBinding.instance.addPostFrameCallback((_) => _start(w));
      }
      final ad = _ad;
      if (ad == null) return const SizedBox.shrink();
      return Align(alignment: Alignment.centerLeft, child: AdWidget(bannerAd: ad));
    });
  }

}
