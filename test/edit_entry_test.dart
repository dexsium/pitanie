import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/features/nutrition/edit_entry_sheet.dart';

Future<Product> product(AppDatabase db,
    {String unit = 'g', double? piece, double? portion}) async {
  final id = await db.insertProduct(ProductsCompanion.insert(
    name: 'Печенье',
    calories: 400,
    proteins: 6,
    fats: 15,
    carbohydrates: 60,
    measurementUnit: Value(unit),
    pieceWeight: Value(piece),
    portionSize: Value(portion),
  ));
  return (await db.productById(id))!;
}

Future<FoodEntry> entryById(AppDatabase db, int id) async =>
    (await db.select(db.foodEntries).get()).firstWhere((e) => e.id == id);

void main() {
  group('правка записи в базе', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('масса меняется — пищевая ценность масштабируется пропорционально', () async {
      final p = await product(db);
      final id = await addProductEntry(db,
          day: '2026-11-04', meal: Meal.breakfast, product: p, unit: QtyUnit.base, qty: 100);
      final before = await entryById(db, id);
      expect(before.caloriesSnapshot, 400);
      await db.updateFoodEntry(before, amount: 250, displayQty: 250, displayUnit: 'g');
      final after = await entryById(db, id);
      expect(after.amount, 250);
      expect(after.displayQty, 250);
      expect(after.caloriesSnapshot, closeTo(1000, 1e-9));
      expect(after.proteinsSnapshot, closeTo(15, 1e-9));
      expect(after.fatsSnapshot, closeTo(37.5, 1e-9));
      expect(after.carbohydratesSnapshot, closeTo(150, 1e-9));
    });

    test('снимок сохраняется: правка продукта после записи не меняет её значения', () async {
      final p = await product(db);
      final id = await addProductEntry(db,
          day: '2026-11-04', meal: Meal.lunch, product: p, unit: QtyUnit.base, qty: 100);
      await (db.update(db.products)..where((t) => t.id.equals(p.id)))
          .write(const ProductsCompanion(calories: Value(999)));
      final e = await entryById(db, id);
      await db.updateFoodEntry(e, amount: 200, displayQty: 200, displayUnit: 'g');
      expect((await entryById(db, id)).caloriesSnapshot, closeTo(800, 1e-9)); // 400 × 2
    });

    test('штуки: 2 шт. → 3 шт., единица и масса сохраняются согласованно', () async {
      final p = await product(db, piece: 30);
      final id = await addProductEntry(db,
          day: '2026-11-04', meal: Meal.snack, product: p, unit: QtyUnit.piece, qty: 2);
      final e = await entryById(db, id);
      expect(e.amount, 60);
      await db.updateFoodEntry(e, amount: 90, displayQty: 3, displayUnit: 'piece');
      final after = await entryById(db, id);
      expect(after.amount, 90);
      expect(after.displayQty, 3);
      expect(after.displayUnit, 'piece');
      expect(after.caloriesSnapshot, closeTo(360, 1e-9)); // 400 ккал/100 г × 90 г
    });

    test('смена приёма пищи не трогает значения', () async {
      final p = await product(db);
      final id = await addProductEntry(db,
          day: '2026-11-04', meal: Meal.breakfast, product: p, unit: QtyUnit.base, qty: 100);
      await db.updateFoodEntry(await entryById(db, id), mealType: Meal.dinner.name);
      final e = await entryById(db, id);
      expect(e.mealType, 'dinner');
      expect(e.caloriesSnapshot, 400);
      expect(e.amount, 100);
    });

    test('напиток с учётом воды: объём в воде меняется вместе с записью', () async {
      final p = await product(db, unit: 'ml');
      final id = await addProductEntry(db,
          day: '2026-11-04',
          meal: Meal.breakfast,
          product: p,
          unit: QtyUnit.base,
          qty: 200,
          trackDrink: true);
      await db.updateFoodEntry(await entryById(db, id),
          amount: 300, displayQty: 300, displayUnit: 'ml');
      final water = await db.select(db.waterEntries).get();
      expect(water.length, 1);
      expect(water.first.volumeMl, 300);
    });

    test('быстрая запись: название и значения задаются напрямую', () async {
      final id = await addManualEntry(db,
          day: '2026-11-04', meal: Meal.snack, name: 'Йогурт', kcal: 120, p: 5, f: 3, c: 18);
      final e = await entryById(db, id);
      await db.updateFoodEntry(e,
          mealType: Meal.lunch.name, name: 'Йогурт греческий', kcal: 150, p: 10, f: 4, c: 12);
      final after = await entryById(db, id);
      expect(after.name, 'Йогурт греческий');
      expect(after.mealType, 'lunch');
      expect(after.caloriesSnapshot, 150);
      expect(after.proteinsSnapshot, 10);
      expect(after.fatsSnapshot, 4);
      expect(after.carbohydratesSnapshot, 12);
      expect(after.isManual, isTrue);
    });
  });

  Future<void> openSheet(WidgetTester tester, AppDatabase db, FoodEntry e) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
              child: ElevatedButton(
                  onPressed: () => showEditEntrySheet(context, db, e),
                  child: const Text('открыть'))),
        ),
      ),
    ));
    await tester.tap(find.text('открыть'));
    // окно загружает продукт из базы: даём реальному async завершиться
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await tester.pump(); // монтируется маршрут окна
    await tester.pump(const Duration(milliseconds: 500)); // анимация выезда
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final size in const [Size(393, 852), Size(360, 640), Size(320, 568)]) {
    testWidgets('Окно правки: штуки, пересчёт и сохранение ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      late FoodEntry e;
      late int id;
      await tester.runAsync(() async {
        final p = await product(db, piece: 30, portion: 50);
        id = await addProductEntry(db,
            day: '2026-11-04', meal: Meal.snack, product: p, unit: QtyUnit.piece, qty: 2);
        e = await entryById(db, id);
      });
      await openSheet(tester, db, e);
      expect(tester.takeException(), isNull);
      expect(find.text('Приём пищи'), findsOneWidget);
      expect(find.text('штуки'), findsOneWidget); // доступны штуки
      expect(find.text('порции'), findsOneWidget);
      expect(find.text('г'), findsOneWidget);

      // 2 шт. = 60 г = 240 ккал; меняем на 3 шт. = 90 г = 360 ккал
      expect(find.text('240'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.pump();
      expect(find.text('360'), findsOneWidget);
      // переходим на граммы: число пересчитывается так, чтобы масса не менялась
      await tester.ensureVisible(find.text('г'));
      await tester.pump();
      await tester.tap(find.text('г'));
      await tester.pump();
      expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text,
          '90');
      // меняем приём пищи и сохраняем
      await tester.ensureVisible(find.text('Ужин'));
      await tester.pump();
      await tester.tap(find.text('Ужин'));
      await tester.pump();
      await save(tester);
      final after = (await tester.runAsync(() => entryById(db, id)))!;
      expect(after.amount, 90);
      expect(after.mealType, 'dinner');
      expect(after.caloriesSnapshot, closeTo(360, 1e-9));
      expect(after.displayUnit, 'g');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => db.close());
    });
  }

  testWidgets('Окно правки быстрой записи: название и калории', (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    late FoodEntry e;
    late int id;
    await tester.runAsync(() async {
      id = await addManualEntry(db,
          day: '2026-11-04', meal: Meal.snack, name: 'Йогурт', kcal: 120, p: 5, f: 3, c: 18);
      e = await entryById(db, id);
    });
    await openSheet(tester, db, e);
    expect(tester.takeException(), isNull);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(5)); // название, ккал, Б, Ж, У
    await tester.enterText(fields.at(0), 'Йогурт греческий');
    await tester.enterText(fields.at(1), '150');
    await save(tester);
    final after = (await tester.runAsync(() => entryById(db, id)))!;
    expect(after.name, 'Йогурт греческий');
    expect(after.caloriesSnapshot, 150);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => db.close());
  });
}
