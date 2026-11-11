import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/ads/native_ad_config.dart';
import 'package:pitanie/features/ads/native_ad_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var viewId = 100;
  late String channelName;
  late int loadCalls;

  setUp(() {
    viewId++;
    channelName = 'pitanie_native_ad.$viewId';
    loadCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channelName), (call) async {
      if (call.method == 'load') loadCalls++;
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(channelName), null));

  Future<void> emit(Map<String, Object?> payload) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          channelName,
          const StandardMethodCodec().encodeMethodCall(MethodCall('event', payload)),
          (_) {});

  test('настройки: рабочий блок, демо-блок и переключатель режима', () {
    expect(kNativeAdProductionUnitId, 'R-M-20382283-1');
    expect(kNativeAdDemoUnitId, 'demo-native-app-yandex');
    // По умолчанию на время проверки интеграции включена демонстрационная реклама.
    expect(kNativeAdUseDemo, isTrue);
    expect(kNativeAdUnitId, kNativeAdDemoUnitId);
    expect(kNativeAdViewType, 'pitanie/native_ad');
  });

  test('после создания представления запускается одна загрузка, показ только после loaded', () async {
    var loaded = 0, shown = 0;
    final c = NativeAdController(onLoaded: () => loaded++, onImpression: () => shown++);
    expect(c.state, NativeAdState.idle);
    expect(c.height, 1);
    c.attach(viewId);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, NativeAdState.loading);
    expect(loadCalls, 1);
    expect(c.height, 1, reason: 'до загрузки карточка не занимает места');

    await emit({'type': 'loaded', 'height': 260.4});
    expect(c.state, NativeAdState.loaded);
    expect(c.height, closeTo(260.4, 1e-9));
    expect(loaded, 1);
    expect(shown, 0, reason: 'создание виджета не считается показом');
    await emit({'type': 'impression'});
    expect(shown, 1);
    c.dispose();
  });

  test('высота ограничена разумными пределами', () async {
    final c = NativeAdController()..attach(viewId);
    await emit({'type': 'loaded', 'height': 5});
    expect(c.height, 120);
    await emit({'type': 'loaded', 'height': 99999});
    expect(c.height, 1200);
    c.dispose();
  });

  test('ошибка: одна повторная попытка с задержкой, затем карточка убирается', () async {
    var failed = 0;
    final c = NativeAdController(
        onFailed: () => failed++, retryDelay: const Duration(milliseconds: 20))
      ..attach(viewId);
    await Future<void>.delayed(Duration.zero);
    await emit({'type': 'failed', 'code': 1});
    expect(c.state, NativeAdState.failed);
    expect(c.height, 1);
    expect(failed, 0, reason: 'сначала повторная попытка');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(loadCalls, 2);
    expect(c.state, NativeAdState.loading);
    await emit({'type': 'bindFailed'});
    expect(failed, 1, reason: 'после второй ошибки карточка убирается');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(loadCalls, 2, reason: 'больше попыток нет');
    c.dispose();
  });

  test('успех после первой ошибки: убирать карточку не нужно', () async {
    var failed = 0, loaded = 0;
    final c = NativeAdController(
        onFailed: () => failed++,
        onLoaded: () => loaded++,
        retryDelay: const Duration(milliseconds: 10))
      ..attach(viewId);
    await emit({'type': 'failed'});
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await emit({'type': 'loaded', 'height': 300});
    expect(failed, 0);
    expect(loaded, 1);
    expect(c.state, NativeAdState.loaded);
    c.dispose();
  });

  test('после удаления события игнорируются и повтор не запускается', () async {
    var loaded = 0, failed = 0;
    final c = NativeAdController(
        onLoaded: () => loaded++,
        onFailed: () => failed++,
        retryDelay: const Duration(milliseconds: 10))
      ..attach(viewId);
    await emit({'type': 'failed'});
    c.dispose();
    expect(c.state, NativeAdState.disposed);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(loadCalls, 1, reason: 'повтор после удаления не запускается');
    await emit({'type': 'loaded', 'height': 300});
    expect(loaded, 0);
    expect(failed, 0);
  });
}
