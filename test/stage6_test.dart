import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/body/measurements_page.dart';
import 'package:pitanie/features/calendar/habits.dart';
import 'package:pitanie/features/calendar/habits_page.dart';
import 'package:pitanie/features/dashboard/day_data.dart';
import 'package:pitanie/features/goals/training_goals_page.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/features/planner/planner_page.dart';
import 'package:pitanie/features/settings/backup_service.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<Product> product(String name, {double kcal = 100}) async {
    final id = await db.insertProduct(ProductsCompanion.insert(
        name: name, calories: kcal, proteins: 10, fats: 5, carbohydrates: 20));
    return (await db.productById(id))!;
  }

  group('нормы тренировочных дней', () {
    setUp(() async {
      await db.setGoal('1970-01-01', const GoalValues(2000, 100, 60, 250, 2000));
      await db.setTrainingGoal('2026-11-01', const GoalValues(2400, 110, 60, 320, 2500));
      await db.upsertWorkouts([
        WorkoutsCompanion.insert(
            source: 'x',
            externalRecordId: 'w1',
            workoutType: 'running',
            startTime: DateTime(2026, 11, 5, 18),
            endTime: DateTime(2026, 11, 5, 19))
      ]);
    });

    test('в тренировочный день действуют свои нормы, в обычный базовые', () async {
      expect((await db.goalForDay('2026-11-05')).calories, 2400);
      expect((await db.goalForDay('2026-11-06')).calories, 2000);
      expect(await db.isTrainingDay('2026-11-05'), isTrue);
      expect(await db.isTrainingDay('2026-11-06'), isFalse);
    });

    test('дневник тренировок тоже делает день тренировочным', () async {
      await db.into(db.liftSessions).insert(
          LiftSessionsCompanion.insert(startedAt: DateTime(2026, 11, 7, 10)));
      expect((await db.goalForDay('2026-11-07')).calories, 2400);
    });

    test('до даты вступления в силу прошлые дни не меняются; отключение возвращает базовые', () async {
      await db.upsertWorkouts([
        WorkoutsCompanion.insert(
            source: 'x',
            externalRecordId: 'w0',
            workoutType: 'running',
            startTime: DateTime(2026, 10, 20, 18),
            endTime: DateTime(2026, 10, 20, 19))
      ]);
      expect((await db.goalForDay('2026-10-20')).calories, 2000);
      await db.setTrainingGoal('2026-11-08',
          const GoalValues(2400, 110, 60, 320, 2500), enabled: false);
      expect((await db.goalForDay('2026-11-05')).calories, 2400); // прошлое сохранилось
      await db.upsertWorkouts([
        WorkoutsCompanion.insert(
            source: 'x',
            externalRecordId: 'w2',
            workoutType: 'running',
            startTime: DateTime(2026, 11, 9, 18),
            endTime: DateTime(2026, 11, 9, 19))
      ]);
      expect((await db.goalForDay('2026-11-09')).calories, 2000);
    });

    test('статистика по диапазону использует те же нормы, что и день', () async {
      final stats = await computeRangeStats(db, '2026-11-04', '2026-11-06');
      expect(stats['2026-11-05']!.goal.calories, 2400);
      expect(stats['2026-11-06']!.goal.calories, 2000);
      expect((await loadDayData(db, '2026-11-05')).goal.calories, 2400);
    });
  });

  group('обхваты тела', () {
    test('изменение за период считается по первому и последнему замеру периода', () {
      BodyMeasurement m(int day, double v) => BodyMeasurement(
          id: day, date: '', measuredAt: DateTime(2026, 11, day), kind: 'waist', valueCm: v);
      final now = DateTime(2026, 11, 20);
      final list = [m(1, 90), m(10, 88.5), m(18, 87)];
      expect(measureChange(list, 30, now), closeTo(-3, 1e-9));
      expect(measureChange(list, 5, now), isNull); // в периоде один замер
      expect(measureChange([m(1, 90)], 0, now), isNull);
    });

    test('замеры и фото сохраняются и удаляются', () async {
      final id = await db.addBodyMeasure('waist', 88, DateTime(2026, 11, 1));
      await db.addBodyMeasure('Шея', 38, DateTime(2026, 11, 2));
      expect((await db.watchBodyMeasures().first).map((e) => e.kind), ['waist', 'Шея']);
      await db.deleteBodyMeasure(id);
      expect((await db.watchBodyMeasures().first).single.kind, 'Шея');
      final pid = await db.addProgressPhoto('a.jpg', DateTime(2026, 11, 3));
      expect(await db.deleteProgressPhoto(pid), 'a.jpg');
      expect(await db.deleteProgressPhoto(pid), isNull);
    });
  });

  group('планировщик', () {
    test('план отдельно от дневника: перенос создаёт запись и работает один раз', () async {
      final a = await product('Овсянка', kcal: 350);
      final id = await db.addPlanItem(MealPlanItemsCompanion.insert(
          date: '2026-11-10',
          mealType: 'breakfast',
          name: 'Овсянка',
          caloriesSnapshot: 175,
          proteinsSnapshot: 5,
          fatsSnapshot: 3,
          carbohydratesSnapshot: 30,
          productId: Value(a.id),
          amount: const Value(50)));
      expect(await db.foodForDay('2026-11-10'), isEmpty);
      expect(await db.transferPlanItemToDiary(id), isTrue);
      expect(await db.transferPlanItemToDiary(id), isFalse);
      final e = (await db.foodForDay('2026-11-10')).single;
      expect(e.caloriesSnapshot, 175);
      expect(e.mealType, 'breakfast');
      expect((await db.planBetween('2026-11-10', '2026-11-10')).single.done, isTrue);
    });

    test('копирование дня плана и итог КБЖУ', () async {
      for (var i = 0; i < 2; i++) {
        await db.addPlanItem(MealPlanItemsCompanion.insert(
            date: '2026-11-10',
            mealType: 'lunch',
            name: 'Суп $i',
            caloriesSnapshot: 200,
            proteinsSnapshot: 10,
            fatsSnapshot: 5,
            carbohydratesSnapshot: 25));
      }
      expect(await db.copyPlanDay('2026-11-10', '2026-11-11'), 2);
      expect(await db.copyPlanDay('2026-11-10', '2026-11-10'), 0);
      final day = await db.planBetween('2026-11-11', '2026-11-11');
      expect(day, hasLength(2));
      expect(planTotal(day).calories, 400);
      expect(weekStartOf(DateTime(2026, 11, 11)), DateTime(2026, 11, 9));
      expect(weekStartOf(DateTime(2026, 11, 15)), DateTime(2026, 11, 9));
    });

    test('список покупок: продукты и ингредиенты блюд суммируются, отметки и ручные позиции сохраняются',
        () async {
      final flour = await product('Мука');
      final milk = await product('Молоко');
      final rid = await db.saveRecipe(name: 'Блины', servings: 4, ingredients: [
        (productId: flour.id, quantity: 200),
        (productId: milk.id, quantity: 400),
      ]);
      // 2 порции из 4: половина ингредиентов
      await db.addPlanItem(MealPlanItemsCompanion.insert(
          date: '2026-11-10',
          mealType: 'breakfast',
          name: 'Блины',
          caloriesSnapshot: 1,
          proteinsSnapshot: 1,
          fatsSnapshot: 1,
          carbohydratesSnapshot: 1,
          recipeId: Value(rid),
          displayQty: const Value(2),
          displayUnit: const Value('portion')));
      await db.addPlanItem(MealPlanItemsCompanion.insert(
          date: '2026-11-12',
          mealType: 'dinner',
          name: 'Мука',
          caloriesSnapshot: 1,
          proteinsSnapshot: 1,
          fatsSnapshot: 1,
          carbohydratesSnapshot: 1,
          productId: Value(flour.id),
          amount: const Value(50)));
      // Вне недели: не попадает в список.
      await db.addPlanItem(MealPlanItemsCompanion.insert(
          date: '2026-11-17',
          mealType: 'dinner',
          name: 'Мука',
          caloriesSnapshot: 1,
          proteinsSnapshot: 1,
          fatsSnapshot: 1,
          carbohydratesSnapshot: 1,
          productId: Value(flour.id),
          amount: const Value(999)));
      expect(await db.buildShoppingList('2026-11-09'), 2);
      var list = await db.watchShopping('2026-11-09').first;
      expect(list.firstWhere((x) => x.name == 'Мука').grams, 150); // 100 + 50
      expect(list.firstWhere((x) => x.name == 'Молоко').grams, 200);

      await db.toggleShopping(list.firstWhere((x) => x.name == 'Мука').id, true);
      await db.addManualShopping('2026-11-09', 'Соль');
      await db.buildShoppingList('2026-11-09');
      list = await db.watchShopping('2026-11-09').first;
      expect(list.firstWhere((x) => x.name == 'Мука').checked, isTrue);
      expect(list.where((x) => x.manual).single.name, 'Соль');
      expect(list, hasLength(3));
    });
  });

  group('привычки и достижения', () {
    test('лучшая серия считается по дням подряд, а пропуски её не обнуляют', () {
      expect(longestRun(['2026-11-01', '2026-11-02', '2026-11-03', '2026-11-05', '2026-11-06']), 3);
      expect(longestRun([]), 0);
      expect(longestRun(['2026-11-30', '2026-12-01']), 2); // через границу месяца
    });

    test('достижения накапливаются из данных', () async {
      await db.setGoal('1970-01-01', const GoalValues(1000, 100, 60, 250, 500));
      final p = await product('Еда', kcal: 100);
      for (var d = 1; d <= 8; d++) {
        final day = '2026-11-${d.toString().padLeft(2, '0')}';
        await addProductEntry(db,
            day: day, meal: Meal.lunch, product: p, unit: QtyUnit.base, qty: 1000); // 1000 ккал
        await db.addWater(day, 600);
      }
      await db.addWeight(DateTime(2026, 11, 2, 8), 70);
      final s = await loadHabits(db, now: DateTime(2026, 11, 9));
      expect(s.foodDays, 8);
      expect(s.bestFoodRun, 8);
      expect(s.waterDays, 8);
      expect(s.goalDays, 8);
      expect(s.weighDays, 1);
      Achievement a(String id) => s.achievements.firstWhere((x) => x.id == id);
      expect(a('first_food').done, isTrue);
      expect(a('run7').done, isTrue);
      expect(a('food30').done, isFalse);
      expect(a('food30').current, 8);
      expect(a('water7').done, isTrue);
      expect(a('weigh1').done, isTrue);
      expect(a('train1').done, isFalse);
      expect(s.days['2026-11-02']!.weighed, isTrue);
    });
  });

  test('копия содержит планировщик, замеры и нормы тренировочных дней', () async {
    await db.setTrainingGoal('2026-11-01', const GoalValues(2400, 110, 60, 320, 2500));
    await db.addBodyMeasure('waist', 88, DateTime(2026, 11, 1));
    await db.addPlanItem(MealPlanItemsCompanion.insert(
        date: '2026-11-10',
        mealType: 'lunch',
        name: 'Суп',
        caloriesSnapshot: 200,
        proteinsSnapshot: 1,
        fatsSnapshot: 1,
        carbohydratesSnapshot: 1));
    await db.addManualShopping('2026-11-09', 'Хлеб');
    final text = await BackupService(db).exportJson();
    final other = AppDatabase.memory();
    addTearDown(other.close);
    await BackupService(other).restore(text);
    expect((await other.allTrainingGoals()).single.calories, 2400);
    expect((await other.watchBodyMeasures().first).single.valueCm, 88);
    expect((await other.planBetween('2026-11-10', '2026-11-10')).single.name, 'Суп');
    expect((await other.watchShopping('2026-11-09').first).single.name, 'Хлеб');
  });

  group('экраны без ошибок вёрстки', () {
    final pages = <String, Widget>{
      'Планировщик': const PlannerPage(),
      'Список покупок': const ShoppingPage(weekStart: '2026-11-09'),
      'Календарь привычек': const HabitsPage(),
      'Измерения тела': const MeasurementsPage(),
      'Тренировочные нормы': const TrainingGoalsPage(),
    };
    for (final e in pages.entries) {
      for (final size in const [Size(393, 852), Size(320, 640)]) {
        testWidgets('${e.key} ${size.width.toInt()}', (tester) async {
          tester.view.physicalSize = size * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final d = AppDatabase(NativeDatabase.memory());
          await tester.pumpWidget(ProviderScope(
            overrides: [dbProvider.overrideWithValue(d)],
            child: MaterialApp(theme: buildTheme(Brightness.light), home: e.value),
          ));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(() => d.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
        });
      }
    }
  });
}
