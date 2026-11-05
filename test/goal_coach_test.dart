import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/features/coach/goal_coach.dart';

const goal = GoalValues(2000, 120, 70, 220, 2000);

List<GoalEvent> ev(Nutrients eaten,
        {double water = 0, double steps = 0, double stepsGoal = 10000}) =>
    achievedGoals(
        eaten: eaten,
        goal: goal,
        calorieTarget: 2000,
        waterMl: water,
        steps: steps,
        stepsGoal: stepsGoal);

void main() {
  group('достижение целей', () {
    test('ничего не выполнено', () {
      expect(ev(const Nutrients(800, 40, 20, 90)), isEmpty);
    });

    test('белок и вода по отдельности', () {
      final e = ev(const Nutrients(900, 125, 30, 90), water: 2100);
      expect(e.map((x) => x.kind), [GoalKind.protein, GoalKind.water]);
    });

    test('калории набраны', () {
      final e = ev(const Nutrients(2050, 80, 70, 250));
      expect(e.map((x) => x.kind), contains(GoalKind.calories));
    });

    test('шаги', () {
      final e = ev(Nutrients.zero, steps: 10500);
      expect(e.single.kind, GoalKind.steps);
    });

    test('КБЖУ в пределах 10 процентов', () {
      final e = ev(const Nutrients(1950, 118, 68, 215));
      expect(e.map((x) => x.kind), contains(GoalKind.macros));
      final bad = ev(const Nutrients(1950, 80, 68, 215));
      expect(bad.map((x) => x.kind), isNot(contains(GoalKind.macros)));
    });

    test('идентификаторы уведомлений различаются', () {
      final ids = GoalKind.values
          .map((k) => GoalEvent(k, '', '').notificationId)
          .toSet();
      expect(ids.length, GoalKind.values.length);
    });
  });

  group('остаток до нормы', () {
    test('не бывает отрицательным', () {
      final r = remainingTo(const Nutrients(2200, 50, 90, 100), goal, 2000);
      expect(r.calories, 0);
      expect(r.proteins, 70);
      expect(r.fats, 0);
      expect(r.carbs, 120);
    });

    test('значимый остаток', () {
      expect(hasGap(const Nutrients(99, 14, 50, 100)), isFalse);
      expect(hasGap(const Nutrients(100, 0, 0, 0)), isTrue);
      expect(hasGap(const Nutrients(50, 15, 0, 0)), isTrue);
    });

    test('текст остатка', () {
      expect(gapSummary(const Nutrients(420, 35, 0.4, 40)),
          '420 ккал, белка 35 г, углеводов 40 г');
    });
  });

  group('подбор продуктов', () {
    test('при нехватке белка предлагает белковое и не превышает калории', () {
      const r = Nutrients(350, 40, 8, 10);
      final s = suggestFoods(r, goal, builtinFoods);
      expect(s, isNotEmpty);
      final total = s.fold(Nutrients.zero, (a, x) => a + x.total);
      expect(total.calories, lessThanOrEqualTo(r.calories * 1.1 + 20));
      expect(total.proteins, greaterThan(15));
    });

    test('если калории закрыты, ничего не предлагает', () {
      expect(suggestFoods(const Nutrients(0, 40, 0, 0), goal, builtinFoods),
          isEmpty);
    });

    test('не больше трёх, без повторов', () {
      final s =
          suggestFoods(const Nutrients(900, 60, 30, 100), goal, builtinFoods);
      expect(s.length, lessThanOrEqualTo(3));
      expect(s.map((x) => x.food.name).toSet().length, s.length);
    });

    test('штучные продукты предлагаются целыми штуками', () {
      const egg = FoodCandidate('Яйцо', Nutrients(155, 12.6, 10.6, 1.1),
          pieceWeight: 50);
      final s = suggestFoods(const Nutrients(160, 13, 10, 1), goal, [egg]);
      // Одно яйцо по 50 г даёт ~78 ккал, остаток 160 ккал закрывают два.
      expect(s.single.pieces, 2);
      expect(s.single.label, contains('2 шт.'));
    });

    test('калории закрыты, белка не хватает: предлагает белковое с пометкой',
        () {
      const r = Nutrients(0, 17, 0, 0);
      final s = suggestProteinFirst(r, builtinFoods);
      expect(s, isNotEmpty);
      expect(s.first.total.proteins, greaterThanOrEqualTo(8.5));
      expect(overflowNote(r, s), isNotNull);
    });

    test('пустой список продуктов', () {
      expect(suggestFoods(const Nutrients(500, 40, 10, 50), goal, const []),
          isEmpty);
    });

    test('количество округляется до 5', () {
      const f = FoodCandidate('Х', Nutrients(100, 10, 0, 0), portionSize: 47);
      final s = FoodSuggestion(f, 47, 0);
      expect(s.quantity, '45 г');
    });
  });
}
