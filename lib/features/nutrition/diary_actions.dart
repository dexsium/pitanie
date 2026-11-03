import 'package:drift/drift.dart' show Value;

import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';

DateTime _eatenAt(String day) {
  final now = DateTime.now();
  final d = parseDayKey(day);
  return DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second);
}

String unitName(String u) => switch (u) {
      'g' => 'г',
      'ml' => 'мл',
      'portion' => 'порц.',
      'piece' => 'шт.',
      _ => u,
    };

String entryQtyText(FoodEntry e) {
  if (e.isManual) return 'ручной ввод';
  if (e.recipeId != null && e.displayUnit == 'portion') {
    return '${fmtAuto(e.displayQty)} порц.';
  }
  return '${fmtAuto(e.displayQty)} ${unitName(e.displayUnit)}';
}

Nutrients productPer100(Product p) =>
    Nutrients(p.calories, p.proteins, p.fats, p.carbohydrates);

/// Добавляет продукт в дневник. Хранится снимок пищевой ценности.
/// Для напитков можно учесть объём в воде без повторного учёта калорий.
Future<int> addProductEntry(
  AppDatabase db, {
  required String day,
  required Meal meal,
  required Product product,
  required QtyUnit unit,
  required double qty,
  bool trackDrink = false,
}) async {
  final amount = baseAmount(
      unit: unit,
      qty: qty,
      portionSize: product.portionSize,
      pieceWeight: product.pieceWeight);
  if (amount == null || amount <= 0) {
    throw ArgumentError('Не удалось определить массу');
  }
  final n = nutrientsForAmount(productPer100(product), amount);
  final id = await db.addFood(FoodEntriesCompanion.insert(
    date: day,
    eatenAt: _eatenAt(day),
    mealType: meal.name,
    name: product.name,
    caloriesSnapshot: n.calories,
    proteinsSnapshot: n.proteins,
    fatsSnapshot: n.fats,
    carbohydratesSnapshot: n.carbs,
    tzOffsetMin: Value(tzOffsetMinutes()),
    productId: Value(product.id),
    amount: Value(amount),
    amountUnit: Value(product.measurementUnit),
    displayQty: Value(qty),
    displayUnit: Value(switch (unit) {
      QtyUnit.base => product.measurementUnit,
      QtyUnit.portion => 'portion',
      QtyUnit.piece => 'piece',
    }),
  ));
  await db.touchProduct(product.id);
  if (trackDrink && product.measurementUnit == 'ml') {
    await db.addWater(day, amount, type: 'other', foodEntryId: id);
  }
  return id;
}

/// Добавляет блюдо: в порциях или в граммах готового блюда.
Future<int> addRecipeEntry(
  AppDatabase db, {
  required String day,
  required Meal meal,
  required Recipe recipe,
  required bool byPortions,
  required double qty,
}) async {
  final r = await db.recipeResult(recipe.id);
  final Nutrients n;
  final double amount;
  if (byPortions) {
    n = r.perServing * qty;
    amount = r.servingWeight * qty;
  } else {
    n = nutrientsForAmount(r.per100, qty);
    amount = qty;
  }
  return db.addFood(FoodEntriesCompanion.insert(
    date: day,
    eatenAt: _eatenAt(day),
    mealType: meal.name,
    name: recipe.name,
    caloriesSnapshot: n.calories,
    proteinsSnapshot: n.proteins,
    fatsSnapshot: n.fats,
    carbohydratesSnapshot: n.carbs,
    tzOffsetMin: Value(tzOffsetMinutes()),
    recipeId: Value(recipe.id),
    amount: Value(amount),
    displayQty: Value(qty),
    displayUnit: Value(byPortions ? 'portion' : 'g'),
  ));
}

Future<int> addManualEntry(
  AppDatabase db, {
  required String day,
  required Meal meal,
  required String name,
  required double kcal,
  double p = 0,
  double f = 0,
  double c = 0,
}) =>
    db.addFood(FoodEntriesCompanion.insert(
      date: day,
      eatenAt: _eatenAt(day),
      mealType: meal.name,
      name: name.isEmpty ? 'Быстрая запись' : name,
      caloriesSnapshot: kcal,
      proteinsSnapshot: p,
      fatsSnapshot: f,
      carbohydratesSnapshot: c,
      tzOffsetMin: Value(tzOffsetMinutes()),
      isManual: const Value(true),
    ));
