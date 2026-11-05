import '../../../core/dates.dart';
import '../../../database/database.dart';
import '../../dashboard/day_data.dart' show kBleSource, mainSourceOf;
import '../../sleep/sleep_data.dart';
import '../domain/algorithms/baseline.dart';
import '../domain/algorithms/resting_hr.dart';
import '../domain/models/health_models.dart';
import '../services/health_data_quality_service.dart';
import '../services/health_notification_engine.dart';
import '../services/heart_rate_analysis_service.dart';
import '../services/hrv_analysis_service.dart';
import '../services/recommendation_engine.dart';
import '../services/recovery_analysis_service.dart';
import '../services/sleep_analysis_service.dart';
import '../services/spo2_analysis_service.dart';

const kHmAuto = 'hm_auto';
const kHmInfoDays = 'hm_info_days';
const kHmQuiet = 'hm_quiet';
const kHmPrivacy = 'hm_privacy';
const kHmHrDelta = 'hm_hr_delta';
const kHmSleepH = 'hm_sleep_h';
const kHmFeel = 'hm_feel';
const kHmHist = 'hm_hist';
const kHmNotes = 'hm_notes';
String hmCatKey(HealthCategory c) => 'hm_cat_${c.name}';

int _hm(String s, int d) {
  final p = s.split(':');
  if (p.length != 2) return d;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  return h == null || m == null ? d : h * 60 + m;
}

String fmtHm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

HealthPrefs parsePrefs(Map<String, String> s) {
  final q = (s[kHmQuiet] ?? '22:00|08:00').split('|');
  return HealthPrefs(
    auto: s[kHmAuto] != '0',
    categories: {
      for (final c in HealthCategory.values) c: s[hmCatKey(c)] != '0'
    },
    infoEveryDays: int.tryParse(s[kHmInfoDays] ?? '') == 1 ? 1 : 7,
    quietFromMin: _hm(q.first, 22 * 60),
    quietToMin: q.length > 1 ? _hm(q[1], 8 * 60) : 8 * 60,
    privacy: s[kHmPrivacy] == '1',
    hrMinDelta:
        (double.tryParse(s[kHmHrDelta] ?? '') ?? 5).clamp(3, 15).toDouble(),
    sleepMinHours:
        (double.tryParse(s[kHmSleepH] ?? '') ?? 6).clamp(4, 9).toDouble(),
  );
}

/// Самочувствие на сегодня (1 хорошо, 2 обычно, 3 плохо) или null.
int? feelingFor(Map<String, String> s, DateTime now) {
  final p = (s[kHmFeel] ?? '').split('|');
  if (p.length != 2 || p[0] != dayKey(now)) return null;
  return int.tryParse(p[1]);
}

class HealthSnapshot {
  final DateTime now;
  final HealthPrefs prefs;
  final List<Capability> capabilities;
  final List<DayHeart> days;
  final List<DailyValue> hrvDaily;
  final List<Sample> spo2;
  final List<DailyValue> stepsDaily;
  final HealthResults results;
  final List<Insight> insights;
  final List<NotifyEntry> history;
  final Sample? lastHr;
  final DateTime? lastData;
  final int? feeling;
  final SleepDay sleepToday;
  final Sample? stressLast, respLast;
  final bool restingFromWatch;
  const HealthSnapshot({
    required this.now,
    required this.prefs,
    required this.capabilities,
    required this.days,
    required this.hrvDaily,
    required this.spo2,
    required this.stepsDaily,
    required this.results,
    required this.insights,
    required this.history,
    required this.lastHr,
    required this.lastData,
    required this.feeling,
    required this.sleepToday,
    required this.stressLast,
    required this.respLast,
    required this.restingFromWatch,
  });
}

HrvMetric _hrvMetric(String type) => switch (type) {
      'hrvRmssd' => HrvMetric.rmssd,
      'hrvSdnn' => HrvMetric.sdnn,
      _ => HrvMetric.unknown,
    };

/// Предпочитаются данные часов по Bluetooth; другие источники берутся для типа только если
/// от часов нет ни одной записи (без суммирования и дублей).
List<ActivityRecord> _preferred(
    List<ActivityRecord> all, String? main, bool Function(String) typeMatch) {
  final of = all.where((r) => typeMatch(r.type)).toList();
  if (main == null) return of;
  final chosen = of.where((r) => r.source == main).toList();
  return chosen.isNotEmpty ? chosen : of;
}

