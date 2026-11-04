import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/day_data.dart' show kBleSource;
import 'package:pitanie/features/health_analysis/presentation/pages/health_analysis_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final withData in [false, true]) {
    for (final size in const [Size(393, 852), Size(360, 640), Size(320, 568)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Анализ здоровья без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '$brightness ${withData ? 'с данными' : 'без данных'}',
            (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          if (withData) {
            await tester.runAsync(() async {
              final now = DateTime.now();
              final recs = <ActivityRecordsCompanion>[];
              for (var d = 20; d >= 0; d--) {
                final base = DateTime(now.year, now.month, now.day - d);
                for (var i = 0; i < 90; i++) {
                  final t = base.add(Duration(minutes: 600 + i));
                  recs.add(ActivityRecordsCompanion.insert(
                      type: 'heartRate',
                      startTime: t,
                      endTime: t.add(const Duration(minutes: 1)),
                      value: 60.0 + (d < 3 ? 17 : 0) + (i % 3),
                      unit: 'bpm',
                      source: kBleSource,
                      externalRecordId: 'hr-$d-$i',
                      tzOffsetMin: Value(now.timeZoneOffset.inMinutes)));
                }
                final t = base.add(const Duration(hours: 12));
                recs.add(ActivityRecordsCompanion.insert(
                    type: 'spo2',
                    startTime: t,
                    endTime: t.add(const Duration(minutes: 1)),
                    value: 96,
                    unit: '%',
                    source: kBleSource,
                    externalRecordId: 'sp-$d'));
              }
              await db.upsertActivity(recs);
            });
          }
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(
                theme: buildTheme(brightness),
                home: const HealthAnalysisPage()),
          ));
          await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 300)));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Восстановление'), findsOneWidget);
          expect(find.textContaining('HRV'),
              findsWidgets); // честно показано, что HRV нет
          await tester.drag(find.byType(ListView), const Offset(0, -6000));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          // настройки
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(
                theme: buildTheme(brightness),
                home: const HealthSettingsPage()),
          ));
          await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(() =>
              db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
        });
      }
    }
  }
}
