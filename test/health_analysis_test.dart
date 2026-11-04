import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/day_data.dart' show kBleSource;
import 'package:pitanie/features/health_analysis/data/health_repository.dart';
import 'package:pitanie/features/health_analysis/domain/algorithms/resting_hr.dart';
import 'package:pitanie/features/health_analysis/domain/models/health_models.dart';
import 'package:pitanie/features/health_analysis/services/health_monitor.dart';
import 'package:pitanie/features/health_analysis/services/health_notification_engine.dart';
import 'package:pitanie/features/health_analysis/services/heart_rate_analysis_service.dart';
import 'package:pitanie/features/health_analysis/services/hrv_analysis_service.dart';
import 'package:pitanie/features/health_analysis/services/recommendation_engine.dart';
import 'package:pitanie/features/health_analysis/services/recovery_analysis_service.dart';
import 'package:pitanie/features/health_analysis/services/sleep_analysis_service.dart';
import 'package:pitanie/features/health_analysis/services/spo2_analysis_service.dart';

final now = DateTime(2026, 11, 4, 12);
DateTime day(int ago) => DateTime(now.year, now.month, now.day - ago);

/// Ряд: старые дни (ago от [n] до 4) — база, три последних (ago 2..0) — [recent].
List<DailyValue> series(double base, int n, List<double> recent,
        {double wiggle = 1}) =>
    [
      for (var i = n; i >= 3; i--)
        DailyValue(day(i), base + (i.isEven ? wiggle : -wiggle)),
      for (var i = 0; i < recent.length; i++)
        DailyValue(day(recent.length - 1 - i), recent[i]),
    ];

List<SleepNight> nights(List<int> minutes) => [
      for (var i = 0; i < minutes.length; i++)
        SleepNight(
            day(minutes.length - 1 - i),
            day(minutes.length - i).add(const Duration(hours: 23)),
            day(minutes.length - 1 - i).add(const Duration(hours: 7)),
            minutes[i]),
    ];

HealthResults results({
  HeartAnalysis? hr,
  HrvAnalysis? hrv,
  SleepAnalysis? sleep,
  Spo2Analysis? spo2,
  RecoveryState? rec,
}) {
  final h = hr ?? analyzeHeartRate(const [], now);
  final v = hrv ?? analyzeHrv(const [], now);
  final s = sleep ?? analyzeSleep(const [], now);
  return HealthResults(
      h,
      v,
      s,
      spo2 ?? analyzeSpo2(const [], now),
      rec ??
          analyzeRecovery(hr: h, hrv: v, sleep: s, heavyLoadYesterday: false));
}

Future<void> addRec(AppDatabase db, String type, DateTime t, double v,
        {String source = kBleSource, String unit = ''}) =>
    db.upsertActivity([
      ActivityRecordsCompanion.insert(
          type: type,
          startTime: t,
          endTime: t.add(const Duration(minutes: 1)),
          value: v,
          unit: unit,
          source: source,
          externalRecordId: '$source-$type-${t.millisecondsSinceEpoch}',
          tzOffsetMin: Value(now.timeZoneOffset.inMinutes))
    ]);

