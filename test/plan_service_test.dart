import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/dates.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/core/nutrition/nutrition_calculation_models.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/services/health/plan_service.dart';

final now = DateTime(2026, 11, 4, 12);

Future<AppDatabase> setup({
  GoalType goal = GoalType.gain,
  bool withWeights = true,
  bool withDiary = true,
  double kg = 70.3,
  int days = 21,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.saveUser(UsersCompanion(
    sex: const Value('male'),
    birthDate: Value(DateTime(1991, 1, 1)),
    heightCm: const Value(175),
    goalType: Value(goal.name),
    activityLevel: const Value('light'),
  ));
  if (withWeights) {
    for (var i = days - 1; i >= 0; i--) {
      await db.addWeight(now.subtract(Duration(days: i)), kg);
    }
  } else {
    await db.addWeight(now, kg); // единственное ручное значение
  }
  if (withDiary) {
    for (var i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      await addManualEntry(db,
          day: dayKey(d),
          meal: Meal.lunch,
          name: 'Обед',
          kcal: 2400,
          p: 150,
          f: 80,
          c: 280);
    }
  }
  return db;
}

void main() {
  test('нет весов и часов: расчёт по ручному весу, адаптации нет', () async {
    final db = await setup(withWeights: false, withDiary: false);
    final p = await loadPlan(db, now);
    expect(p.hasProfile, isTrue);
    expect(
        p.result!.bmr, closeTo(1626.75, 1e-9)); // муж., 35 лет, 175 см, 70,3 кг
    expect(p.result!.targetCalories, closeTo(2460.459375, 1e-6));
    expect(p.weightSource, 'ручной ввод');
    expect(p.proposal, isNull);
    expect(p.energy.tdee, isNull);
    expect(p.confidence, Confidence.low);
    await db.close();
  });

  test('вес от умных весов помечается источником', () async {
    final db = await setup(withWeights: false, withDiary: false);
    await db.addWeight(now.add(const Duration(minutes: 1)), 70.1,
        impedance: 480);
    final p = await loadPlan(db, now.add(const Duration(minutes: 2)));
    expect(p.weightSource, 'умные весы');
    await db.close();
  });

  test(
      'адаптивный режим: предложение не меняет нормы без согласия, принятие пишет историю',
      () async {
    final db = await setup(); // вес стабилен при цели «набор» → калорий мало
    await db.setGoal('1970-01-01', const GoalValues(2460, 150, 63, 330, 2300));
    final p = await loadPlan(db, now);
    expect(p.mode, CalcMode.adaptive);
    expect(p.proposal, isNotNull);
    expect(p.proposal!.deltaKcal, inInclusiveRange(100, 150));
    expect(
        (await db.goalFor(dayKey(now))).calories, 2460); // само не поменялось
    final g = await acceptProposal(db, p, now: now);
    expect(g!.calories, closeTo(2460 + p.proposal!.deltaKcal, 1));
    expect((await db.goalFor(dayKey(now))).calories, g.calories);
    final after = await loadPlan(db, now);
    expect(after.history.last.kind, 'adapt');
    expect(after.offsetKcal, p.proposal!.newOffsetKcal);
    expect(after.proposal,
        isNull); // следующая проверка не раньше чем через 14 дней
    await db.close();
  });

  test('отмена возвращает прежние нормы и поправку', () async {
    final db = await setup();
    await db.setGoal('1970-01-01', const GoalValues(2460, 150, 63, 330, 2300));
    final p = await loadPlan(db, now);
    await acceptProposal(db, p, now: now);
    expect(await undoLast(db, now: now), isTrue);
    expect((await db.goalFor(dayKey(now))).calories, 2460);
    final after = await loadPlan(db, now);
    expect(after.offsetKcal, 0);
    expect(after.history.last.kind, 'undo');
    await db.close();
  });

  test('автоприменение работает только при включённой настройке', () async {
    final db = await setup();
    await db.setGoal('1970-01-01', const GoalValues(2460, 150, 63, 330, 2300));
    expect(await maybeAutoApply(db, now: now), isFalse);
    await db.setSetting(kCalcAutoApplyKey, '1');
    expect(await maybeAutoApply(db, now: now), isTrue);
    expect((await db.goalFor(dayKey(now))).calories, greaterThan(2460));
    expect((await loadPlan(db, now)).history.last.kind, 'auto');
    await db.close();
  });

  test('10. ручная настройка: автоматика не перезаписывает нормы', () async {
    final db = await setup();
    await db.setGoal('1970-01-01', const GoalValues(2460, 150, 63, 330, 2300));
    final manual = const GoalValues(3000, 180, 90, 400, 3000);
    await db.setGoal(dayKey(now), manual);
    await recordManualGoals(
        db, const GoalValues(2460, 150, 63, 330, 2300), manual,
        at: now);
    await db.setSetting(kCalcAutoApplyKey, '1');
    final p = await loadPlan(db, now);
    expect(p.mode, CalcMode.manual);
    expect(p.proposal, isNull);
    expect(await maybeAutoApply(db, now: now), isFalse);
    final g = await db.goalFor(dayKey(now));
    expect([g.calories, g.proteins, g.fats, g.carbs, g.waterMl],
        [3000, 180, 90, 400, 3000]);
    await db.close();
  });

  test('режим «по формулам» не предлагает поправок', () async {
    final db = await setup();
    await setCalcMode(db, CalcMode.standard);
    final p = await loadPlan(db, now);
    expect(p.proposal, isNull);
    expect(p.result!.adaptationOffsetKcal, 0);
    await db.close();
  });

  test('без дневника питания адаптации нет и расход не оценивается', () async {
    final db = await setup(withDiary: false);
    final p = await loadPlan(db, now);
    expect(p.proposal, isNull);
    expect(p.energy.tdee, isNull);
    await db.close();
  });

  test('явный пересчёт сохраняет нормы, вес расчёта и историю', () async {
    final db = await setup(withWeights: false, withDiary: false);
    final p = await loadPlan(db, now);
    final g = await applyRecalc(db, p, now: now);
    expect(g!.calories, 2460);
    expect((await db.goalFor(dayKey(now))).calories, 2460);
    final after = await loadPlan(db, now);
    expect(after.history.single.kind, 'recalc');
    expect(after.weightAtLastCalc, closeTo(70.3, 1e-9));
    expect(after.weightDriftKg, isNull);
    // вес изменился существенно → подсказка пересчитать, нормы сами не меняются
    await db.addWeight(now.add(const Duration(days: 1)), 72.0);
    final drift = await loadPlan(db, now.add(const Duration(days: 1)));
    expect(drift.weightDriftKg, closeTo(1.7, 1e-9));
    expect((await db.goalFor(dayKey(now))).calories, 2460);
    await db.close();
  });

  test('несовершеннолетний: взрослая формула не применяется', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveUser(UsersCompanion(
        sex: const Value('male'),
        birthDate: Value(DateTime(2012, 5, 5)),
        heightCm: const Value(150)));
    await db.addWeight(now, 45);
    final p = await loadPlan(db, now);
    expect(p.minor, isTrue);
    expect(p.result, isNull);
    await db.close();
  });
}
