import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/profile/profile_page.dart';

void main() {
  for (final size in const [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)]) {
    for (final brightness in Brightness.values) {
      testWidgets('Профиль строится без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} $brightness',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        await tester.runAsync(() async {
          await db.saveUser(UsersCompanion(
              sex: const Value('male'),
              birthDate: Value(DateTime(1990, 5, 1)),
              heightCm: const Value(175),
              goalType: const Value('gain')));
          await db.addWeight(DateTime.now(), 69.5);
        });
        await tester.pumpWidget(ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
              theme: buildTheme(brightness), home: const Scaffold(body: ProfilePage())),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Суточные нормы'), findsOneWidget);
        expect(find.text('Умные весы Mi'), findsOneWidget);
        // прокрутка до конца списка
        await tester.drag(find.byType(ListView), const Offset(0, -3000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Освобождаем запросы к базе до закрытия, иначе остаются таймеры drift.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
      });
    }
  }
}
