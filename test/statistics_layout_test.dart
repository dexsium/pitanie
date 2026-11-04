import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/statistics/statistics_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final size in const [Size(393, 852), Size(360, 640), Size(430, 932), Size(320, 568)]) {
    for (final brightness in Brightness.values) {
      testWidgets('Статистика без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} $brightness',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        await tester.pumpWidget(ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
              theme: buildTheme(brightness),
              home: const Scaffold(body: StatisticsPage())),
        ));
        for (final label in ['День', 'Месяц', 'Неделя']) {
          await tester.tap(find.text(label));
          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: label);
          await tester.drag(find.byType(ListView), const Offset(0, -4000));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: '$label прокрутка');
          await tester.drag(find.byType(ListView), const Offset(0, 4000));
          await tester.pump(const Duration(milliseconds: 400));
        }
        // стрелки сдвигают период
        await tester.tap(find.byIcon(Icons.chevron_left).first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Сегодня'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
            () => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
      });
    }
  }
}
