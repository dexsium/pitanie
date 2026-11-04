import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/core/nutrition/bmr_calculator.dart';
import 'package:pitanie/core/nutrition/calc_engine.dart';
import 'package:pitanie/core/nutrition/calorie_adaptation_service.dart';
import 'package:pitanie/core/nutrition/energy_balance_estimator.dart';
import 'package:pitanie/core/nutrition/hydration_calculator.dart';
import 'package:pitanie/core/nutrition/macro_calculator.dart';
import 'package:pitanie/core/nutrition/nutrition_calculation_models.dart';
import 'package:pitanie/core/nutrition/tdee_calculator.dart';
import 'package:pitanie/core/nutrition/weight_trend_analyzer.dart';

final _now = DateTime(2026, 11, 4, 12);

List<WeightPoint> _series(List<double> kg, {int stepDays = 1}) => [
      for (var i = 0; i < kg.length; i++)
        WeightPoint(
            _now.subtract(Duration(days: (kg.length - 1 - i) * stepDays)),
            kg[i]),
    ];

List<double> _linear(int n, double start, double perDay) =>
    [for (var i = 0; i < n; i++) start + perDay * i];

void main() {
  group('формулы по ТЗ', () {
    test('1. BMR мужчины 35 лет, 175 см, 70,3 кг = 1626,75', () {
      final b =
          bmrAdult(sex: Sex.male, weightKg: 70.3, heightCm: 175, age: 35)!;
      expect(b, closeTo(1626.75, 1e-9));
      expect(b.round(), 1627);
    });

    test('1б. женская формула и отказ для несовершеннолетних', () {
      expect(bmrAdult(sex: Sex.female, weightKg: 60, heightCm: 165, age: 30)!,
          closeTo(10 * 60 + 6.25 * 165 - 150 - 161, 1e-9));
      expect(bmrAdult(sex: Sex.male, weightKg: 60, heightCm: 170, age: 17),
          isNull);
      expect(bmrAdult(sex: Sex.male, weightKg: 60, heightCm: 170, age: 18),
          isNotNull);
    });

    test('2. TDEE = 1626,75 × 1,375 = 2236,78', () {
      final t = tdeeFrom(1626.75, ActivityLevel.light);
      expect(t, closeTo(2236.78125, 1e-9));
      expect(t.round(), 2237);
    });

    test('3. набор: профицит 10 % → 2460,46', () {
      final t = tdeeFrom(1626.75, ActivityLevel.light) * 1.10;
      expect(t, closeTo(2460.459375, 1e-6));
      expect(t.round(), 2460);
      final r = calculatePlan(const CalcInput(
          sex: Sex.male,
          age: 35,
          heightCm: 175,
          weightKg: 70.3,
          level: ActivityLevel.light,
          goal: GoalType.gain))!;
      expect(r.targetCalories, closeTo(2460.459375, 1e-6));
      expect(r.bmr, closeTo(1626.75, 1e-9));
    });

    test('4. КБЖУ 150/80/320 ↔ 2600 ккал; остаточный расчёт согласован', () {
      expect(150 * 4 + 80 * 9 + 320 * 4, 2600);
      const m = MacroPlan(2600, 150, 80, 320);
      expect(m.kcalFromMacros, 2600);
      expect(m.mismatch, 0);
      final calc =
          calcMacros(targetCalories: 2600, weightKg: 75, goal: GoalType.gain);
      expect(calc.proteins, 150); // 2,0 г/кг
      expect(calc.kcalFromMacros, closeTo(2600, 1e-9));
      expect(calc.carbs, greaterThan(0));
    });

    test('углеводы никогда не отрицательные, есть предупреждение', () {
      final m =
          calcMacros(targetCalories: 1200, weightKg: 100, goal: GoalType.lose);
      expect(m.carbs, 0);
      expect(m.warnings, isNotEmpty);
      expect(m.fats, closeTo(80, 1e-9)); // жир сначала снижен до 0,8 г/кг
    });

    test('вода: 30–35 мл/кг, без добавки за шаги', () {
      expect(calcWaterMl(weightKg: 70), closeTo(70 * 33, 1e-9));
      expect(calcWaterMl(weightKg: 70, mlPerKg: 50), closeTo(70 * 35, 1e-9));
      expect(calcWaterMl(weightKg: 70, mlPerKg: 10), closeTo(70 * 30, 1e-9));
      expect(calcWaterMl(weightKg: 70, extraMl: 500),
          closeTo(70 * 33 + 500, 1e-9));
    });

    test('границы дефицита и профицита', () {
      expect(clampGoalFraction(GoalType.lose, -0.5), -0.20);
      expect(clampGoalFraction(GoalType.lose, 0), -0.10);
      expect(clampGoalFraction(GoalType.gain, 0.5), 0.15);
      expect(clampGoalFraction(GoalType.gain, 0), 0.05);
    });

    test('сильный дефицит не опускает норму ниже нижнего предела', () {
      final r = calculatePlan(const CalcInput(
          sex: Sex.female,
          age: 30,
          heightCm: 155,
          weightKg: 50,
          level: ActivityLevel.sedentary,
          goal: GoalType.lose,
          adaptationOffsetKcal: -500))!;
      expect(r.targetCalories, greaterThanOrEqualTo(1200));
      expect(r.warnings, isNotEmpty);
    });
  });

  group('работа без устройств и с часами', () {
    test('5. нет весов: ручной вес даёт полный расчёт', () {
      final r = calculatePlan(const CalcInput(
          sex: Sex.female,
          age: 28,
          heightCm: 168,
          weightKg: 62.5, // введён вручную
          level: ActivityLevel.moderate,
          goal: GoalType.maintain))!;
      expect(r.bmr, greaterThan(0));
      expect(r.tdee, closeTo(r.bmr * 1.55, 1e-9));
      expect(r.targetCalories, closeTo(r.tdee, 1e-9));
      expect(r.macros.kcalFromMacros, closeTo(r.targetCalories, 1e-6));
      expect(r.waterMl, greaterThan(1800));
    });

    test('6. нет часов: только PAL, калории активности не выдумываются', () {
      expect(
          watchAdjustedTarget(
              base: 2460,
              activeKcal: null,
              includedActiveKcal: 0,
              reliable: false),
          2460);
      expect(
          watchAdjustedTarget(
              base: 2460,
              activeKcal: 500,
              includedActiveKcal: 0,
              reliable: false),
          2460);
    });

    test(
        '7. есть часы: добавляется только превышение над учтённым, без двойного счёта',
        () {
      expect(
          watchAdjustedTarget(
              base: 2460,
              activeKcal: 500,
              includedActiveKcal: 300,
              reliable: true),
          2660);
      expect(
          watchAdjustedTarget(
              base: 2460,
              activeKcal: 250,
              includedActiveKcal: 300,
              reliable: true),
          2460);
    });
  });

  group('тренд веса и адаптация', () {
    test('8. единичный скачок массы не меняет тренд и норму', () {
      final base = _linear(21, 70.0, 0.0); // стабильный вес
      final spike = [...base]..[20] = 74.0; // один выброс в последний день
      final t = analyzeWeightTrend(_series(spike), _now);
      expect(t.reliable, isTrue);
      expect(t.kgPerWeek!.abs(), lessThan(0.05));
      final c = checkAdaptation(
          goal: GoalType.maintain,
          trend: t,
          currentTarget: 2400,
          currentOffset: 0,
          floorKcal: 1500,
          foodCoverage: 1,
          now: _now);
      expect(c.proposal, isNull);
    });

    test('8б. резкое изменение распознаётся для подтверждения', () {
      expect(
          isSuddenChange(
              previousKg: 70, since: const Duration(hours: 12), newKg: 74),
          isTrue);
      expect(
          isSuddenChange(
              previousKg: 70, since: const Duration(days: 1), newKg: 70.8),
          isFalse);
      expect(isPlausibleWeight(5), isFalse);
      expect(isPlausibleWeight(70), isTrue);
    });

    test('9. недостаточно данных: адаптации нет', () {
      final few = analyzeWeightTrend(_series([70, 70.2, 70.1]), _now);
      expect(few.reliable, isFalse);
      expect(
          checkAdaptation(
                  goal: GoalType.gain,
                  trend: few,
                  currentTarget: 2400,
                  currentOffset: 0,
                  floorKcal: 1500,
                  foodCoverage: 1,
                  now: _now)
              .proposal,
          isNull);
      expect(analyzeWeightTrend(const [], _now).reliable, isFalse);
    });

    test('набор: медленный рост → +100…150 ккал с объяснением', () {
      // масса почти не растёт: +0,05 кг за 20 дней
      final t = analyzeWeightTrend(_series(_linear(21, 70.0, 0.0025)), _now);
      expect(t.reliable, isTrue);
      final c = checkAdaptation(
          goal: GoalType.gain,
          trend: t,
          currentTarget: 2460,
          currentOffset: 0,
          floorKcal: 1500,
          foodCoverage: 0.9,
          now: _now);
      expect(c.proposal, isNotNull);
      expect(c.proposal!.deltaKcal, inInclusiveRange(100, 150));
      expect(c.proposal!.newTargetKcal,
          closeTo(2460 + c.proposal!.deltaKcal, 1e-9));
      expect(c.proposal!.reason, contains('Предлагаем увеличить'));
    });

    test('набор: слишком быстрый рост → уменьшение', () {
      final t = analyzeWeightTrend(
          _series(_linear(21, 70.0, 0.15)), _now); // ≈1 кг/нед
      final c = checkAdaptation(
          goal: GoalType.gain,
          trend: t,
          currentTarget: 2460,
          currentOffset: 0,
          floorKcal: 1500,
          foodCoverage: 1,
          now: _now);
      expect(c.proposal!.deltaKcal, lessThan(0));
    });

    test('не чаще раза в 14 дней и не при неполном дневнике', () {
      final t = analyzeWeightTrend(_series(_linear(21, 70.0, 0.0)), _now);
      final recent = checkAdaptation(
          goal: GoalType.gain,
          trend: t,
          currentTarget: 2460,
          currentOffset: 0,
          floorKcal: 1500,
          foodCoverage: 1,
          now: _now,
          lastAdjustment: _now.subtract(const Duration(days: 5)));
      expect(recent.proposal, isNull);
      final noDiary = checkAdaptation(
          goal: GoalType.gain,
          trend: t,
          currentTarget: 2460,
          currentOffset: 0,
          floorKcal: 1500,
          foodCoverage: 0.2,
          now: _now);
      expect(noDiary.proposal, isNull);
    });

    test('накопленная поправка ограничена ±500', () {
      final t = analyzeWeightTrend(_series(_linear(21, 70.0, 0.0)), _now);
      final c = checkAdaptation(
          goal: GoalType.gain,
          trend: t,
          currentTarget: 2900,
          currentOffset: 500,
          floorKcal: 1500,
          foodCoverage: 1,
          now: _now);
      expect(c.proposal, isNull);
    });
  });

  group('оценка фактического TDEE', () {
    test('считается только при достоверном тренде и полном дневнике', () {
      final t = analyzeWeightTrend(_series(_linear(28, 70.0, 0.0)), _now);
      final ok = estimateTdee(
          trend: t,
          dailyIntakeKcal: List.filled(28, 2400),
          observedDays: 28,
          formulaTdee: 2300);
      expect(ok.tdee, closeTo(2400, 1e-6)); // вес стабилен → расход = приём
      final sparse = estimateTdee(
          trend: t,
          dailyIntakeKcal: [...List.filled(5, 2400), ...List.filled(23, 0)],
          observedDays: 28,
          formulaTdee: 2300);
      expect(sparse.tdee, isNull);
      final noTrend = estimateTdee(
          trend: analyzeWeightTrend(const [], _now),
          dailyIntakeKcal: List.filled(28, 2400),
          observedDays: 28,
          formulaTdee: 2300);
      expect(noTrend.tdee, isNull);
    });

    test('при росте массы расход ниже приёма (7700 ккал/кг)', () {
      final t = analyzeWeightTrend(
          _series(_linear(28, 70.0, 0.05)), _now); // 0,35 кг/нед
      final e = estimateTdee(
          trend: t,
          dailyIntakeKcal: List.filled(28, 2800),
          observedDays: 28,
          formulaTdee: 2500);
      expect(e.tdee, closeTo(2800 - 7700 * 0.05, 1));
    });
  });
}