void main() {
  group('пульс', () {
    test('1. нормальный пульс покоя: отклонений нет, личная норма считается',
        () {
      final a = analyzeHeartRate(series(62, 28, [62, 63, 61]), now);
      expect(a.baseline!.median, closeTo(62, 1));
      expect(a.persistentHigh, isFalse);
      expect(buildInsights(results(hr: a), now), isEmpty);
    });

    test('2. тренировка не попадает в пульс покоя', () {
      final hr = <Sample>[];
      final steps = <int>{};
      final d = day(1);
      for (var i = 0; i < 300; i++) {
        final t = d.add(Duration(minutes: 8 * 60 + i));
        final training = i >= 100 && i < 160;
        hr.add(Sample(t, training ? 150.0 : 60 + (i % 5).toDouble()));
        if (training) steps.add(t.millisecondsSinceEpoch ~/ 60000);
      }
      final r = dailyHeart(hr, stepMinutes: steps, sleepMinutes: {}, workouts: [
        (
          d.add(const Duration(hours: 8, minutes: 100)),
          d.add(const Duration(hours: 9, minutes: 40))
        )
      ]);
      expect(r.single.resting, lessThan(65));
      expect(r.single.restingSamples,
          lessThan(300)); // 60 минут тренировки и 30 после — исключены
    });

    test(
        '3. устойчивое повышение (62 → 77, 80, 79) определяется, текст осторожный',
        () {
      final a = analyzeHeartRate(series(62, 28, [77, 80, 79]), now);
      expect(a.persistentHigh, isTrue);
      final i = buildInsights(results(hr: a), now).single;
      expect(i.severity, Severity.attention);
      expect(i.body, contains('обсудите его с врачом'));
      expect(i.body.toLowerCase(), isNot(contains('стресс')));
      expect(i.body.toLowerCase(), isNot(contains('болезн')));
      expect(i.basis, isNotEmpty);
      expect(i.algoVersion, kAlgoVersion);
    });

    test('4. единичное ложное измерение и один высокий день не дают тревоги',
        () {
      final hr = [
        for (var i = 0; i < 200; i++)
          Sample(day(1).add(Duration(minutes: 600 + i)), 60),
        Sample(day(1).add(const Duration(minutes: 900)), 200),
        Sample(day(1).add(const Duration(minutes: 901)), 10), // недостоверное
      ];
      final r = dailyHeart(hr, stepMinutes: {}, sleepMinutes: {});
      expect(r.single.resting, closeTo(60, 1e-9));
      final one = analyzeHeartRate(series(62, 28, [62, 63, 80]), now);
      expect(one.persistentHigh, isFalse);
    });

    test('8. мало истории: личная норма не формируется, вывода нет', () {
      final a = analyzeHeartRate(series(62, 9, [80, 81, 82]), now);
      expect(a.baseline, isNull);
      expect(a.persistentHigh, isFalse);
      expect(buildInsights(results(hr: a), now), isEmpty);
    });

    test('14. пропущенная синхронизация: старые данные не дают вывода', () {
      final old = [
        for (var i = 40; i >= 8; i--)
          DailyValue(day(i), 62.0 + (i.isEven ? 1 : -1)),
        DailyValue(day(7), 85),
        DailyValue(day(6), 86),
        DailyValue(day(5), 87),
      ];
      final a = analyzeHeartRate(old, now);
      expect(a.persistentHigh, isFalse);
    });
  });

  group('HRV', () {
    List<HrvSample> hrv(HrvMetric m, int n, double base, List<double> last) => [
          for (var i = n; i >= 3; i--)
            HrvSample(day(i), base + (i.isEven ? 2 : -2), m),
          for (var i = 0; i < last.length; i++)
            HrvSample(day(last.length - 1 - i), last[i], m),
        ];

    test('5. HRV ниже личного диапазона', () {
      final a = analyzeHrv(hrv(HrvMetric.rmssd, 24, 60, [38, 40, 39]), now);
      expect(a.lowStreak, isTrue);
      final i = buildInsights(results(hrv: a), now).single;
      expect(i.category, HealthCategory.hrv);
      expect(i.body, contains('Это не диагноз'));
    });

    test('6. нет HRV: анализ работает без неё', () {
      final a = analyzeHrv(const [], now);
      expect(a.available, isFalse);
      final hr = analyzeHeartRate(series(62, 28, [62, 62, 62]), now);
      final rec = analyzeRecovery(
          hr: hr,
          hrv: a,
          sleep: analyzeSleep(nights(List.filled(5, 450)), now),
          heavyLoadYesterday: false);
      expect(rec.level, RecoveryLevel.normal);
      expect(rec.hrvUsed, isFalse);
    });

    test('7. RMSSD и SDNN не смешиваются', () {
      final mixed = [
        ...hrv(HrvMetric.rmssd, 26, 50, [50, 51, 49]),
        ...hrv(HrvMetric.sdnn, 20, 100, [100, 99, 101]),
      ];
      final a = analyzeHrv(mixed, now);
      expect(a.metric, HrvMetric.rmssd);
      expect(a.mixedMetrics, isTrue);
      expect(a.lowStreak, isFalse);
      expect(a.baseline!.median, closeTo(50, 3)); // SDNN не повлиял на базу
    });

    test('неизвестный тип анализируется только по собственной базе', () {
      final a = analyzeHrv(hrv(HrvMetric.unknown, 24, 60, [60, 61, 59]), now);
      expect(a.metric, HrvMetric.unknown);
      expect(hrvMetricLabel(a.metric!), 'тип не указан');
      expect(a.lowStreak, isFalse);
    });

    test('мало ночей: личный диапазон не формируется', () {
      final a = analyzeHrv(hrv(HrvMetric.rmssd, 8, 60, [30, 31, 30]), now);
      expect(a.baseline, isNull);
      expect(a.lowStreak, isFalse);
    });
  });

  group('сон', () {
    test('9. один короткий ночной сон — только наблюдение, без уведомления',
        () {
      final a = analyzeSleep(nights([450, 440, 300]), now);
      expect(a.lastNightShort, isTrue);
      expect(a.shortStreak, isFalse);
      expect(buildInsights(results(sleep: a), now), isEmpty);
    });

    test('10. несколько ночей недостаточного сна', () {
      final a = analyzeSleep(nights([450, 330, 320, 300]), now);
      expect(a.shortStreak, isTrue);
      final i = buildInsights(results(sleep: a), now).single;
      expect(i.category, HealthCategory.sleep);
      expect(i.severity, Severity.advice);
    });

    test('пользовательский порог сна', () {
      final a = analyzeSleep(nights([400, 400, 400]), now, minHours: 7);
      expect(a.shortStreak, isTrue);
    });
  });

  group('SpO₂', () {
    Sample s(int hoursAgo, double v) =>
        Sample(now.subtract(Duration(hours: hoursAgo)), v);

    test('11. повторные низкие значения и недостоверные отбрасываются', () {
      final a = analyzeSpo2([s(1, 90), s(5, 89), s(9, 91), s(2, 40)], now);
      expect(a.level, Spo2Level.repeatedLow);
      expect(a.rejected, 1);
      final i = buildInsights(results(spo2: a), now).single;
      expect(i.body, contains('медицинским прибором'));
      expect(i.body, contains('скорую'));
    });

    test('одно низкое измерение — только повторить, не вывод', () {
      final a = analyzeSpo2([s(1, 90), s(30, 97)], now);
      expect(a.level, Spo2Level.repeatMeasure);
      final i = buildInsights(results(spo2: a), now).single;
      expect(i.severity, Severity.info);
      expect(i.body, contains('ничего не доказывает'));
    });

    test('частые значения в пределах часа считаются одним', () {
      final a = analyzeSpo2([
        s(1, 90),
        Sample(now.subtract(const Duration(minutes: 70)), 90),
        Sample(now.subtract(const Duration(minutes: 75)), 90)
      ], now);
      expect(a.level, isNot(Spo2Level.repeatedLow));
    });

    test('повторные очень низкие — срочная осторожная рекомендация', () {
      final a = analyzeSpo2([s(1, 86), s(4, 85), s(8, 87)], now);
      expect(a.level, Spo2Level.repeatedVeryLow);
      expect(buildInsights(results(spo2: a), now).single.severity,
          Severity.urgent);
    });
  });

  group('восстановление', () {
    test(
        'два признака → более лёгкая тренировка, три → внимание к восстановлению',
        () {
      final hr = analyzeHeartRate(series(62, 28, [77, 80, 79]), now);
      final sl = analyzeSleep(nights([450, 330, 320, 300]), now);
      final two = analyzeRecovery(
          hr: hr,
          hrv: analyzeHrv(const [], now),
          sleep: sl,
          heavyLoadYesterday: false);
      expect(two.level, RecoveryLevel.lighter);
      final three = analyzeRecovery(
          hr: hr,
          hrv: analyzeHrv(const [], now),
          sleep: sl,
          heavyLoadYesterday: true);
      expect(three.level, RecoveryLevel.focus);
      final one = analyzeRecovery(
          hr: analyzeHeartRate(series(62, 28, [62, 62, 62]), now),
          hrv: analyzeHrv(const [], now),
          sleep: sl,
          heavyLoadYesterday: false);
      expect(one.level, RecoveryLevel.normal); // один показатель вывода не даёт
    });

    test('плохое самочувствие — рекомендация отдыха с оговоркой о враче', () {
      final r = analyzeRecovery(
          hr: analyzeHeartRate(const [], now),
          hrv: analyzeHrv(const [], now),
          sleep: analyzeSleep(const [], now),
          heavyLoadYesterday: false,
          feeling: 3);
      expect(r.level, RecoveryLevel.focus);
      expect(r.recommendation, contains('врачу'));
    });

    test('нет данных → «недостаточно данных», а не выдуманная оценка', () {
      expect(results().recovery.level, RecoveryLevel.insufficient);
    });
  });

  group('уведомления', () {
    final high = analyzeHeartRate(series(62, 28, [77, 80, 79]), now);
    final insights = buildInsights(results(hr: high), now);

    test('17. отключённая категория и выключенный анализ — без уведомлений',
        () {
      final off = HealthPrefs(
          categories: {for (final c in HealthCategory.values) c: false});
      expect(selectForDelivery(insights, const [], off, now), isEmpty);
      expect(
          selectForDelivery(
              insights, const [], const HealthPrefs(auto: false), now),
          isEmpty);
      expect(selectForDelivery(insights, const [], const HealthPrefs(), now),
          hasLength(1));
    });

    test('18. повторное событие не отправляется повторно', () {
      final sent = [NotifyEntry(insights.single, now)];
      expect(
          selectForDelivery(insights, sent, const HealthPrefs(),
              now.add(const Duration(hours: 3))),
          isEmpty);
    });

    test('тихие часы откладывают обычные, но не срочные', () {
      final night = DateTime(2026, 11, 4, 23, 30);
      expect(selectForDelivery(insights, const [], const HealthPrefs(), night),
          isEmpty);
      final urgent = buildInsights(
          results(
              spo2: analyzeSpo2([
            Sample(night.subtract(const Duration(hours: 1)), 86),
            Sample(night.subtract(const Duration(hours: 4)), 85),
            Sample(night.subtract(const Duration(hours: 8)), 87),
          ], night)),
          night);
      expect(selectForDelivery(urgent, const [], const HealthPrefs(), night),
          hasLength(1));
    });

    test('информационные — не чаще заданного интервала', () {
      final info = Insight(
          key: 'i1',
          category: HealthCategory.heartRate,
          severity: Severity.info,
          title: 't',
          body: 'b',
          basis: const [],
          period: '',
          confidence: '',
          createdAt: now);
      final info2 = Insight(
          key: 'i2',
          category: HealthCategory.sleep,
          severity: Severity.info,
          title: 't',
          body: 'b',
          basis: const [],
          period: '',
          confidence: '',
          createdAt: now);
      final h = [NotifyEntry(info, now.subtract(const Duration(days: 2)))];
      expect(
          selectForDelivery(
              [info2], h, const HealthPrefs(infoEveryDays: 7), now),
          isEmpty);
      expect(
          selectForDelivery(
              [info2], h, const HealthPrefs(infoEveryDays: 1), now),
          hasLength(1));
    });

    test('режим приватности скрывает подробности', () {
      final t = notificationText(insights.single, privacy: true);
      expect(t.body, isNot(contains('уд/мин')));
    });

    test('история сохраняется и читается без потерь', () {
      final h = parseNotifyHistory(
          encodeNotifyHistory([NotifyEntry(insights.single, now)]));
      expect(h.single.insight.key, insights.single.key);
      expect(h.single.insight.basis, insights.single.basis);
    });
  });

  group('с базой данных', () {
    test(
        '12–13. нет часов и интернета: страница строится, выводов нет, всё локально',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final snap = await loadHealth(db, now);
      expect(snap.insights, isEmpty);
      expect(snap.lastHr, isNull);
      final byId = {for (final c in snap.capabilities) c.id: c};
      expect(byId['hr']!.state, Availability.awaitingSync);
      expect(byId['hrv']!.state, Availability.unsupported);
      expect(byId['ecg']!.state, Availability.unsupported);
      expect(snap.results.recovery.level, RecoveryLevel.insufficient);
      await db.close();
    });

    test('15. дубли HealthKit и BLE: берутся данные часов, без удвоения',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      for (var i = 0; i < 120; i++) {
        final t = day(1).add(Duration(minutes: 600 + i));
        await addRec(db, 'heartRate', t, 60, unit: 'bpm');
        await addRec(db, 'heartRate', t, 61, source: 'health_kit', unit: 'bpm');
      }
      final snap = await loadHealth(db, now);
      expect(snap.days.single.restingSamples, 120);
      await db.close();
    });

    test(
        '18б. монитор: повторный запуск на тех же данных не шлёт то же уведомление',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      for (final h in [1, 5, 9]) {
        await addRec(db, 'spo2', now.subtract(Duration(hours: h)), 90,
            unit: '%');
      }
      final shown = <String>[];
      Future<void> show(int id, String t, String b, bool u) async =>
          shown.add(t);
      expect(await runHealthMonitor(db, show, now: now), 1);
      expect(
          await runHealthMonitor(db, show,
              now: now.add(const Duration(hours: 2))),
          0);
      expect(shown, hasLength(1));
      final snap = await loadHealth(db, now);
      expect(snap.history.single.insight.category, HealthCategory.spo2);
      await db.close();
    });

    test('автоанализ выключен — монитор молчит', () async {
      final db = AppDatabase(NativeDatabase.memory());
      for (final h in [1, 5, 9]) {
        await addRec(db, 'spo2', now.subtract(Duration(hours: h)), 90,
            unit: '%');
      }
      await db.setSetting(kHmAuto, '0');
      expect(await runHealthMonitor(db, (a, b, c, d) async {}, now: now), 0);
      await db.close();
    });

    test('устаревшие данные помечаются как требующие синхронизации', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await addRec(db, 'heartRate', now.subtract(const Duration(days: 6)), 70,
          unit: 'bpm');
      final snap = await loadHealth(db, now);
      expect({for (final c in snap.capabilities) c.id: c}['hr']!.state,
          Availability.stale);
      await db.close();
    });
  });
}
