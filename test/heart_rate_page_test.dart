import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/wearables/heart_rate_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final withData in [false, true]) {
    for (final size in const [Size(393, 852), Size(360, 640), Size(430, 932), Size(320, 568)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Пульс без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '$brightness ${withData ? 'с данными' : 'без данных'}', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          if (withData) {
            await tester.runAsync(() async {
              final now = DateTime.now();
              final y = DateTime(now.year, now.month, now.day - 1);
              final recs = <ActivityRecordsCompanion>[];
              for (var i = 0; i < 400; i++) {
                final t = y.add(Duration(minutes: 5 + i * 3));
                recs.add(ActivityRecordsCompanion.insert(
                    type: 'heartRate',
                    startTime: t,
                    endTime: t.add(const Duration(minutes: 1)),
                    value: 55.0 + (i % 40) + (i > 200 ? 20 : 0),
                    unit: 'bpm',
                    source: 'amazfit_ble',
                    externalRecordId: 'hr-$i',
                    tzOffsetMin: Value(now.timeZoneOffset.inMinutes)));
              }
              await db.upsertActivity(recs);
            });
          }
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(theme: buildTheme(brightness), home: const HeartRatePage()),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Частота сердечных сокращений'), findsOneWidget);
          expect(find.text('Сегодня'), findsOneWidget);
          expect(find.text('Мин.'), findsOneWidget);
          expect(find.text('Макс.'), findsOneWidget);

          if (withData) {
            // сегодня данных нет, переходим на вчера
            await tester.tap(find.byIcon(Icons.chevron_left).last);
            await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            expect(find.text('Сегодня'), findsNothing);
            expect(find.textContaining('Точек: '), findsOneWidget);
            expect(find.textContaining('Источник: Умные часы'), findsOneWidget);
          }
          await tester.drag(find.byType(ListView), const Offset(0, -3000));
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
