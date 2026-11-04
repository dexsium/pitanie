// Настройки часов Zepp OS по Bluetooth: группа «Здоровье» службы конфигурации (точка 0x000a),
// время и «найти часы». Формат команд описан по Gadgetbridge (AGPLv3): ZeppOsConfigService,
// ZeppOsSupport. Реализация написана заново. Не проверено на всех моделях: GTR 4 принимает
// только то, что объявляет в ответе на запрос, поэтому перед записью настройки читаются.
import 'dart:typed_data';

const cfgEndpoint = 0x000a;
const findEndpoint = 0x001a;

const _cmdRequest = 0x03;
const cmdResponse = 0x04;
const _cmdSet = 0x05;
const cmdAck = 0x06;

const groupHealth = 0x08;
const _groupHealthVersion = 0x02;

const _typeBool = 0x0b;
const _typeByte = 0x10;

/// Ключи группы «Здоровье».
const keyHrInterval =
    0x01; // байт: минуты между измерениями, 0 — выкл., 0xFF (−1) — авто
const keySleepHr = 0x11; // булево: точный мониторинг сна по пульсу
const keySleepBreathing = 0x12; // булево: качество дыхания во сне
const keyStress = 0x13; // булево: мониторинг стресса
const keySpo2AllDay = 0x31; // булево: SpO₂ в течение суток

const healthKeys = [
  keyHrInterval,
  keySleepHr,
  keySleepBreathing,
  keyStress,
  keySpo2AllDay
];

/// Допустимые интервалы измерения пульса, минуты: 0 — выключено, -1 — автоматически.
const hrIntervals = [0, -1, 1, 5, 10, 30];

class WatchHealthSettings {
  final int? hrInterval;
  final bool? sleepHr, sleepBreathing, stress, spo2AllDay;
  const WatchHealthSettings(
      {this.hrInterval,
      this.sleepHr,
      this.sleepBreathing,
      this.stress,
      this.spo2AllDay});

  WatchHealthSettings merge(WatchHealthSettings o) => WatchHealthSettings(
        hrInterval: o.hrInterval ?? hrInterval,
        sleepHr: o.sleepHr ?? sleepHr,
        sleepBreathing: o.sleepBreathing ?? sleepBreathing,
        stress: o.stress ?? stress,
        spo2AllDay: o.spo2AllDay ?? spo2AllDay,
      );

  Map<String, dynamic> toJson() => {
        if (hrInterval != null) 'hr': hrInterval,
        if (sleepHr != null) 'sh': sleepHr,
        if (sleepBreathing != null) 'sb': sleepBreathing,
        if (stress != null) 'st': stress,
        if (spo2AllDay != null) 'sp': spo2AllDay,
      };

  static WatchHealthSettings fromJson(Map j) => WatchHealthSettings(
        hrInterval: j['hr'] as int?,
        sleepHr: j['sh'] as bool?,
        sleepBreathing: j['sb'] as bool?,
        stress: j['st'] as bool?,
        spo2AllDay: j['sp'] as bool?,
      );

  bool get isEmpty =>
      hrInterval == null &&
      sleepHr == null &&
      sleepBreathing == null &&
      stress == null &&
      spo2AllDay == null;
}

String hrIntervalLabel(int v) => switch (v) {
      0 => 'Выключено',
      -1 => 'Автоматически',
      1 => 'Каждую минуту',
      _ => 'Каждые $v мин',
    };

/// Запрос текущих значений (без ограничений в ответе).
Uint8List encodeHealthRequest([List<int> keys = healthKeys]) =>
    Uint8List.fromList([_cmdRequest, 0x00, groupHealth, keys.length, ...keys]);

/// Запись: значение bool — для булевых ключей, int — для байтовых (интервал: −1 → 0xFF).
Uint8List encodeHealthSet(Map<int, Object> values) {
  final out = <int>[
    _cmdSet,
    groupHealth,
    _groupHealthVersion,
    0x00,
    values.length
  ];
  values.forEach((key, v) {
    if (v is bool) {
      out.addAll([key, _typeBool, v ? 1 : 0]);
    } else if (v is int) {
      out.addAll([key, _typeByte, v & 0xFF]);
    } else {
      throw ArgumentError('Недопустимое значение для ключа $key');
    }
  });
  return Uint8List.fromList(out);
}

/// Разбор ответа на запрос группы «Здоровье»: [04, статус, группа, версия, ограничения, число, ...].
/// null — формат не распознан (запись при этом не выполняется).
WatchHealthSettings? parseHealthResponse(Uint8List p) {
  if (p.length < 6 || p[0] != cmdResponse || p[1] != 1 || p[2] != groupHealth)
    return null;
  final constraints = p[4] == 1;
  final count = p[5];
  var o = 6;
  int? hr;
  bool? sh, sb, st, sp;
  for (var i = 0; i < count && o + 2 <= p.length; i++) {
    final key = p[o], type = p[o + 1];
    o += 2;
    if (type == _typeBool) {
      if (o >= p.length) return null;
      final v = p[o++] == 1;
      switch (key) {
        case keySleepHr:
          sh = v;
        case keySleepBreathing:
          sb = v;
        case keyStress:
          st = v;
        case keySpo2AllDay:
          sp = v;
      }
    } else if (type == _typeByte) {
      if (o >= p.length) return null;
      final raw = p[o++];
      if (constraints) {
        if (o >= p.length) return null;
        o += 1 + p[o]; // список допустимых значений
      }
      if (key == keyHrInterval) hr = raw > 127 ? raw - 256 : raw;
    } else {
      break; // тип, размер которого неизвестен: дальше разбирать нельзя
    }
  }
  final s = WatchHealthSettings(
      hrInterval: hr,
      sleepHr: sh,
      sleepBreathing: sb,
      stress: st,
      spo2AllDay: sp);
  return s.isEmpty ? null : s;
}

/// Время для характеристики Current Time (2A2B): 11 байт, как у Zepp OS в Gadgetbridge.
Uint8List currentTimeBytes(DateTime local) {
  final tz = (local.timeZoneOffset.inMinutes ~/ 15) & 0xFF;
  return Uint8List.fromList([
    local.year & 0xFF,
    (local.year >> 8) & 0xFF,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
    local.weekday % 7, // 0 — воскресенье
    0x00,
    0x08,
    tz,
  ]);
}

const findStart = 0x03;
const findStopFromPhone = 0x06;
const findAck = 0x04;
const findStopFromBand = 0x07;
