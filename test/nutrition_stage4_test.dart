import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/core/nutrition.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<Product> product(String name,
      {double kcal = 100, double p = 10, double f = 5, double c = 20, String? brand}) async {
    final id = await db.insertProduct(ProductsCompanion.insert(
        name: name,
        calories: kcal,
        proteins: p,
        fats: f,
        carbohydrates: c,
        brand: Value(brand)));
    return (await db.productById(id))!;
  }

  Future<void> eat(Product pr, String day, Meal meal, double grams) =>
      addProductEntry(db, day: day, meal: meal, product: pr, unit: QtyUnit.base, qty: grams);

  test('повтор последнего приёма пищи берёт ближайший прошлый день с этим приёмом', () async {
    final oat = await product('Овсянка');
    final egg = await product('Яйцо');
    await eat(oat, '2026-11-05', Meal.breakfast, 60);
    await eat(egg, '2026-11-07', Meal.breakfast, 100);
    await eat(oat, '2026-11-08', Meal.lunch, 50); // другой приём: не мешает
    expect(await db.lastMealDay('breakfast', '2026-11-10'), '2026-11-07');
    final n = await db.repeatLastMeal('2026-11-10', 'breakfast');
    expect(n, 1);
    final day = await db.foodForDay('2026-11-10');
    expect(day.single.name, 'Яйцо');
    expect(day.single.mealType, 'breakfast');
    expect(day.single.amount, 100);
    // Раньше ужин не записывался.
    expect(await db.repeatLastMeal('2026-11-10', 'dinner'), 0);
    // Будущие дни не считаются «последними».
    expect(await db.lastMealDay('breakfast', '2026-11-05'), isNull);
  });

  test('копирование дня переносит все приёмы пищи и не копирует день в себя', () async {
    final a = await product('A');
    await eat(a, '2026-11-01', Meal.breakfast, 100);
    await eat(a, '2026-11-01', Meal.dinner, 200);
    expect(await db.copyDay('2026-11-01', '2026-11-01'), 0);
    expect(await db.copyDay('2026-11-01', '2026-11-02'), 2);
    final d = await db.foodForDay('2026-11-02');
    expect(d.map((e) => e.mealType).toSet(), {'breakfast', 'dinner'});
    expect(d.fold<double>(0, (s, e) => s + e.caloriesSnapshot), 300);
  });

  test('шаблон приёма пищи сохраняет снимок и применяется в другой день', () async {
    final a = await product('Гречка', kcal: 110);
    await eat(a, '2026-11-01', Meal.lunch, 200);
    final id = (await db.saveMealTemplate('2026-11-01', 'lunch', '  Обед типовой '))!;
    // Продукт изменился, шаблон хранит прежние значения.
    await db.updateProduct(a.id, const ProductsCompanion(calories: Value(999)));
    expect(await db.applyMealTemplate(id, '2026-11-09', 'dinner'), 1);
    final e = (await db.foodForDay('2026-11-09')).single;
    expect(e.mealType, 'dinner');
    expect(e.caloriesSnapshot, closeTo(220, 1e-9));
    expect((await db.watchMealTemplates().first).single.name, 'Обед типовой');
    expect(await db.saveMealTemplate('2026-11-03', 'lunch', 'пусто'), isNull);
    await db.deleteMealTemplate(id);
    expect(await db.watchMealTemplates().first, isEmpty);
    expect(await db.templateItems(id), isEmpty);
  });

  test('частые порции: по числу повторов, затем по давности', () async {
    final a = await product('Хлеб');
    for (var i = 0; i < 3; i++) {
      await eat(a, '2026-11-0${i + 1}', Meal.breakfast, 30);
    }
    await eat(a, '2026-11-05', Meal.breakfast, 50);
    await eat(a, '2026-11-06', Meal.breakfast, 80);
    final f = await db.frequentPortions(a.id);
    expect(f.first.qty, 30);
    expect(f.first.count, 3);
    expect(f.length, 3);
    expect(f[1].qty, 80); // более поздняя из одиночных
    expect(await db.frequentPortions(999), isEmpty);
  });

  test('защита от дублей: тот же состав — дубль, другой состав или производитель — нет', () async {
    await product('Творог', kcal: 120, p: 18, f: 5, c: 3, brand: 'Простоквашино');
    final same = await db.findSimilarProduct(
        name: ' творог ', brand: 'простоквашино', kcal: 120.5, p: 18.2, f: 5, c: 3);
    expect(same, isNotNull);
    expect(
        await db.findSimilarProduct(
            name: 'Творог', brand: 'Простоквашино', kcal: 160, p: 16, f: 9, c: 3),
        isNull);
    expect(
        await db.findSimilarProduct(
            name: 'Творог', brand: 'Другой', kcal: 120, p: 18, f: 5, c: 3),
        isNull);
    expect(
        await db.findSimilarProduct(
            name: 'Творог',
            brand: 'Простоквашино',
            kcal: 120,
            p: 18,
            f: 5,
            c: 3,
            excludeId: same!.id),
        isNull);
  });

  test('при создании и правке продукта обновляется дата карточки', () async {
    final a = await product('Сыр');
    expect(a.updatedAt, isNotNull);
    final first = a.updatedAt!;
    await db.updateProduct(a.id, const ProductsCompanion(calories: Value(300)));
    final after = (await db.productById(a.id))!;
    expect(after.calories, 300);
    expect(after.updatedAt!.isBefore(first), isFalse);
  });

  test('правка рецепта и продукта не меняет уже записанные приёмы пищи', () async {
    final a = await product('Мука', kcal: 340, p: 10, f: 1, c: 70);
    final rid = await db.saveRecipe(
        name: 'Тесто',
        servings: 2,
        ingredients: [(productId: a.id, quantity: 200)]);
    final recipe = (await db.recipeById(rid))!;
    await addRecipeEntry(db,
        day: '2026-11-01', meal: Meal.lunch, recipe: recipe, byPortions: true, qty: 1);
    final before = (await db.foodForDay('2026-11-01')).single.caloriesSnapshot;
    await db.updateProduct(a.id, const ProductsCompanion(calories: Value(500)));
    await db.saveRecipe(
        id: rid, name: 'Тесто', servings: 4, ingredients: [(productId: a.id, quantity: 400)]);
    final after = (await db.foodForDay('2026-11-01')).single.caloriesSnapshot;
    expect(after, before);
    expect(before, closeTo(340, 1e-6)); // 200 г × 340 / 100 / 2 порции
  });
}
