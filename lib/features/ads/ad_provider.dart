import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'ads_models.dart';
import 'ads_service.dart';
import 'yandex_ad_provider.dart';

/// Сообщения рекламного блока о результате загрузки. Сеть, которая загружает объявление уже
/// после показа виджета, вызывает их сама; слот тогда учитывает показ или ошибку по факту.
class AdEvents {
  final VoidCallback onLoaded;
  final VoidCallback onFailed;
  const AdEvents({required this.onLoaded, required this.onFailed});
}

/// Подключение рекламной сети. Чтобы подключить сеть, достаточно реализовать этот интерфейс и
/// подменить [adProviderProvider]. Реализация получает только размещение: никаких данных
/// пользователя, питания, веса, пульса и сна ей не передаётся.
abstract class AdProvider {
  const AdProvider();

  /// Название сети для экрана настроек.
  String get name;

  /// Подключена ли сеть и готова ли показывать рекламу.
  bool get available;

  /// Сеть сама сообщает о загрузке через [AdEvents] (объявление грузится после показа виджета).
  /// Тогда подпись «Реклама» и учёт показа появляются только после успешной загрузки.
  bool get reportsOwnEvents => false;

  /// Карточка рекламы сама содержит пометку «Реклама» (нативная реклама): слот свою не рисует.
  bool providesLabel(AdPlacement placement) => false;

  /// Заглушка вместо настоящей рекламы: показывается всегда, не подчиняется лимитам частоты
  /// и не попадает в счётчики показов.
  bool get isPlaceholder => false;

  /// Готовый виджет объявления для размещения или null, если объявления нет.
  /// Ошибки SDK нужно превращать в null: приложение обязано работать без рекламы.
  Future<Widget?> buildAd(AdPlacement placement, {AdEvents? events});
}

/// Рекламная сеть не подключена: реклама не показывается и ничего не запрашивается.
class NoAdProvider extends AdProvider {
  const NoAdProvider();
  @override
  String get name => 'не подключена';
  @override
  bool get available => false;
  @override
  Future<Widget?> buildAd(AdPlacement placement, {AdEvents? events}) async => null;
}

/// Заглушка рекламы: серый блок «Здесь будет реклама» нужного размера, чтобы видеть, как
/// выглядят рекламные места. Ничего не запрашивает из сети. Когда будет выбрана рекламная сеть,
/// её реализация [AdProvider] заменит эту заглушку.
class PlaceholderAdProvider extends AdProvider {
  const PlaceholderAdProvider();
  @override
  String get name => 'заглушка';
  @override
  bool get available => true;
  @override
  bool get isPlaceholder => true;

  @override
  Future<Widget?> buildAd(AdPlacement placement, {AdEvents? events}) async {
    final height = switch (placement.format) {
      AdFormat.banner => 56.0,
      AdFormat.native => 120.0,
      AdFormat.rewarded => 56.0,
    };
    return _PlaceholderAd(height: height);
  }
}

class _PlaceholderAd extends StatelessWidget {
  final double height;
  const _PlaceholderAd({required this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text('Здесь будет реклама',
          style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
    );
  }
}

final adProviderProvider = Provider<AdProvider>((ref) => const YandexAdProvider());

final adsServiceProvider = Provider<AdsService>((ref) => AdsService(ref.watch(dbProvider)));
