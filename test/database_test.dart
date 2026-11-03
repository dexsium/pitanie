import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/dates.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/day_data.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/features/settings/backup_service.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<Product> buckwheat() async {
    final id = await db.insertProduct(ProductsCompanion.insert(
        name: 'Гречневая каша', calories: 110, proteins: 3.6, fats: 1.2, carbohydrates: 21.3));
    return (await db.productById(id))!;
  }

  const day = '2025-01-24';

  group('питание', () {
    test('каталог заполнен справочными продуктами с источником', () async {
      final list = await db.watchProducts().first;
      expect(list, isNotEmpty);
      expect(list.every((p) => p.source.isNotEmpty), true);
    });

    test('поиск работает без учёта регистра для кириллицы', () async {
      await buckwheat();
      final r = await db.watchProducts(query: 'ГРЕЧНЕВАЯ').first;
      expect(r.map((e) => e.name), contains('Гречневая каша'));
    });

    test('добавление, редактирование массы и удаление пересчитывают день', () async {
      final p = await buckwheat();
      final id = await addProductEntry(db,
          day: day, meal: Meal.lunch, product: p, unit: QtyUnit.base, qty: 200);
      var d = await loadDayData(db, day);
      expect(d.eaten.calories, closeTo(220, 1e-9));
      expect(d.eaten.proteins, closeTo(7.2, 1e-9));

      final entry = d.food.single;
      await db.updateFoodAmount(entry, 100);
      d = await loadDayData(db, day);
      expect(d.eaten.calories, closeTo(110, 1e-9));

      await db.deleteFood(id);
      d = await loadDayData(db, day);
      expect(d.eaten.calories, 0);
    });

    test('снимок не меняется при изменении продукта', () async {
      final p = await buckwheat();
      await addProductEntry(db, day: day, meal: Meal.lunch, product: p, unit: QtyUnit.base, qty: 100);
      await db.updateProduct(p.id, const ProductsCompanion(
          name: Value('Гречневая каша'),
          brand: Value(null),
          calories: Value(999)));
      final d = await loadDayData(db, day);
      expect(d.eaten.calories, closeTo(110, 1e-9));
    });

    test('копирование приёма пищи', () async {
      final p = await buckwheat();
      await addProductEntry(db, day: day, meal: Meal.breakfast, product: p, unit: QtyUnit.base, qty: 150);
      final n = await db.copyMeal(day, '2025-01-25', 'breakfast');
      expect(n, 1);
      expect((await loadDayData(db, '2025-01-25')).eaten.calories, closeTo(165, 1e-9));
    });

    test('ручной ввод помечается и не редактируется по массе', () async {
      await addManualEntry(db, day: day, meal: Meal.snack, name: '', kcal: 300, p: 10);
      final e = (await db.foodForDay(day)).single;
      expect(e.isManual, true);
      expect(e.name, 'Быстрая запись');
    });

    test('напиток с учётом объёма не задваивает калории', () async {
      final id = await db.insertProduct(ProductsCompanion.insert(
          name: 'Сок', calories: 45, proteins: 0.7, fats: 0.2, carbohydrates: 10.4,
          measurementUnit: const Value('ml')));
      final p = (await db.productById(id))!;
      final eid = await addProductEntry(db,
          day: day, meal: Meal.breakfast, product: p, unit: QtyUnit.base, qty: 200, trackDrink: true);
      var d = await loadDayData(db, day);
      expect(d.eaten.calories, closeTo(90, 1e-9));
      expect(d.otherDrinksMl, 200);
      expect(d.plainWaterMl, 0);
      await db.deleteFood(eid);
      d = await loadDayData(db, day);
      expect(d.water, isEmpty);
    });
  });

  group('рецепты', () {
    test('расчёт и сохранение рецепта с готовой массой', () async {
      final a = await buckwheat();
      final id = await db.saveRecipe(
          name: 'Тест', servings: 2, cookedWeight: 400,
          ingredients: [(productId: a.id, quantity: 200)]);
      final r = await db.recipeResult(id);
      expect(r.total.calories, closeTo(220, 1e-9));
      expect(r.per100.calories, closeTo(55, 1e-9));
      expect(r.perServing.calories, closeTo(110, 1e-9));
      final copy = await db.copyRecipe(id);
      expect((await db.recipeResult(copy)).total.calories, closeTo(220, 1e-9));
    });

    test('продукт из рецепта нельзя удалить', () async {
      final a = await buckwheat();
      await db.saveRecipe(name: 'Тест', servings: 1, ingredients: [(productId: a.id, quantity: 100)]);
      expect(await db.deleteCustomProduct(a.id), false);
    });
  });

  group('вода', () {
    test('добавление, правка, удаление и разделение по датам', () async {
      final a = await db.addWater(day, 250);
      await db.addWater(day, 500);
      await db.addWater('2025-01-25', 300);
      var d = await loadDayData(db, day);
      expect(d.plainWaterMl, 750);
      await db.updateWater(a, 100, 'water');
      d = await loadDayData(db, day);
      expect(d.plainWaterMl, 600);
      await db.deleteWater(a);
      d = await loadDayData(db, day);
      expect(d.plainWaterMl, 500);
      expect((await loadDayData(db, '2025-01-25')).plainWaterMl, 300);
    });

    test('другие напитки не входят в норму воды', () async {
      await db.addWater(day, 200, type: 'tea');
      final d = await loadDayData(db, day);
      expect(d.plainWaterMl, 0);
      expect(d.otherDrinksMl, 200);
    });
  });

  group('цели и вес', () {
    test('цель действует с даты вступления в силу, история сохраняется', () async {
      await db.setGoal('1970-01-01', const GoalValues(2000, 100, 70, 250, 2000));
      await db.setGoal('2025-01-20', const GoalValues(3100, 160, 90, 400, 2500));
      expect((await db.goalFor('2025-01-10')).calories, 2000);
      expect((await db.goalFor('2025-01-24')).calories, 3100);
    });

    test('несколько замеров веса в день', () async {
      await db.addWeight(DateTime(2025, 1, 24, 8), 70.0);
      await db.addWeight(DateTime(2025, 1, 24, 20), 70.5);
      final d = await loadDayData(db, day);
      expect(d.weight, 70.5);
      expect((await db.allWeights()).length, 2);
    });
  });

  group('активность', () {
    ActivityRecordsCompanion rec(String ext, double v, {String source = 'zepp'}) =>
        ActivityRecordsCompanion.insert(
            type: 'steps',
            startTime: DateTime(2025, 1, 24, 8),
            endTime: DateTime(2025, 1, 24, 9),
            value: v,
            unit: 'count',
            source: source,
            externalRecordId: ext);

    test('повторная синхронизация не создаёт дубликатов и обновляет значение', () async {
      await db.upsertActivity([rec('a', 500)]);
      await db.upsertActivity([rec('a', 500)]);
      expect((await db.select(db.activityRecords).get()).length, 1);
      await db.upsertActivity([rec('a', 650)]);
      final rows = await db.select(db.activityRecords).get();
      expect(rows.single.value, 650);
    });

    test('шаги из двух источников не суммируются', () async {
      await db.upsertActivity([rec('a', 500, source: 'zepp'), rec('b', 450, source: 'phone')]);
      final d = await loadDayData(db, day);
      expect(d.activity.steps, 500);
    });

    test('данные с часов по Bluetooth приоритетнее Health (без суммирования)', () async {
      await db.upsertActivity([rec('a', 500, source: 'zepp'), rec('b', 450, source: kBleSource)]);
      final d = await loadDayData(db, day);
      expect(d.activity.steps, 450);
      expect(d.activity.source, kBleSource);
    });

    test('нет данных — нули, без ошибок', () async {
      final d = await loadDayData(db, day);
      expect(d.activity.hasData, false);
      expect(d.activity.steps, 0);
    });
  });

  group('резервная копия', () {
    test('экспорт → проверка → восстановление сохраняет данные', () async {
      final p = await buckwheat();
      await addProductEntry(db, day: day, meal: Meal.lunch, product: p, unit: QtyUnit.base, qty: 200);
      await db.addWater(day, 250);
      await db.addWeight(DateTime(2025, 1, 24, 8), 70.5);
      await db.setGoal('1970-01-01', const GoalValues(3100, 160, 90, 400, 2500));
      final text = await BackupService(db).exportJson();
      expect(BackupService.verify(text).ok, true);

      final other = AppDatabase.memory();
      addTearDown(other.close);
      await BackupService(other).restore(text);
      final d = await loadDayData(other, day);
      expect(d.eaten.calories, closeTo(220, 1e-9));
      expect(d.plainWaterMl, 250);
      expect(d.weight, 70.5);
      expect(d.goal.calories, 3100);
    });

    test('повреждённый файл отклоняется', () async {
      final text = await BackupService(db).exportJson();
      expect(BackupService.verify(text.replaceFirst('Гречка', 'Грека')).ok, false);
      expect(BackupService.verify('не json').ok, false);
      expect(BackupService.verify('{"app":"x"}').ok, false);
    });

    test('CSV содержит заголовок и строки дней', () async {
      final p = await buckwheat();
      await addProductEntry(db, day: dayKey(DateTime.now()), meal: Meal.lunch, product: p, unit: QtyUnit.base, qty: 100);
      final csv = await BackupService(db).exportCsv();
      expect(csv, contains('Дата;Ккал'));
      expect(csv.split('\n').length, greaterThan(1));
    });
  });
}
