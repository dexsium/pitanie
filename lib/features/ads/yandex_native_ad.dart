import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ad_provider.dart';
import 'native_ad_config.dart';
import 'native_ad_controller.dart';

/// Нативная реклама Яндекса: платформенное представление iOS на официальном SDK.
/// Объявление загружается один раз при появлении виджета (не при каждой перестройке),
/// при ошибке карточка сворачивается и не оставляет пустого места, при удалении виджета
/// ресурсы освобождаются. Работает только на iOS; на других платформах ничего не рисует.
class YandexNativeAd extends StatefulWidget {
  final String unitId;
  final AdEvents? events;
  const YandexNativeAd({super.key, required this.unitId, this.events});

  @override
  State<YandexNativeAd> createState() => _YandexNativeAdState();
}

class _YandexNativeAdState extends State<YandexNativeAd> {
  late final NativeAdController _ctl = NativeAdController(
    onLoaded: () => widget.events?.onLoaded(),
    onFailed: () => widget.events?.onFailed(),
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width - 32;
      return ListenableBuilder(
        listenable: _ctl,
        builder: (context, _) => SizedBox(
          height: _ctl.height,
          width: double.infinity,
          child: UiKitView(
            viewType: kNativeAdViewType,
            creationParams: {'unitId': widget.unitId, 'width': width},
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _ctl.attach,
          ),
        ),
      );
    });
  }
}
