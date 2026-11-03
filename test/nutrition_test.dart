import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/nutrition.dart';

void main() {
  const buckwheat = Nutrients(110, 3.6, 1.2, 21.3);

  group('расчёт по массе', () {
    test('200 г гречки', () {
      final n = nutrientsForAmount(buckwheat, 200);
      expect(n.calories, closeTo(220, 1e-9));
      expect(n.proteins, closeTo(7.2, 1e-9));
      expect(n.fats, closeTo(2.4, 1e-9));
      expect(n.carbs, closeTo(42.6, 1e-9));
    });

    test('округление не применяется до отображения', () {
      final n = nutrientsForAmount(const Nutrients(33, 0.33, 0.33, 0.33), 33.3);
      expect(n.calories, closeTo(10.989, 1e-9));
    });

    test('порции и штуки', () {
      expect(baseAmount(unit: QtyUnit.piece, qty: 2, pieceWeight: 50), 100);
      expect(baseAmount(unit: QtyUnit.portion, qty: 1.5, portionSize: 200), 300);
      expect(baseAmount(unit: QtyUnit.piece, qty: 2), isNull);
      expect(baseAmount(unit: QtyUnit.base, qty: 120), 120);
    });

    test('суммирование приёмов пищи и пересчёт после удаления/правки', () {
      var items = [
        nutrientsForAmount(buckwheat, 200),
        nutrientsForAmount(const Nutrients(143, 12.6, 9.5, 0.7), 100),
      ];
      Nutrients sum() => items.fold(Nutrients.zero, (a, b) => a + b);
      expect(sum().calories, closeTo(363, 1e-9));
      items = [items[0], nutrientsForAmount(const Nutrients(143, 12.6, 9.5, 0.7), 50)];
      expect(sum().calories, closeTo(291.5, 1e-9));
      items = [items[0]];
      expect(sum().calories, closeTo(220, 1e-9));
    });
  });

  group('рецепты', () {
    final lines = [
      const RecipeLine(Nutrients(365, 7.1, 0.7, 80), 300),
      const RecipeLine(Nutrients(215, 18.6, 15, 0), 400),
      const RecipeLine(Nutrients(41, 0.9, 0.2, 9.6), 150),
      const RecipeLine(Nutrients(40, 1.1, 0.1, 9.3), 100),
      const RecipeLine(Nutrients(884, 0, 100, 0), 40),
    ];

    test('без массы готового блюда', () {
      final r = calcRecipe(lines, servings: 4);
      expect(r.rawWeight, 990);
      expect(r.finalWeight, 990);
      expect(r.total.calories, closeTo(1095 + 860 + 61.5 + 40 + 353.6, 1e-9));
      expect(r.perServing.calories, closeTo(r.total.calories / 4, 1e-9));
      expect(r.servingWeight, 990 / 4);
      expect(r.per100.calories, closeTo(r.total.calories / 9.9, 1e-9));
    });

    test('масса готового блюда не меняет общую энергию', () {
      final raw = calcRecipe(lines, servings: 4);
      final cooked = calcRecipe(lines, cookedWeight: 800, servings: 4);
      expect(cooked.total.calories, closeTo(raw.total.calories, 1e-9));
      expect(cooked.finalWeight, 800);
      expect(cooked.per100.calories, closeTo(raw.total.calories / 8, 1e-9));
      expect(cooked.per100.calories, greaterThan(raw.per100.calories));
    });

    test('пустой рецепт не даёт деления на ноль', () {
      final r = calcRecipe([], servings: 2);
      expect(r.total.calories, 0);
      expect(r.per100.calories, 0);
    });
  });

  group('профиль и цели', () {
    test('Миффлин — Сан Жеор', () {
      expect(bmrMifflin(sex: Sex.male, weightKg: 80, heightCm: 180, age: 30), 1780);
      expect(bmrMifflin(sex: Sex.female, weightKg: 60, heightCm: 165, age: 30),
          closeTo(10 * 60 + 6.25 * 165 - 150 - 161, 1e-9));
    });

    test('возраст', () {
      expect(ageOn(DateTime(1990, 6, 15), DateTime(2025, 6, 14)), 34);
      expect(ageOn(DateTime(1990, 6, 15), DateTime(2025, 6, 15)), 35);
    });

    test('рекомендации по цели', () {
      final bmr = bmrMifflin(sex: Sex.male, weightKg: 80, heightCm: 180, age: 30);
      final keep = suggestGoals(bmr: bmr, level: ActivityLevel.moderate, goal: GoalType.maintain, weightKg: 80);
      final lose = suggestGoals(bmr: bmr, level: ActivityLevel.moderate, goal: GoalType.lose, weightKg: 80);
      final gain = suggestGoals(bmr: bmr, level: ActivityLevel.moderate, goal: GoalType.gain, weightKg: 80);
      expect(lose.calories, lessThan(keep.calories));
      expect(gain.calories, greaterThan(keep.calories));
      expect(keep.carbs, greaterThan(0));
    });

    test('динамическая цель не считает активность дважды', () {
      expect(effectiveCalorieTarget(base: 2500, mode: CalorieMode.fixed, activeKcal: 400), 2500);
      expect(effectiveCalorieTarget(base: 2500, mode: CalorieMode.dynamic, activeKcal: 400), 2900);
      expect(
          effectiveCalorieTarget(
              base: 2500, mode: CalorieMode.dynamic, activeKcal: 400, includedActiveKcal: 300),
          2600);
      expect(
          effectiveCalorieTarget(
              base: 2500, mode: CalorieMode.dynamic, activeKcal: 100, includedActiveKcal: 300),
          2500);
    });
  });
}
