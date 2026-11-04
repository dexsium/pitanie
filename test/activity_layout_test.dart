import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/activity/activity_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  for (final withData in [false, true]) {
    for (final size in const [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Активность без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '$brightness ${withData ? 'с данными' : 'без данных'}', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          if (withData) {
            await tester.runAsync(() async {
              final now = DateTime.now();
              final recs = <ActivityRecordsCompanion>[];
              for (var d = 0; d < 7; d++) {
                final t = DateTime(now.year, now.month, now.day - d, 12);
                recs.add(ActivityRecordsCompanion.insert(
                    type: 'steps',
                    startTime: t,
                    endTime: t.add(const Duration(minutes: 1)),
                    value: 1500.0 + d * 1700,
                    unit: 'count',
                    source: 'amazfit_ble',
                    externalRecordId: 'steps-$d',
                    tzOffsetMin: Value(now.timeZoneOffset.inMinutes)));
                recs.add(ActivityRecordsCompanion.insert(
                    type: 'heartRate',
                    startTime: t,
                    endTime: t.add(const Duration(minutes: 1)),
                    value: 70.0 + d,
                    unit: 'bpm',
                    source: 'amazfit_ble',
                    externalRecordId: 'hr-$d',
                    tzOffsetMin: Value(now.timeZoneOffset.inMinutes)));
              }
              await db.upsertActivity(recs);
            });
          }
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(
                theme: buildTheme(brightness), home: const Scaffold(body: ActivityPage())),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Шаги за 7 дней'), findsOneWidget);
          expect(find.text('График пульса'), findsOneWidget);
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
