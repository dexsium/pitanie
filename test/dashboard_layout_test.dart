import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/dashboard_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final status in const ['off']) {
    for (final size in const [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Главная без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '$brightness, источник: $status', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          await tester.pumpWidget(ProviderScope(
            overrides: [
              dbProvider.overrideWithValue(db),
            ],
            child: MaterialApp(
                theme: buildTheme(brightness), home: const Scaffold(body: DashboardPage())),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Приёмы пищи'), findsOneWidget);
          await tester.drag(find.byType(ListView), const Offset(0, -4000));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Вода'), findsOneWidget);
          expect(find.text('Активность'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(
              () => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
        });
      }
    }
  }

  testWidgets('Карточка источника: название и подсказка подключения', (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(body: HealthStatusChip())),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Не подключено'), findsOneWidget);
    expect(find.text('Нажмите, чтобы подключить'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
  });
}
