// Загрузка истории с часов Huami / Zepp OS (характеристики 0004 и 0005).
// Протокол описан по Gadgetbridge (AGPLv3): AbstractFetchOperation,
// FetchActivityOperation, FetchSpo2NormalOperation. Реализация написана заново.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'huami_crypto.dart';

const fetchTypeActivity = 0x01;
const fetchTypeSpo2Normal = 0x25;

class FetchResult {
  final Uint8List data;
  final DateTime? start; // момент первой записи (UTC-инстант)
  final String? error;
  const FetchResult(this.data, this.start, [this.error]);
  bool get ok => error == null;
}

/// 8 байт времени запроса: год (u16 LE), месяц, день, час, минута, 0, часовой пояс (в четвертях часа).
Uint8List fetchTimeBytes(DateTime local) {
  final tz = (local.timeZoneOffset.inMinutes ~/ 15) & 0xFF;
  return Uint8List.fromList([
    local.year & 0xFF,
    (local.year >> 8) & 0xFF,
    local.month,
    local.day,
    local.hour,
    local.minute,
    0,
    tz,
  ]);
}

/// Разбор времени из ответа часов (год u16, мес, день, час, мин, сек, пояс int8).
DateTime parseFetchTime(Uint8List b, int o) {
  final year = b[o] | (b[o + 1] << 8);
  final tz = b[o + 7] > 127 ? b[o + 7] - 256 : b[o + 7];
  return DateTime.utc(year, b[o + 2], b[o + 3], b[o + 4], b[o + 5], b[o + 6])
      .subtract(Duration(minutes: tz * 15));
}

class HuamiFetcher {
  final BluetoothCharacteristic control; // 0004
  final BluetoothCharacteristic dataChar; // 0005
  HuamiFetcher(this.control, this.dataChar);

  Future<void> _write(List<int> v) =>
      control.write(v, withoutResponse: control.properties.writeWithoutResponse);

