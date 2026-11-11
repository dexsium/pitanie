// Подключение к весам со стандартными сервисами Bluetooth SIG: поиск характеристик, подписка,
// сбор измерения, отключение. Не проверялось на реальных весах; ошибки возвращаются как текст
// и не прерывают работу приложения.
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'scale_driver.dart';
import 'standard_scale.dart';

/// Адаптер результата сканирования к описанию, не зависящему от библиотеки Bluetooth.
ScaleAdvert advertOf(ScanResult r) {
  final ad = r.advertisementData;
  return ScaleAdvert(
    ad.advName.isNotEmpty ? ad.advName : r.device.platformName,
    {for (final g in ad.serviceUuids) shortUuid(g.str128)},
    {for (final e in ad.serviceData.entries) shortUuid(e.key.str128): e.value},
  );
}

class GattScaleResult {
  final ScaleMeasurement? measurement;
  final String? error;
  const GattScaleResult(this.measurement, this.error);
}

/// Одно подключение к весам: ждёт измерение и отключается.
/// [onProgress] вызывается при каждом новом значении массы (для окна «Измерение веса»).
Future<GattScaleResult> readGattScale(
  BluetoothDevice device, {
  void Function(double kg)? onProgress,
  Duration window = const Duration(seconds: 40),
  Duration quiet = const Duration(seconds: 4),
}) async {
  final subs = <StreamSubscription>[];
  var merged = ScaleMeasurement.empty;
  DateTime? lastData;
  try {
    // Лицензия flutter_blue_plus: выбрана владельцем проекта (некоммерческая, см. docs/STAGE3_REPORT.md).
    await device.connect(
        license: License.nonprofit, timeout: const Duration(seconds: 15), autoConnect: false);
    final services = await device.discoverServices();
    final chars = <BluetoothCharacteristic>[];
    for (final s in services) {
      for (final c in s.characteristics) {
        final id = shortUuid(c.uuid.str128);
        if (id == kWeightMeasurementChar || id == kBodyCompositionChar) chars.add(c);
      }
    }
    if (chars.isEmpty) {
      return const GattScaleResult(null, 'у весов нет стандартных характеристик веса');
    }
    for (final c in chars) {
      final id = shortUuid(c.uuid.str128);
      subs.add(c.onValueReceived.listen((v) {
        final m = parseCharacteristic(id, v);
        if (m == null) return;
        merged = merged.merge(m);
        lastData = DateTime.now();
        final kg = merged.weightKg;
        if (kg != null) onProgress?.call(kg);
      }));
      await c.setNotifyValue(true);
    }
    final started = DateTime.now();
    while (DateTime.now().difference(started) < window) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final last = lastData;
      if (merged.weightKg != null && last != null) {
        // Весы шлют несколько значений, пока вес устанавливается: ждём паузу.
        if (DateTime.now().difference(last) >= quiet) break;
      }
      if (device.isDisconnected && merged.weightKg != null) break;
      if (device.isDisconnected && merged.weightKg == null) {
        return const GattScaleResult(null, 'соединение с весами оборвалось до измерения');
      }
    }
    if (merged.weightKg == null) {
      return const GattScaleResult(null, 'весы не передали вес');
    }
    return GattScaleResult(merged, null);
  } catch (e) {
    return GattScaleResult(merged.weightKg != null ? merged : null, '$e');
  } finally {
    for (final s in subs) {
      await s.cancel();
    }
    try {
      await device.disconnect();
    } catch (_) {}
  }
}
