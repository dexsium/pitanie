// Разбор сна по записям из Здоровья (Apple Health / Health Connect) и прежним минутным записям. Всё считается из данных часов;
// фазы сна — приблизительная оценка (правила Gadgetbridge), а не точное измерение.
import '../../core/dates.dart';
import '../../database/database.dart';

enum SleepKind { awake, light, rem, deep }

class SleepSegment {
  final DateTime start, end;
  final SleepKind kind;
  const SleepSegment(this.start, this.end, this.kind);
  int get minutes => end.difference(start).inMinutes;
}

class SleepSession {
  final DateTime start, end;
  final int sleepMin, deepMin, remMin, lightMin, awakeMin, wakeups;
  final List<SleepSegment> segments;
  const SleepSession(this.start, this.end, this.sleepMin, this.deepMin, this.remMin, this.lightMin,
      this.awakeMin, this.wakeups, this.segments);

  /// Время в постели: от первой до последней минуты сна по данным часов.
  int get inBedMin => end.difference(start).inMinutes;

  /// Эффективность: доля времени сна от времени в постели.
  double get efficiency => inBedMin <= 0 ? 0 : sleepMin / inBedMin;
}

class SleepDay {
  final SleepSession? night;
  final SleepSession? nap;
  const SleepDay(this.night, this.nap);
  static const empty = SleepDay(null, null);
}

/// Между минутами сна больше этого интервала начинается новый эпизод сна (например, дневной).
const _sessionGapMin = 60;

/// Пауза внутри ночи от этой длины считается пробуждением.
const _wakeGapMin = 5;

/// Эпизоды короче этого не считаются сном (шум датчика).
const _minSessionMin = 20;

int _minute(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;
DateTime _fromMinute(int m) => DateTime.fromMillisecondsSinceEpoch(m * 60000);

/// Минуты записи: минутная запись даёт одну минуту, запись из Здоровья — весь свой интервал.
Iterable<int> _recordMinutes(ActivityRecord r) {
  final a = _minute(r.startTime);
  var b = _minute(r.endTime);
  if (b <= a) b = a + 1;
  if (b - a > 1440) b = a + 1440;
  return [for (var m = a; m < b; m++) m];
}

List<SleepSession> sleepSessions(List<ActivityRecord> recs) {
  final sleepMin = <int>{};
  final stage = <int, SleepKind>{};
  for (final r in recs) {
    final kind = switch (r.type) {
      'sleepDeep' => SleepKind.deep,
      'sleepRem' => SleepKind.rem,
      'sleepLight' => SleepKind.light,
      _ => null,
    };
    if (r.type != 'sleep' && kind == null) continue;
    for (final m in _recordMinutes(r)) {
      // Минуты фаз тоже считаются сном: источник мог записать только фазы.
      sleepMin.add(m);
      if (kind != null) stage[m] = kind;
    }
  }
  final ms = sleepMin.toList()..sort();
  if (ms.isEmpty) return const [];
  final groups = <List<int>>[];
  for (final m in ms) {
    if (groups.isEmpty || m - groups.last.last > _sessionGapMin) {
      groups.add([m]);
    } else {
      groups.last.add(m);
    }
  }
  final out = <SleepSession>[];
  for (final g in groups) {
    if (g.length < _minSessionMin) continue;
    var deep = 0, rem = 0, light = 0, awake = 0, wakeups = 0;
    final segs = <SleepSegment>[];
    void add(int m, SleepKind k) {
      final s = _fromMinute(m), e = _fromMinute(m + 1);
      if (segs.isNotEmpty && segs.last.kind == k && segs.last.end == s) {
        final last = segs.removeLast();
        segs.add(SleepSegment(last.start, e, k));
      } else {
        segs.add(SleepSegment(s, e, k));
      }
    }

    for (var i = 0; i < g.length; i++) {
      if (i > 0) {
        final gap = g[i] - g[i - 1] - 1;
        if (gap > 0) {
          awake += gap;
          if (gap >= _wakeGapMin) wakeups++;
          for (var m = g[i - 1] + 1; m < g[i]; m++) {
            add(m, SleepKind.awake);
          }
        }
      }
      final k = stage[g[i]] ?? SleepKind.light;
      switch (k) {
        case SleepKind.deep:
          deep++;
        case SleepKind.rem:
          rem++;
        default:
          light++;
      }
      add(g[i], k);
    }
    out.add(SleepSession(_fromMinute(g.first), _fromMinute(g.last + 1), g.length, deep, rem, light,
        awake, wakeups, segs));
  }
  return out;
}

/// Сон относится ко дню пробуждения: окно 18:00 → 18:00, как и в остальном приложении.
bool inSleepWindow(DateTime t, DateTime day) {
  const six = Duration(hours: 6);
  return !t.isBefore(dayStart(day).subtract(six)) && t.isBefore(dayEnd(day).subtract(six));
}

SleepDay analyzeSleepDay(List<ActivityRecord> recs, DateTime day) {
  final sessions = sleepSessions([for (final r in recs) if (inSleepWindow(r.startTime, day)) r]);
  if (sessions.isEmpty) return SleepDay.empty;
  sessions.sort((a, b) => b.sleepMin.compareTo(a.sleepMin));
  return SleepDay(sessions.first, sessions.length > 1 ? sessions[1] : null);
}

/// Минуты ночного сна по дням пробуждения.
Map<DateTime, int> nightMinutesByDay(List<ActivityRecord> sleepRecs) {
  final byDay = <DateTime, List<ActivityRecord>>{};
  for (final r in sleepRecs) {
    if (r.type != 'sleep') continue;
    final d = dayStart(r.startTime.add(const Duration(hours: 6)));
    byDay.putIfAbsent(d, () => []).add(r);
  }
  final out = <DateTime, int>{};
  for (final e in byDay.entries) {
    final ss = sleepSessions(e.value);
    if (ss.isEmpty) continue;
    out[e.key] = ss.map((s) => s.sleepMin).reduce((a, b) => a > b ? a : b);
  }
  return out;
}
