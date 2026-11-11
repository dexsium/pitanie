import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/weight/weight_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('изменение веса за период', () {
    final now = DateTime(2026, 11, 4, 12);
    WeightEntry w(int id, DateTime at, double kg) =>
        WeightEntry(id: id, date: '', measuredAt: at, weightKg: kg, source: 'manual');
    final ws = [
      w(1, DateTime(2026, 11, 3, 17, 14), 69.0),
      w(2, DateTime(2026, 11, 4, 9, 13), 69.5),
    ];
    expect(weightChange(ws, const Duration(days: 7), now), closeTo(0.5, 1e-9));
    expect(weightChange([ws.first], const Duration(days: 7), now), isNull);
  });

  for (final scenario in const ['пусто', 'один замер', 'два замера', 'много замеров']) {
    for (final size in const [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)]) {
      for (final range in [0, 1, 2]) {
        testWidgets(
            'Вес без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} '
            '$scenario, период $range', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final db = AppDatabase(NativeDatabase.memory());
          await tester.runAsync(() async {
            final now = DateTime.now();
            final n = switch (scenario) { 'пусто' => 0, 'один замер' => 1, 'два замера' => 2, _ => 60 };
            for (var i = n - 1; i >= 0; i--) {
              await db.addWeight(now.subtract(Duration(days: i, hours: 1)),
                  n == 2 ? 69.0 + (1 - i) * 0.5 : 70 + (i % 7) * 0.3 - i * 0.02);
            }
            if (scenario != 'пусто') {
              await db.saveUser(const UsersCompanion(targetWeightKg: Value(85)));
            }
          });
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(db)],
            child: MaterialApp(theme: buildTheme(Brightness.light), home: const WeightPage()),
          ));
          await tester.pump(const Duration(milliseconds: 400));
          if (range > 0) {
            await tester.tap(find.text(range == 1 ? 'Месяц' : 'Всё'));
          }
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(find.text('Динамика веса'), findsOneWidget);
          expect(find.text('Записи'), findsOneWidget);
          await tester.drag(find.byType(ListView), const Offset(0, -5000));
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
