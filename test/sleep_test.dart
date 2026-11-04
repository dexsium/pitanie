import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/sleep/sleep_data.dart';
import 'package:pitanie/features/sleep/sleep_page.dart';

/// Минутные записи сна: [from, to) с паузами и фазами. Данные синтетические, собраны по формату
/// записей приложения (type sleep + type фазы на каждую минуту).
List<ActivityRecordsCompanion> night(DateTime from, DateTime to,
    {List<(int, int)> gaps = const [], String idp = 'n'}) {
  final out = <ActivityRecordsCompanion>[];
  var i = 0;
  for (var t = from; t.isBefore(to); t = t.add(const Duration(minutes: 1)), i++) {
    if (gaps.any((g) => i >= g.$1 && i < g.$2)) continue;
    final stage = switch ((i ~/ 40) % 3) { 0 => 'sleepDeep', 1 => 'sleepRem', _ => 'sleepLight' };
    for (final type in ['sleep', stage]) {
      out.add(ActivityRecordsCompanion.insert(
          type: type,
          startTime: t,
          endTime: t.add(const Duration(minutes: 1)),
          value: 1,
          unit: 'min',
          source: 'amazfit_ble',
          externalRecordId: 'ble-$type-$idp-${t.millisecondsSinceEpoch ~/ 60000}'));
    }
  }
  return out;
}

Future<List<ActivityRecord>> rows(AppDatabase db) => db.select(db.activityRecords).get();

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('расчёт сна', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('ночь 00:03–08:48 с двумя паузами: сон, постель, эффективность, пробуждения', () async {
      final day = DateTime(2026, 11, 4);
      final from = DateTime(2026, 11, 4, 0, 3), to = DateTime(2026, 11, 4, 8, 48);
      // две паузы по 5 и 6 минут внутри ночи
      await db.upsertActivity(night(from, to, gaps: [(100, 105), (300, 306)]));
      final d = analyzeSleepDay(await rows(db), day);
      final n = d.night!;
      expect(n.inBedMin, 525); // 8 ч 45 м
      expect(n.sleepMin, 525 - 11); // 8 ч 34 м
      expect(n.awakeMin, 11);
      expect(n.wakeups, 2);
      expect(n.efficiency, closeTo(514 / 525, 1e-9));
      expect(n.deepMin + n.remMin + n.lightMin, n.sleepMin);
      expect(n.start, from);
      expect(n.end, to);
      expect(d.nap, isNull);
      // сегменты покрывают весь промежуток без разрывов
      expect(n.segments.first.start, from);
      expect(n.segments.last.end, to);
      for (var i = 1; i < n.segments.length; i++) {
        expect(n.segments[i].start, n.segments[i - 1].end);
      }
    });

    test('дневной сон выделяется отдельно, короткие эпизоды игнорируются', () async {
      final day = DateTime(2026, 11, 4);
      await db.upsertActivity([
        ...night(DateTime(2026, 11, 4, 0, 3), DateTime(2026, 11, 4, 8, 48), idp: 'a'),
        ...night(DateTime(2026, 11, 4, 13, 20), DateTime(2026, 11, 4, 14, 15), idp: 'b'),
        ...night(DateTime(2026, 11, 4, 16, 0), DateTime(2026, 11, 4, 16, 10), idp: 'c'), // 10 минут
      ]);
      final d = analyzeSleepDay(await rows(db), day);
      expect(d.night!.sleepMin, 525);
      expect(d.nap!.sleepMin, 55);
      expect(d.nap!.start, DateTime(2026, 11, 4, 13, 20));
    });

    test('сон до полуночи относится ко дню пробуждения (окно 18:00 → 18:00)', () async {
      await db.upsertActivity(
          night(DateTime(2026, 11, 3, 23, 0), DateTime(2026, 11, 4, 7, 0)));
      final all = await rows(db);
      expect(analyzeSleepDay(all, DateTime(2026, 11, 4)).night!.sleepMin, 480);
      expect(analyzeSleepDay(all, DateTime(2026, 11, 3)).night, isNull);
    });

    test('нет данных — пустой результат', () {
      expect(analyzeSleepDay(const [], DateTime(2026, 11, 4)).night, isNull);
    });

    test('ночи по дням пробуждения для динамики', () async {
      await db.upsertActivity([
        ...night(DateTime(2026, 11, 3, 23, 30), DateTime(2026, 11, 4, 6, 30), idp: 'x'),
        ...night(DateTime(2026, 11, 4, 23, 0), DateTime(2026, 11, 5, 7, 0), idp: 'y'),
      ]);
      final m = nightMinutesByDay(await rows(db));
      expect(m[DateTime(2026, 11, 4)], 420);
      expect(m[DateTime(2026, 11, 5)], 480);
    });
  });

  for (final withData in [false, true]) {
    for (final size in const [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)]) {
      for (final range in [0, 1, 2]) {
        testWidgets(
            'Страница сна без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '${withData ? 'с данными' : 'без данных'}, период $range', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          final today = DateTime.now();
          final day = DateTime(today.year, today.month, today.day);
          if (withData) {
            await tester.runAsync(() async {
              final recs = <ActivityRecordsCompanion>[];
              for (var d = 0; d < 20; d++) {
                final wake = day.subtract(Duration(days: d));
                recs.addAll(night(wake.add(Duration(minutes: 3 + d)),
                    wake.add(Duration(hours: 7, minutes: 30 + d * 3)),
                    gaps: [(60, 66)], idp: 'd$d'));
              }
              recs.addAll(night(day.add(const Duration(hours: 13, minutes: 20)),
                  day.add(const Duration(hours: 14, minutes: 15)), idp: 'nap'));
              await db.upsertActivity(recs);
            });
          }
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(
                theme: buildTheme(Brightness.light), home: SleepPage(day: day)),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          if (range > 0) {
            await tester.tap(find.text(range == 1 ? '30 дней' : 'Год'));
          }
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Фазы сна'), findsOneWidget);
          expect(find.text('Динамика сна'), findsOneWidget);
          if (withData) expect(find.text('Бодрствование'), findsOneWidget);
          await tester.drag(find.byType(ListView), const Offset(0, -4000));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(
              () => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
        });
      }
    }
  }
}
