// Тренировки с часов Amazfit GTR 4 (тип данных 0x05, сводка тренировки).
//
// Формат проверен на одной реальной записи (прошивка 7.6.0.2): два байта заголовка и дальше
// protobuf. Сверка с подробностями тренировки (тип 0x06) сошлась: средний пульс 115, максимум
// 140, минимум 96, длительность 456 с. Не проверено: код вида активности (поле 2.3), калории,
// дистанция и формат нескольких тренировок в одном ответе. Эти поля не используются.
import 'dart:typed_data';

class WatchWorkout {
  final DateTime start;
  final int durationSec;
  final int avgHr, maxHr, minHr;

  /// Код вида активности из часов. Расшифровка не подтверждена, в интерфейсе не показывается.
  final int? typeCode;
  const WatchWorkout(this.start, this.durationSec, this.avgHr, this.maxHr,
      this.minHr, this.typeCode);

  DateTime get end => start.add(Duration(seconds: durationSec));
  String get externalId => 'ble-wk-${start.millisecondsSinceEpoch ~/ 1000}';
}

class _Field {
  final int no;
  final int? v;
  final Uint8List? b;
  const _Field(this.no, this.v, this.b);
}

/// Разбор protobuf верхнего уровня. null при любой неожиданности (обрыв, неизвестный тип).
List<_Field>? _fields(Uint8List d) {
  final out = <_Field>[];
  var i = 0;
  int? varint() {
    var r = 0, s = 0;
    while (i < d.length) {
      final x = d[i++];
      r |= (x & 0x7f) << s;
      if (x & 0x80 == 0) return r;
      s += 7;
      if (s > 56) return null;
    }
    return null;
  }

  while (i < d.length) {
    final k = varint();
    if (k == null) return null;
    final no = k >> 3;
    switch (k & 7) {
      case 0:
        final v = varint();
        if (v == null) return null;
        out.add(_Field(no, v, null));
      case 2:
        final l = varint();
        if (l == null || i + l > d.length) return null;
        out.add(_Field(no, null, Uint8List.sublistView(d, i, i + l)));
        i += l;
      case 5:
        if (i + 4 > d.length) return null;
        i += 4;
      case 1:
        if (i + 8 > d.length) return null;
        i += 8;
      default:
        return null;
    }
  }
  return out;
}

int? _int(List<_Field>? f, int no) {
  if (f == null) return null;
  for (final x in f) {
    if (x.no == no && x.v != null) return x.v;
  }
  return null;
}

List<_Field>? _sub(List<_Field>? f, int no) {
  if (f == null) return null;
  for (final x in f) {
    if (x.no == no && x.b != null) return _fields(x.b!);
  }
  return null;
}

/// Разбирает сводку тренировки. Возвращает null, если данные не похожи на проверенный формат
/// или значения неправдоподобны: лучше пропустить запись, чем сохранить выдуманную.
WatchWorkout? parseWatchWorkout(Uint8List data, {DateTime? now}) {
  if (data.length < 8) return null;
  final root = _fields(Uint8List.sublistView(data, 2));
  if (root == null) return null;
  final head = _sub(root, 2);
  final start = _int(head, 1);
  final dur = _int(_sub(root, 7), 1);
  final hr = _sub(root, 19);
  final avg = _int(hr, 1), max = _int(hr, 2), min = _int(hr, 3);
  if (start == null ||
      dur == null ||
      avg == null ||
      max == null ||
      min == null) {
    return null;
  }
  final t = now ?? DateTime.now();
  final s = DateTime.fromMillisecondsSinceEpoch(start * 1000);
  if (s.year < 2020 || s.isAfter(t.add(const Duration(days: 1)))) return null;
  if (dur < 30 || dur > 24 * 3600) return null;
  for (final x in [avg, max, min]) {
    if (x < 30 || x > 230) return null;
  }
  if (!(min <= avg && avg <= max)) return null;
  return WatchWorkout(s, dur, avg, max, min, _int(head, 3));
}

/// Вид тренировки по коду из часов. Подтверждён только код 48: пользователь запустил на часах
/// «силовую тренировку», и в сводке пришёл код 48. Остальные коды не расшифрованы.
String watchWorkoutType(int? code) =>
    code == 48 ? 'STRENGTH_TRAINING' : 'WATCH_ACTIVITY';
