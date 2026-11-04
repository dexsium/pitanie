import '../nutrition.dart' show activityFactor;
import 'bmr_calculator.dart';
import 'hydration_calculator.dart';
import 'macro_calculator.dart';
import 'nutrition_calculation_models.dart';
import 'tdee_calculator.dart';

/// Полный расчёт норм. Null — если формула неприменима (несовершеннолетний).
CalcResult? calculatePlan(CalcInput i) {
  final bmr = bmrAdult(
      sex: i.sex, weightKg: i.weightKg, heightCm: i.heightCm, age: i.age);
  if (bmr == null) return null;
  final tdee = tdeeFrom(bmr, i.level);
  final frac =
      clampGoalFraction(i.goal, i.goalPercent ?? defaultGoalFraction(i.goal));
  final warnings = <String>[];
  var target = tdee * (1 + frac) + i.adaptationOffsetKcal;
  final floor = calorieFloor(bmr: bmr, sex: i.sex);
  if (target < floor) {
    warnings.add('Норма поднята до нижнего предела ${floor.round()} ккал: '
        'слишком сильный дефицит автоматически не назначается.');
    target = floor;
  }
  final macros = calcMacros(
      targetCalories: target,
      weightKg: i.weightKg,
      goal: i.goal,
      proteinPerKg: i.proteinPerKg,
      fatPerKg: i.fatPerKg);
  warnings.addAll(macros.warnings);
  return CalcResult(
    bmr: bmr,
    pal: activityFactor[i.level]!,
    tdee: tdee,
    goalFraction: frac,
    targetCalories: target,
    macros: macros,
    waterMl: calcWaterMl(
        weightKg: i.weightKg, mlPerKg: i.waterMlPerKg, extraMl: i.waterExtraMl),
    adaptationOffsetKcal: i.adaptationOffsetKcal,
    warnings: warnings,
  );
}
