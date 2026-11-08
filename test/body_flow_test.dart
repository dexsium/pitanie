import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/body/body_page.dart';
import 'package:pitanie/features/scale/mi_scale.dart';
import 'package:pitanie/features/scale/scale_controller.dart';
import 'package:pitanie/features/scale/scale_measure_page.dart';

MiScaleReading reading(double kg,
        {bool stable = false, bool removed = false, int? imp, String stamp = 'a'}) =>
    MiScaleReading(kg, imp, stable, removed, stamp);

const _sizes = [Size(393, 852), Size(360, 740), Size(430, 932), Size(320, 640)];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('фазы измерения на весах', () {
    late AppDatabase db;
    late ScaleController c;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      c = ScaleController(db);
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    test('сошёл раньше времени: повторы пакета не держат измерение, следующее взвешивание проходит',
        () async {
      final t0 = DateTime(2026, 11, 8, 12);
      await c.onReading(reading(69.2, stamp: 'a'), now: t0);
      expect(c.phase, ScalePhase.measuring);
      // Весы повторяют один и тот же пакет, ничего не меняется.
      for (var s = 5; s <= 30; s += 5) {
        await c.onReading(reading(69.2, stamp: 'a'), now: t0.add(Duration(seconds: s)));
      }
      c.checkStale(now: t0.add(const Duration(seconds: 30)));
      expect(c.phase, ScalePhase.idle);
      // Тот же повтор после прерывания измерение не запускает.
      await c.onReading(reading(69.2, stamp: 'a'), now: t0.add(const Duration(seconds: 35)));
      expect(c.phase, ScalePhase.idle);
      // Новое взвешивание (другая метка) проходит до сохранения.
      await c.onReading(reading(70.0, stamp: 'b'), now: t0.add(const Duration(seconds: 60)));
      expect(c.phase, ScalePhase.measuring);
      await c.onReading(reading(70.1, stable: true, imp: 480, stamp: 'b'),
          now: t0.add(const Duration(seconds: 65)));
      expect(c.phase, ScalePhase.done);
      expect((await db.allWeights()).length, 1);
    });

    test('вес без стабилизации — идёт измерение, пока ничего не сохранено', () async {
      await c.onReading(reading(69.2));
      expect(c.phase, ScalePhase.measuring);
      expect(c.liveKg, 69.2);
      expect(await db.allWeights(), isEmpty);
    });

    test('стабильный вес с импедансом сохраняется вместе с импедансом', () async {
      await c.onReading(reading(69.4));
      await c.onReading(reading(69.5, stable: true, imp: 512));
      expect(c.phase, ScalePhase.done);
      final w = await db.allWeights();
      expect(w.length, 1);
      expect(w.first.weightKg, 69.5);
      expect(w.first.impedance, 512);
      expect(c.savedEntry!.id, w.first.id);
    });

    test('сначала вес без импеданса, потом пакет с импедансом — одна запись с импедансом', () async {
      await c.onReading(reading(69.5, stable: true));
      expect(c.phase, ScalePhase.measuring); // ждём импеданс
      expect(await db.allWeights(), isEmpty);
      await c.onReading(reading(69.5, stable: true, imp: 480));
      final w = await db.allWeights();
      expect(w.length, 1);
      expect(w.first.impedance, 480);
    });

    test('повторы пакета того же взвешивания не создают дубликатов', () async {
      await c.onReading(reading(69.5, stable: true, imp: 480));
      await c.onReading(reading(69.5, stable: true, imp: 480));
      await c.onReading(reading(69.5, removed: true, imp: 480));
      expect((await db.allWeights()).length, 1);
      expect(c.phase, ScalePhase.idle);
    });

    test('сошёл с весов до завершения — измерение прервано, записи нет', () async {
      await c.onReading(reading(40.0));
      await c.onReading(reading(40.0, removed: true, stamp: 'b'));
      expect(c.phase, ScalePhase.idle);
      expect(await db.allWeights(), isEmpty);
    });

    test('пакеты перестали приходить — измерение прервано по таймауту', () async {
      final t0 = DateTime(2026, 11, 4, 12);
      await c.onReading(reading(60.0), now: t0);
      c.checkStale(now: t0.add(const Duration(seconds: 10)));
      expect(c.phase, ScalePhase.measuring);
      c.checkStale(now: t0.add(const Duration(seconds: 40)));
      expect(c.phase, ScalePhase.idle);
    });

    test('закрытое окно не открывается снова до конца взвешивания', () async {
      await c.onReading(reading(69.0));
      c.dismissed = true;
      await c.onReading(reading(69.3));
      expect(c.dismissed, isTrue);
      await c.onReading(reading(69.3, removed: true, stamp: 'z'));
      expect(c.dismissed, isFalse); // новое взвешивание снова откроет окно
    });
  });

  Future<AppDatabase> seeded(WidgetTester tester, {bool withUser = true, bool withImpedance = true}) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() async {
      if (withUser) {
        await db.saveUser(UsersCompanion(
            sex: const Value('male'),
            birthDate: Value(DateTime(1990, 5, 1)),
            heightCm: const Value(175),
            goalType: const Value('gain')));
      }
      final now = DateTime.now();
      for (var i = 4; i >= 0; i--) {
        await db.addWeight(now.subtract(Duration(days: i * 3)), 69.0 + (4 - i) * 0.2,
            impedance: withImpedance ? 500.0 - i * 5 : null);
      }
    });
    return db;
  }

  Future<void> disposeAll(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
  }

  for (final size in _sizes) {
    for (final scenario in const ['с составом', 'без импеданса', 'без анкеты']) {
      testWidgets('Состав тела без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()} $scenario',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final db = await seeded(tester,
            withUser: scenario != 'без анкеты', withImpedance: scenario != 'без импеданса');
        final entry = (await tester.runAsync(() => db.allWeights()))!.last;
        await tester.pumpWidget(ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
              theme: buildTheme(Brightness.light), home: BodyCompositionPage(entry: entry)),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        expect(find.text('Состав тела'), findsOneWidget);
        expect(find.text('Показатели состава тела'), findsOneWidget);
        if (scenario == 'с составом') {
          expect(find.textContaining('Норма ('), findsWidgets);
        }
        await tester.drag(find.byType(ListView), const Offset(0, -5000));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        if (scenario == 'с составом') {
          expect(find.text('Оценка состояния тела'), findsOneWidget);
        }
        await disposeAll(tester, db);
      });
    }

    testWidgets('Динамика изменений ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final db = await seeded(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const BodyDynamicsPage()),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Жир'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await disposeAll(tester, db);
    });

    for (final phase in ['измерение', 'сохранено']) {
      testWidgets('Окно измерения ${size.width.toInt()}×${size.height.toInt()} $phase', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final db = await seeded(tester);
        final ctrl = ScaleController(db);
        await tester.runAsync(() async {
          await ctrl.onReading(reading(69.5));
          if (phase == 'сохранено') {
            await ctrl.onReading(reading(69.5, stable: true, imp: 500, stamp: 'x'));
          }
        });
        await tester.pumpWidget(ProviderScope(
          overrides: [
            dbProvider.overrideWithValue(db),
            scaleProvider.overrideWith((ref) => ctrl),
          ],
          child: MaterialApp(
              theme: buildTheme(Brightness.light), home: const ScaleMeasurePage()),
        ));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.text('Измерение веса'), findsOneWidget);
        expect(find.text('Подключение'), findsOneWidget);
        expect(find.text('Текущий вес'), findsOneWidget);
        if (phase == 'сохранено') {
          // после завершения окно само переходит к составу тела
          await tester.pump(const Duration(milliseconds: 1500));
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          expect(find.text('Состав тела'), findsOneWidget);
        }
        await disposeAll(tester, db);
      });
    }
  }
}
