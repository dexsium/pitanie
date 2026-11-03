/// Защита от двойного подсчёта активности. Чистая логика без БД.
class Interval {
  final String source;
  final DateTime start, end;
  final double value;
  const Interval(this.source, this.start, this.end, this.value);
}

/// Доля интервала, попадающая в [from, to). Для нулевой длины — целиком или 0.
double overlapFraction(Interval r, DateTime from, DateTime to) {
  final dur = r.end.difference(r.start).inMilliseconds;
  if (dur <= 0) {
    return (!r.start.isBefore(from) && r.start.isBefore(to)) ? 1 : 0;
  }
  final s = r.start.isAfter(from) ? r.start : from;
  final e = r.end.isBefore(to) ? r.end : to;
  final ov = e.difference(s).inMilliseconds;
  return ov <= 0 ? 0 : ov / dur;
}

/// Перекрывающиеся записи одного источника не суммируются: остаётся запись
/// с большим значением.
List<Interval> resolveOverlaps(Iterable<Interval> recs) {
  final sorted = recs.toList()..sort((a, b) => a.start.compareTo(b.start));
  final out = <Interval>[];
  for (final r in sorted) {
    if (out.isNotEmpty && r.start.isBefore(out.last.end)) {
      if (r.value > out.last.value) out[out.length - 1] = r;
    } else {
      out.add(r);
    }
  }
  return out;
}

double _sum(Iterable<Interval> recs, DateTime from, DateTime to) {
  var t = 0.0;
  for (final r in resolveOverlaps(recs)) {
    t += r.value * overlapFraction(r, from, to);
  }
  return t;
}

/// Выбор одного источника на сутки: приоритетный (если есть данные),
/// иначе источник с наибольшим объёмом.
String? pickSource(
    Iterable<Interval> recs, DateTime from, DateTime to, String? preferred) {
  final bySource = <String, List<Interval>>{};
  for (final r in recs) {
    if (overlapFraction(r, from, to) > 0) {
      bySource.putIfAbsent(r.source, () => []).add(r);
    }
  }
  if (bySource.isEmpty) return null;
  if (preferred != null && bySource.containsKey(preferred)) return preferred;
  String? best;
  var bestV = -1.0;
  bySource.forEach((s, list) {
    final v = _sum(list, from, to);
    if (v > bestV) {
      bestV = v;
      best = s;
    }
  });
  return best;
}

/// Сумма значения за сутки по выбранному источнику.
double dayTotal(Iterable<Interval> recs, DateTime from, DateTime to,
    {String? preferred}) {
  final src = pickSource(recs, from, to, preferred);
  if (src == null) return 0;
  return _sum(recs.where((r) => r.source == src), from, to);
}

/// Записи выбранного источника, попадающие в сутки (для пульса и т. п.).
List<Interval> dayRecords(Iterable<Interval> recs, DateTime from, DateTime to,
    {String? preferred}) {
  final src = pickSource(recs, from, to, preferred);
  if (src == null) return [];
  return recs
      .where((r) => r.source == src && overlapFraction(r, from, to) > 0)
      .toList();
}

/// Длительность объединения интервалов в минутах (пересечения не суммируются).
double unionMinutes(List<(DateTime, DateTime)> spans, DateTime from, DateTime to) {
  final list = spans
      .map((s) => (s.$1.isBefore(from) ? from : s.$1, s.$2.isAfter(to) ? to : s.$2))
      .where((s) => s.$2.isAfter(s.$1))
      .toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  var total = 0;
  DateTime? curS, curE;
  for (final s in list) {
    if (curE == null || s.$1.isAfter(curE)) {
      if (curS != null) total += curE!.difference(curS).inSeconds;
      curS = s.$1;
      curE = s.$2;
    } else if (s.$2.isAfter(curE)) {
      curE = s.$2;
    }
  }
  if (curS != null) total += curE!.difference(curS).inSeconds;
  return total / 60;
}