Future<HealthSnapshot> loadHealth(AppDatabase db, DateTime now) async {
  final settings = await db.allSettings();
  final prefs = parsePrefs(settings);
  final main = mainSourceOf(settings);
  final today = dayStart(now);
  final from = today.subtract(const Duration(days: 35));
  final recs =
      await db.activityBetween(from, now.add(const Duration(minutes: 1)));
  final wk = await db.workoutsBetween(from, now);

  final hrRecs = _preferred(recs, main, (t) => t == 'heartRate');
  final stepRecs = _preferred(recs, main, (t) => t == 'steps');
  final sleepRecs = _preferred(recs, main, (t) => t.startsWith('sleep'));
  final spoRecs = _preferred(recs, main, (t) => t == 'spo2');
  final hrvRecs = recs.where((r) => r.type.startsWith('hrv')).toList();

  int minute(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;
  final stepMin = {
    for (final r in stepRecs)
      if (r.value > 0) minute(r.startTime)
  };
  final sleepMin = {
    for (final r in sleepRecs)
      if (r.type == 'sleep') minute(r.startTime)
  };
  final hrSamples = [for (final r in hrRecs) Sample(r.startTime, r.value)];
  final days = dailyHeart(hrSamples,
      stepMinutes: stepMin,
      sleepMinutes: sleepMin,
      workouts: [for (final w in wk) (w.startTime, w.endTime)]);
  // Пульс покоя: значение от часов (тип 0x3a), если оно есть за день; иначе расчёт по минутам.
  final watchRest = <DateTime, double>{};
  for (final r in _preferred(recs, main, (t) => t == 'restingHeartRate')) {
    if (validHeartRate(r.value)) watchRest[dayOf(r.startTime)] = r.value;
  }
  final restingMap = <DateTime, double>{
    for (final d in days)
      if (d.resting != null) d.day: d.resting!,
    ...watchRest,
  };
  final resting = [
    for (final e
        in restingMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      DailyValue(e.key, e.value)
  ];
  Sample? latestOf(String type) {
    final l = _preferred(recs, main, (t) => t == type);
    if (l.isEmpty) return null;
    final r = l.reduce((a, b) => a.startTime.isAfter(b.startTime) ? a : b);
    return Sample(r.startTime, r.value);
  }

  final nightHr = {for (final d in days) d.day: d.night};
  final nights = <SleepNight>[];
  for (var i = 0; i < 28; i++) {
    final d = today.subtract(Duration(days: i));
    final sd = analyzeSleepDay(sleepRecs, d);
    final n = sd.night;
    if (n != null) {
      nights
          .add(SleepNight(d, n.start, n.end, n.sleepMin, nightHr: nightHr[d]));
    }
  }

  final spo2 = [for (final r in spoRecs) Sample(r.startTime, r.value)];
  final hrv = [
    for (final r in hrvRecs) HrvSample(r.startTime, r.value, _hrvMetric(r.type))
  ];

  // Суточные шаги и признак повышенной нагрузки вчера.
  final stepsByDay = <DateTime, double>{};
  for (final r in stepRecs) {
    stepsByDay.update(dayOf(r.startTime), (v) => v + r.value,
        ifAbsent: () => r.value);
  }
  final stepsDaily = [
    for (final e
        in stepsByDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      DailyValue(e.key, e.value)
  ];
  final yesterday = today.subtract(const Duration(days: 1));
  final ySteps = stepsByDay[yesterday] ?? 0;
  final medSteps = stepsByDay.length >= 7
      ? medianOf([
          for (final e in stepsByDay.entries)
            if (e.key.isBefore(yesterday)) e.value
        ])
      : double.nan;
  final yWorkout = wk
      .where((w) => dayOf(w.startTime) == yesterday)
      .fold<int>(0, (s, w) => s + w.endTime.difference(w.startTime).inMinutes);
  final heavy = yWorkout >= 90 ||
      (ySteps >= 8000 &&
          !medSteps.isNaN &&
          medSteps > 0 &&
          ySteps > 1.5 * medSteps);

  final hrA = analyzeHeartRate(resting, now, minDelta: prefs.hrMinDelta);
  final hrvA = analyzeHrv(hrv, now);
  final sleepA = analyzeSleep(nights, now, minHours: prefs.sleepMinHours);
  final spoA = analyzeSpo2(spo2, now);
  final feeling = feelingFor(settings, now);
  final rec = analyzeRecovery(
      hr: hrA,
      hrv: hrvA,
      sleep: sleepA,
      heavyLoadYesterday: heavy,
      feeling: feeling);
  final results = HealthResults(hrA, hrvA, sleepA, spoA, rec);

  DateTime? lastOf(bool Function(ActivityRecord) f) {
    DateTime? m;
    for (final r in recs) {
      if (f(r) && (m == null || r.endTime.isAfter(m))) m = r.endTime;
    }
    return m;
  }

  final lastHrRec = hrRecs.isEmpty
      ? null
      : hrRecs.reduce((a, b) => a.startTime.isAfter(b.startTime) ? a : b);
  final caps = _capabilities(
      now,
      {
        'hr': lastOf((r) => r.type == 'heartRate'),
        'spo2': lastOf((r) => r.type == 'spo2'),
        'sleep': lastOf((r) => r.type.startsWith('sleep')),
        'steps': lastOf((r) => r.type == 'steps'),
        'hrv': lastOf((r) => r.type.startsWith('hrv')),
        'resp': lastOf((r) => r.type == 'respiration'),
        'rest': lastOf((r) => r.type == 'restingHeartRate'),
        'stress': lastOf((r) => r.type == 'stress'),
        'energy': lastOf((r) => r.type == 'activeEnergy'),
        'workouts': wk.isEmpty
            ? null
            : wk.map((w) => w.endTime).reduce((a, b) => a.isAfter(b) ? a : b),
      },
      restingDays: resting.length,
      restingFromWatch: watchRest.isNotEmpty);

  return HealthSnapshot(
    now: now,
    prefs: prefs,
    capabilities: caps,
    days: days,
    hrvDaily: [
      for (final s in hrv) DailyValue(dayOf(s.at), s.v),
    ],
    spo2: spo2,
    stepsDaily: stepsDaily,
    results: results,
    insights: buildInsights(results, now),
    history: parseNotifyHistory(settings[kHmHist]),
    lastHr:
        lastHrRec == null ? null : Sample(lastHrRec.startTime, lastHrRec.value),
    lastData: lastOf((r) => main == null || r.source == main),
    feeling: feeling,
    sleepToday: analyzeSleepDay(sleepRecs, today),
    stressLast: latestOf('stress'),
    respLast: latestOf('respiration'),
    restingFromWatch: watchRest.isNotEmpty,
  );
}

List<Capability> _capabilities(DateTime now, Map<String, DateTime?> last,
    {required int restingDays, required bool restingFromWatch}) {
  Capability cap(String id, String label,
      {required bool channel, required String gone}) {
    final t = last[id];
    if (t == null) {
      return channel
          ? Capability(id, label, Availability.awaitingSync,
              'Данных пока нет: ожидается синхронизация часов.')
          : Capability(id, label, Availability.unsupported, gone);
    }
    final fresh = now.difference(t).inHours <= 72;
    return Capability(
        id,
        label,
        fresh ? Availability.available : Availability.stale,
        fresh
            ? 'Данные получены.'
            : 'Данные устарели: синхронизация давно не выполнялась.',
        last: t);
  }

  return [
    cap('hr', 'Пульс', channel: true, gone: ''),
    restingFromWatch
        ? Capability('rest', 'Пульс в покое', Availability.available,
            'Значение приходит с часов${last['rest'] == null ? '' : ''}. Если за день его нет, используется расчёт по минутному пульсу.',
            last: last['rest'])
        : Capability(
            'rest',
            'Пульс в покое',
            restingDays > 0
                ? Availability.available
                : Availability.awaitingSync,
            restingDays > 0
                ? 'Рассчитывается приложением по минутным значениям пульса ($restingDays дн.): значения от часов пока не получены.'
                : 'Пока недостаточно данных; ожидается синхронизация часов.'),
    cap('hrv', 'HRV',
        channel: false,
        gone:
            'Через используемый канал Bluetooth не передаётся (в истории часов не найдена). Анализ идёт без неё.'),
    cap('spo2', 'SpO₂', channel: true, gone: ''),
    cap('sleep', 'Сон и его стадии', channel: true, gone: ''),
    cap('steps', 'Шаги', channel: true, gone: ''),
    cap('workouts', 'Тренировки',
        channel: false,
        gone:
            'Через используемый канал не передаются; доступны только из подключённых систем здоровья.'),
    cap('energy', 'Активные калории',
        channel: false, gone: 'Часы по этому каналу не передают.'),
    cap('resp', 'Частота дыхания',
        channel: false, gone: 'Через используемый канал не передаётся.'),
    cap('stress', 'Оценка стресса Zepp',
        channel: false,
        gone:
            'Через используемый канал не передаётся (данные хранятся в облаке Zepp).'),
    const Capability('ecg', 'ЭКГ', Availability.unsupported,
        'Не поддерживается: приложение ЭКГ не читает.'),
  ];
}
