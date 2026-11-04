import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/dashboard_page.dart';
import 'package:pitanie/features/wearables/wearable_controller.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final status in WearStatus.values) {
    for (final size in const [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            'Главная без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '$brightness, часы: ${status.name}', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          final watch = WearableController(db)
            ..status = status
            ..battery = 77
            ..hr = status == WearStatus.ready ? 69 : null;
          await tester.pumpWidget(ProviderScope(
            overrides: [
              dbProvider.overrideWithValue(db),
              wearableProvider.overrideWith((ref) => watch),
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

  testWidgets('Карточка часов: название, заряд, статус, пульс и время обновления', (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final watch = WearableController(db)
      ..status = WearStatus.ready
      ..battery = 76
      ..hr = 78
      ..lastRead = DateTime(2026, 11, 4, 14, 36);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(db),
        wearableProvider.overrideWith((ref) => watch),
      ],
      child: MaterialApp(
          theme: buildTheme(Brightness.light), home: const Scaffold(body: WatchStatusChip())),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Amazfit GTR 4'), findsOneWidget);
    expect(find.text('76%'), findsOneWidget);
    expect(find.text('Подключены'), findsOneWidget);
    expect(find.textContaining('78'), findsOneWidget);
    expect(find.text('Обновлено: 14:36'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
  });
}