  /// Запрашивает данные [type] начиная с [since]. Подтверждает приём так, чтобы
  /// данные оставались на часах (0x09), ничего с часов не удаляется.
  Future<FetchResult> fetch(int type, DateTime since,
      {Duration timeout = const Duration(seconds: 20), void Function(String)? onStage}) async {
    final buffer = BytesBuilder();
    final response = StreamController<Uint8List>();
    var lastCounter = -1;
    var valid = true;
    StreamSubscription<List<int>>? ctlSub, dataSub;
    final it = StreamIterator(response.stream);
    try {
      await control.setNotifyValue(true);
      ctlSub = control.onValueReceived.listen((v) => response.add(Uint8List.fromList(v)));
      Future<Uint8List> next() async {
        if (!await it.moveNext().timeout(timeout)) throw StateError('соединение закрыто');
        return it.current;
      }

      onStage?.call('тип 0x${type.toRadixString(16)}: запрос отправлен');
      await _write([0x01, type, ...fetchTimeBytes(since)]);
      final r1 = await next();
      onStage?.call('тип 0x${type.toRadixString(16)}: ответ ${_hex(r1)}');
      if (r1.length < 3 || r1[0] != 0x10 || r1[1] != 0x01 || r1[2] != 0x01) {
        return FetchResult(Uint8List(0), null, 'Часы отклонили запрос (${_hex(r1)})');
      }
      if (r1.length < 15) {
        return FetchResult(Uint8List(0), null, 'Неожиданный ответ часов (${_hex(r1)})');
      }
      final expected = ByteData.sublistView(r1).getUint32(3, Endian.little);
      final start = parseFetchTime(r1, 7);
      if (expected == 0) {
        await _write([0x03, 0x09]);
        return FetchResult(Uint8List(0), start);
      }

      await dataChar.setNotifyValue(true);
      dataSub = dataChar.onValueReceived.listen((v) {
        if (v.isEmpty) return;
        if (((lastCounter + 1) & 0xFF) == v[0]) {
          lastCounter = v[0];
          buffer.add(v.sublist(1));
        } else {
          valid = false;
        }
      });
      onStage?.call('ожидается $expected байт, передача начата');
      await _write([0x02]);
      final r2 = await next();
      onStage?.call('передача завершена: ${buffer.length} байт');
      if (r2.length < 3 || r2[0] != 0x10 || r2[1] != 0x02 || r2[2] != 0x01) {
        return FetchResult(Uint8List(0), start, 'Часы прервали передачу (${_hex(r2)})');
      }
      final data = buffer.toBytes();
      if (!valid) return FetchResult(Uint8List(0), start, 'Потеряны пакеты данных, повторите');
      // Для активности часы называют число минутных записей (по 8 байт), для остального — байты.
      final expectedBytes = type == fetchTypeActivity && data.length == expected * 8
          ? expected * 8
          : expected;
      if (data.length != expectedBytes) {
        await _write([0x03, 0x09]);
        return FetchResult(
            Uint8List(0), start, 'Получено ${data.length} байт из $expected, повторите');
      }
      String? warn;
      if (r2.length == 7) {
        final crc = ByteData.sublistView(r2).getUint32(3, Endian.little);
        if (crc != crc32(data)) {
          // Для активности Gadgetbridge тоже не проверяет сумму; для остальных это ошибка.
          if (type != fetchTypeActivity) {
            await _write([0x03, 0x09]);
            return FetchResult(Uint8List(0), start, 'Контрольная сумма не совпала');
          }
          warn = null;
        }
      }
      await _write([0x03, 0x09]);
      return FetchResult(data, start, warn);
    } on TimeoutException {
      onStage?.call('таймаут: получено ${buffer.length} байт');
      return FetchResult(Uint8List(0), null, 'Часы не ответили вовремя');
    } catch (e) {
      return FetchResult(Uint8List(0), null, 'Ошибка загрузки: $e');
    } finally {
      // StreamIterator держит подписку приостановленной, поэтому close() не ждём:
      // иначе он не завершается и загрузка истории зависает навсегда.
      unawaited(it.cancel());
      unawaited(response.close());
      await ctlSub?.cancel();
      await dataSub?.cancel();
      try {
        await dataChar.setNotifyValue(false).timeout(const Duration(seconds: 5));
        await control.setNotifyValue(false).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
}

enum SleepStage { light, deep, rem }

class ActivitySample {
  final DateTime time;
  final int kind, intensity, steps, heartRate, sleep, deepSleep, remSleep;
  const ActivitySample(this.time, this.kind, this.intensity, this.steps, this.heartRate,
      this.sleep, this.deepSleep, this.remSleep);

  /// Вид 120 в записях Zepp OS — сон (без разбивки на фазы), 115 — часы сняты, 118 — зарядка.
  bool get isSleep => kind == 120;

  /// Фаза сна по эвристике Gadgetbridge (HuamiExtendedSampleProvider): пороги подобраны
  /// опытным путём и дают приблизительную разбивку, а не точное значение с часов.
  SleepStage get stage {
    final rem = remSleep & 127, deep = deepSleep & 127;
    if (rem > 55) return SleepStage.rem;
    if (deep > 42) return SleepStage.deep;
    return SleepStage.light;
  }

  /// 0 и 255 — «нет измерения» (допущение по формату Huami; требует проверки).
  bool get hasHeartRate => heartRate >= 30 && heartRate <= 230;
}

/// Минутные записи активности, 8 байт: вид, интенсивность, шаги, пульс, ?, сон, глубокий сон, REM.
List<ActivitySample>? parseActivity(Uint8List bytes, DateTime start) {
  if (bytes.length % 8 != 0) return null;
  final out = <ActivitySample>[];
  for (var i = 0, n = 0; i < bytes.length; i += 8, n++) {
    out.add(ActivitySample(start.add(Duration(minutes: n)), bytes[i], bytes[i + 1],
        bytes[i + 2], bytes[i + 3], bytes[i + 5], bytes[i + 6], bytes[i + 7]));
  }
  return out;
}

class Spo2Sample {
  final DateTime time;
  final int value;
  final bool automatic;
  const Spo2Sample(this.time, this.value, this.automatic);
}

/// SpO2: версия 2, затем записи по 65 байт: время (u32 LE, секунды Unix), значение
/// (бит 7 — автоматическое измерение), 60 байт неизвестного назначения.
List<Spo2Sample>? parseSpo2(Uint8List bytes) {
  if (bytes.isEmpty || (bytes.length - 1) % 65 != 0 || bytes[0] != 2) return null;
  final bd = ByteData.sublistView(bytes);
  final out = <Spo2Sample>[];
  for (var o = 1; o < bytes.length; o += 65) {
    final raw = bytes[o + 4];
    final auto = raw >= 128;
    out.add(Spo2Sample(
        DateTime.fromMillisecondsSinceEpoch(bd.getUint32(o, Endian.little) * 1000,
            isUtc: true),
        auto ? raw - 128 : raw,
        auto));
  }
  return out;
}
