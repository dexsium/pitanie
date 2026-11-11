import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/health_integration/devices_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final size in const [Size(393, 852), Size(320, 640)]) {
    for (final connected in [false, true]) {
      testWidgets('Источники здоровья без ошибок вёрстки ${size.width.toInt()}, '
          'подключено: $connected', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        if (connected) {
          await db.saveSource(
              'health_connect',
              ConnectedSourcesCompanion.insert(sourceType: 'health_connect'));
          await db.saveSource(
              'apple_health', ConnectedSourcesCompanion.insert(sourceType: 'apple_health'));
        }
        await tester.pumpWidget(ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const DevicesPage()),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Источники здоровья'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -3000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('напрямую по Bluetooth'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
            () => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
      });
    }
  }
}
