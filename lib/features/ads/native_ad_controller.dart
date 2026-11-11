import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NativeAdState { idle, loading, loaded, failed, disposed }

/// Состояние и события одной нативной рекламной карточки. Загрузку запускает после создания
/// платформенного представления (команда "load"), события приходят методом "event".
/// Одна повторная попытка после ошибки, с задержкой и только пока карточка на экране.
class NativeAdController extends ChangeNotifier {
  NativeAdController({
    this.onLoaded,
    this.onFailed,
    this.onImpression,
    this.onClick,
    this.retryDelay = const Duration(seconds: 30),
    this.maxRetries = 1,
  });

  final VoidCallback? onLoaded;

  /// Вызывается, когда карточку показать не удалось (после исчерпания повторов).
  final VoidCallback? onFailed;
  final VoidCallback? onImpression;
  final VoidCallback? onClick;
  final Duration retryDelay;
  final int maxRetries;

  NativeAdState state = NativeAdState.idle;

  /// Высота карточки: пока объявления нет, 1 (представление должно существовать, чтобы
  /// загрузить рекламу, но не занимает места).
  double height = 1;

  int _retries = 0;
  bool _failedReported = false;
  Timer? _retryTimer;
  MethodChannel? _channel;

  void _log(String s) {
    if (kDebugMode) debugPrint('[native-ad] $s');
  }

  /// Подключает канал созданного представления и запускает загрузку.
  void attach(int viewId) {
    if (state == NativeAdState.disposed) return;
    _channel = MethodChannel('pitanie_native_ad.$viewId');
    _channel!.setMethodCallHandler(_onCall);
    _load();
  }

  Future<void> _load() async {
    if (state == NativeAdState.disposed) return;
    state = NativeAdState.loading;
    notifyListeners();
    try {
      await _channel?.invokeMethod<void>('load');
    } catch (_) {
      _fail('channel');
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'event' || state == NativeAdState.disposed) return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final type = args['type'];
    _log('событие: $type${args['code'] != null ? ' (код ${args['code']})' : ''}');
    switch (type) {
      case 'loaded':
        final h = args['height'];
        height = (h is num ? h.toDouble() : 0.0).clamp(120.0, 1200.0).toDouble();
        state = NativeAdState.loaded;
        notifyListeners();
        onLoaded?.call();
      case 'failed':
      case 'bindFailed':
        _fail(type as String);
      case 'impression':
        onImpression?.call();
      case 'click':
        onClick?.call();
    }
    return true;
  }

  void _fail(String why) {
    if (state == NativeAdState.disposed) return;
    state = NativeAdState.failed;
    height = 1;
    notifyListeners();
    if (_retries < maxRetries) {
      _retries++;
      _retryTimer?.cancel();
      _retryTimer = Timer(retryDelay, _load);
      return;
    }
    if (!_failedReported) {
      _failedReported = true;
      onFailed?.call();
    }
  }

  @override
  void dispose() {
    state = NativeAdState.disposed;
    _retryTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }
}
