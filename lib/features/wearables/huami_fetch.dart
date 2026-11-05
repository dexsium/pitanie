// Загрузка истории с часов Huami / Zepp OS (характеристики 0004 и 0005).
// Протокол описан по Gadgetbridge (AGPLv3): AbstractFetchOperation,
// FetchActivityOperation, FetchSpo2NormalOperation, FetchHeartRateRestingOperation,
// FetchHeartRateMaxOperation, FetchStressAutoOperation, FetchSleepRespiratoryRateOperation.
// Реализация написана заново.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'huami_crypto.dart';

const fetchTypeActivity = 0x01;
const fetchTypeSpo2Normal = 0x25;
const fetchTypeStressAuto = 0x13;
const fetchTypeSleepResp = 0x38;
const fetchTypeRestingHr = 0x3a;
const fetchTypeMaxHr = 0x3d;

class FetchResult {
  final Uint8List data;
  final DateTime? start; // момент первой записи (UTC-инстант)
  final String? error;
  final String? note; // пояснение к принятым данным (диагностика)
  const FetchResult(this.data, this.start, [this.error, this.note]);
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

  Future<void> _write(List<int> v) => control.write(v,
      withoutResponse: control.properties.writeWithoutResponse);

  /// Запрашивает данные [type] начиная с [since]. Подтверждает приём так, чтобы
  /// данные оставались на часах (0x09), ничего с часов не удаляется.
  /// [maxBytes]: если часы объявляют больше, данные не загружаются (для диагностики).
  Future<FetchResult> fetch(int type, DateTime since,
      {Duration timeout = const Duration(seconds: 20),
      void Function(String)? onStage,
      int? maxBytes,
      bool lenient = false}) async {
    final buffer = BytesBuilder();
    final response = StreamController<Uint8List>();
    var lastCounter = -1;
    var valid = true;
    StreamSubscription<List<int>>? ctlSub, dataSub;
    final it = StreamIterator(response.stream);
    try {
      await control.setNotifyValue(true);
      ctlSub = control.onValueReceived
          .listen((v) => response.add(Uint8List.fromList(v)));
      Future<Uint8List> next() async {
        if (!await it.moveNext().timeout(timeout))
          throw StateError('соединение закрыто');
        return it.current;
      }

      onStage?.call('тип 0x${type.toRadixString(16)}: запрос отправлен');
      await _write([0x01, type, ...fetchTimeBytes(since)]);
      final r1 = await next();
      onStage?.call('тип 0x${type.toRadixString(16)}: ответ ${_hex(r1)}');
      if (r1.length < 3 || r1[0] != 0x10 || r1[1] != 0x01 || r1[2] != 0x01) {
        return FetchResult(
            Uint8List(0), null, 'Часы отклонили запрос (${_hex(r1)})');
      }
      if (r1.length < 15) {
        return FetchResult(
            Uint8List(0), null, 'Неожиданный ответ часов (${_hex(r1)})');
      }
      final expected = ByteData.sublistView(r1).getUint32(3, Endian.little);
      final start = parseFetchTime(r1, 7);
      if (expected == 0) {
        await _write([0x03, 0x09]);
        return FetchResult(Uint8List(0), start);
      }
      if (maxBytes != null && expected > maxBytes) {
        await _write([0x03, 0x09]);
        return FetchResult(Uint8List(0), start,
            'Объявлено $expected байт, больше лимита $maxBytes');
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
        return FetchResult(
            Uint8List(0), start, 'Часы прервали передачу (${_hex(r2)})');
      }
      final data = buffer.toBytes();
      if (!valid)
        return FetchResult(
            Uint8List(0), start, 'Потеряны пакеты данных, повторите');
      // Для активности часы называют число минутных записей (по 8 байт), для остального — байты.
      final expectedBytes =
          type == fetchTypeActivity && data.length == expected * 8
              ? expected * 8
              : expected;
      if (lenient && data.isNotEmpty && data.length != expectedBytes) {
        await _write([0x03, 0x09]);
        return FetchResult(data, start, null,
            'размер не совпал: заявлено $expected, получено ${data.length} байт');
      }
      if (data.length != expectedBytes) {
        await _write([0x03, 0x09]);
        return FetchResult(Uint8List(0), start,
            'Получено ${data.length} байт из $expected, повторите');
      }
      String? warn;
      if (r2.length == 7) {
        final crc = ByteData.sublistView(r2).getUint32(3, Endian.little);
        if (crc != crc32(data)) {
          // Для активности Gadgetbridge тоже не проверяет сумму; для остальных это ошибка.
          if (type != fetchTypeActivity) {
            await _write([0x03, 0x09]);
            return FetchResult(
                Uint8List(0), start, 'Контрольная сумма не совпала');
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
        await dataChar
            .setNotifyValue(false)
            .timeout(const Duration(seconds: 5));
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
  const ActivitySample(this.time, this.kind, this.intensity, this.steps,
      this.heartRate, this.sleep, this.deepSleep, this.remSleep);

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
    out.add(ActivitySample(
        start.add(Duration(minutes: n)),
        bytes[i],
        bytes[i + 1],
        bytes[i + 2],
        bytes[i + 3],
        bytes[i + 5],
        bytes[i + 6],
        bytes[i + 7]));
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
  if (bytes.isEmpty || (bytes.length - 1) % 65 != 0 || bytes[0] != 2)
    return null;
  final bd = ByteData.sublistView(bytes);
  final out = <Spo2Sample>[];
  for (var o = 1; o < bytes.length; o += 65) {
    final raw = bytes[o + 4];
    final auto = raw >= 128;
    out.add(Spo2Sample(
        DateTime.fromMillisecondsSinceEpoch(
            bd.getUint32(o, Endian.little) * 1000,
            isUtc: true),
        auto ? raw - 128 : raw,
        auto));
  }
  return out;
}

/// Дневное значение пульса: 6 байт — время (u32 LE, секунды Unix), смещение пояса
/// (четверти часа, int8), пульс (u8). Так передаются «пульс в покое» и «максимальный пульс».
class DayHeartSample {
  final DateTime time;
  final int bpm;
  const DayHeartSample(this.time, this.bpm);
}

List<DayHeartSample>? parseDayHeart(Uint8List bytes) {
  if (bytes.length % 6 != 0) return null;
  final bd = ByteData.sublistView(bytes);
  return [
    for (var o = 0; o < bytes.length; o += 6)
      DayHeartSample(
          DateTime.fromMillisecondsSinceEpoch(
              bd.getUint32(o, Endian.little) * 1000,
              isUtc: true),
          bytes[o + 5])
  ];
}

class MinuteValue {
  final DateTime time;
  final int value;
  const MinuteValue(this.time, this.value);
}

/// Автоматический стресс: по одному байту на минуту от времени начала ответа; 0xFF — нет
/// измерения (минута пропускается). Значения 0–100.
List<MinuteValue> parseStress(Uint8List bytes, DateTime start) {
  final out = <MinuteValue>[];
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0xFF || bytes[i] > 100) continue;
    out.add(MinuteValue(start.add(Duration(minutes: i)), bytes[i]));
  }
  return out;
}

/// Дыхание во сне: 8 байт — время (u32 LE), смещение пояса (int8), частота дыхания (u8),
/// два байта неизвестного назначения.
List<MinuteValue>? parseSleepResp(Uint8List bytes) {
  if (bytes.length % 8 != 0) return null;
  final bd = ByteData.sublistView(bytes);
  return [
    for (var o = 0; o < bytes.length; o += 8)
      MinuteValue(
          DateTime.fromMillisecondsSinceEpoch(
              bd.getUint32(o, Endian.little) * 1000,
              isUtc: true),
          bytes[o + 5])
  ];
}

/// Диагностика: грубый разбор protobuf без схемы. Поле:тип=значение, вложенные сообщения в [].
String dumpProtobuf(Uint8List b, [int depth = 0]) {
  final out = <String>[];
  var o = 0;
  int? varint() {
    var r = 0, shift = 0;
    while (o < b.length && shift < 63) {
      final x = b[o++];
      r |= (x & 0x7f) << shift;
      if (x & 0x80 == 0) return r;
      shift += 7;
    }
    return null;
  }

  while (o < b.length) {
    final tag = varint();
    if (tag == null) return '${out.join(' ')} ?обрыв';
    final field = tag >> 3, wt = tag & 7;
    if (field == 0) return '${out.join(' ')} ?поле0';
    switch (wt) {
      case 0:
        final v = varint();
        if (v == null) return '${out.join(' ')} ?обрыв';
        out.add('$field=$v');
      case 1:
        if (o + 8 > b.length) return '${out.join(' ')} ?обрыв';
        out.add(
            '$field:f64=${ByteData.sublistView(b, o, o + 8).getFloat64(0, Endian.little).toStringAsFixed(3)}');
        o += 8;
      case 5:
        if (o + 4 > b.length) return '${out.join(' ')} ?обрыв';
        final bd = ByteData.sublistView(b, o, o + 4);
        out.add(
            '$field:i32=${bd.getUint32(0, Endian.little)}/f${bd.getFloat32(0, Endian.little).toStringAsFixed(3)}');
        o += 4;
      case 2:
        final n = varint();
        if (n == null || o + n > b.length) return '${out.join(' ')} ?обрыв';
        final sub = Uint8List.sublistView(b, o, o + n);
        o += n;
        if (depth < 3 && n > 1) {
          final d = dumpProtobuf(sub, depth + 1);
          if (!d.contains('?')) {
            out.add('$field[$d]');
            break;
          }
        }
        out.add('$field:b$n');
      default:
        return '${out.join(' ')} ?тип$wt';
    }
  }
  return out.join(' ');
}

/// Диагностика: сводка по потоку событий (тип 0x2c): типы событий и параметры внутри них.
/// Поток — protobuf; записи — поле 5, внутри: 1 — номер события, 2/3 — числа, 5 — пары
/// (1 — номер параметра, 2 — значение). Возвращает строки для журнала.
List<String> summarizeEvents(Uint8List data) {
  for (final skip in const [4, 0]) {
    final r = _summarizeEventsAt(data, skip);
    if (r.isNotEmpty) return r;
  }
  return const ['не удалось разобрать как protobuf'];
}

class _Rd {
  final Uint8List b;
  int o;
  _Rd(this.b, this.o);
  bool get more => o < b.length;
  int? varint() {
    var r = 0, shift = 0;
    while (o < b.length && shift < 64) {
      final x = b[o++];
      r |= (x & 0x7f) << shift;
      if (x & 0x80 == 0) return r;
      shift += 7;
    }
    return null;
  }

  /// Пропускает значение поля; для вложенных данных возвращает диапазон.
  (int, int)? skipValue(int wt) {
    switch (wt) {
      case 0:
        return varint() == null ? null : (0, 0);
      case 1:
        o += 8;
        return o <= b.length ? (0, 0) : null;
      case 5:
        o += 4;
        return o <= b.length ? (0, 0) : null;
      case 2:
        final n = varint();
        if (n == null || n < 0 || o + n > b.length) return null;
        final s = o;
        o += n;
        return (s, o);
      default:
        return null;
    }
  }
}

List<String> _summarizeEventsAt(Uint8List data, int skip) {
  final events = <int, _EvStat>{};
  final top = _Rd(data, skip);
  var records = 0;
  while (top.more) {
    final tag = top.varint();
    if (tag == null) break;
    final wt = tag & 7;
    if (tag >> 3 == 5 && wt == 2) {
      final n = top.varint();
      if (n == null || top.o + n > data.length) break;
      final end = top.o + n;
      final rec = _Rd(data, top.o);
      top.o = end;
      int? id;
      final params = <int, List<int>>{};
      while (rec.o < end) {
        final t = rec.varint();
        if (t == null) break;
        final f = t >> 3, w = t & 7;
        if (f == 1 && w == 0) {
          id = rec.varint();
        } else if (f == 5 && w == 2) {
          final m = rec.varint();
          if (m == null || rec.o + m > end) break;
          final sub = _Rd(data, rec.o);
          final subEnd = rec.o + m;
          rec.o = subEnd;
          int? pid, pv;
          while (sub.o < subEnd) {
            final st = sub.varint();
            if (st == null) break;
            if (st >> 3 == 1 && st & 7 == 0) {
              pid = sub.varint();
            } else if (st >> 3 == 2 && st & 7 == 0) {
              pv = sub.varint();
            } else if (sub.skipValue(st & 7) == null) {
              break;
            }
          }
          if (pid != null && pv != null) (params[pid] ??= []).add(pv);
        } else if (rec.skipValue(w) == null) {
          break;
        }
      }
      if (id != null) {
        records++;
        final st = events[id] ??= _EvStat();
        st.count++;
        params.forEach((k, v) => (st.params[k] ??= []).addAll(v));
      }
    } else if (top.skipValue(wt) == null) {
      break;
    }
  }
  if (records == 0) return const [];
  final out = <String>['записей: $records, типов событий: ${events.length}'];
  final keys = events.keys.toList()
    ..sort((a, b) => events[b]!.count.compareTo(events[a]!.count));
  for (final k in keys.take(40)) {
    final st = events[k]!;
    final ps = <String>[];
    final pk = st.params.keys.toList()..sort();
    for (final p in pk.take(8)) {
      final v = st.params[p]!;
      var mn = v.first, mx = v.first;
      for (final x in v) {
        if (x < mn) mn = x;
        if (x > mx) mx = x;
      }
      ps.add('$p:${v.length}×[$mn..$mx]');
    }
    out.add(
        '  событие $k (0x${k.toRadixString(16)}) ×${st.count}: ${ps.join(' ')}');
  }
  return out;
}

class _EvStat {
  int count = 0;
  final Map<int, List<int>> params = {};
}
