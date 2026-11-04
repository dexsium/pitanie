import '../nutrition.dart' show ActivityLevel, GoalType, Sex;

/// Режим расчёта норм.
enum CalcMode {
  /// Формулы + постепенная поправка по тренду веса (с подтверждением пользователя).
  adaptive,

  /// Только стандартные формулы, без поправок.
  standard,

  /// Нормы заданы вручную и автоматически не перезаписываются.
  manual,
}

/// Достоверность оценки.
enum Confidence { none, low, medium, high }

/// Исходные данные для расчёта. Все значения — «как есть», округление делает только UI.
class CalcInput {
  final Sex sex;
  final int age;
  final double heightCm;
  final double weightKg;
  final ActivityLevel level;
  final GoalType goal;

  /// Доля дефицита (для похудения, отрицательная) или профицита (для набора) от TDEE;
  /// null — по умолчанию для цели.
  final double? goalPercent;

  /// Накопленная поправка адаптации, ккал/сут (подтверждённая пользователем).
  final double adaptationOffsetKcal;

  /// Белок и жир, г/кг; null — по умолчанию для цели.
  final double? proteinPerKg;
  final double? fatPerKg;

  /// Вода, мл/кг (30–35) и ручная добавка, мл.
  final double waterMlPerKg;
  final double waterExtraMl;

  const CalcInput({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.level,
    required this.goal,
    this.goalPercent,
    this.adaptationOffsetKcal = 0,
    this.proteinPerKg,
    this.fatPerKg,
    this.waterMlPerKg = 33,
    this.waterExtraMl = 0,
  });
}

/// Нормы БЖУ в граммах (точные значения, без округления).
class MacroPlan {
  final double calories, proteins, fats, carbs;

  /// Предупреждения: например, калорий не хватает на выбранные белок и жир.
  final List<String> warnings;
  const MacroPlan(this.calories, this.proteins, this.fats, this.carbs,
      [this.warnings = const []]);

  /// Калории, восстановленные из граммов (4/9/4).
  double get kcalFromMacros => proteins * 4 + fats * 9 + carbs * 4;

  /// Расхождение между целью и суммой 4/9/4 (ккал). Не ноль, если углеводы обрезаны до нуля.
  double get mismatch => calories - kcalFromMacros;
}

class CalcResult {
  final double bmr;
  final double pal;
  final double tdee;

  /// Доля профицита (+) или дефицита (−) от TDEE.
  final double goalFraction;
  final double targetCalories;
  final MacroPlan macros;
  final double waterMl;
  final double adaptationOffsetKcal;
  final List<String> warnings;
  const CalcResult({
    required this.bmr,
    required this.pal,
    required this.tdee,
    required this.goalFraction,
    required this.targetCalories,
    required this.macros,
    required this.waterMl,
    required this.adaptationOffsetKcal,
    required this.warnings,
  });
}

/// Одно измерение массы.
class WeightPoint {
  final DateTime at;
  final double kg;
  const WeightPoint(this.at, this.kg);
}

/// Результат анализа тренда веса.
class WeightTrend {
  final bool reliable;

  /// Сглаженный вес (среднее за последние 7 дней), кг.
  final double? smoothedKg;

  /// Недельный тренд, кг/нед (устойчивая оценка).
  final double? kgPerWeek;
  final int measurements;
  final int days;
  final String? reason;
  const WeightTrend({
    required this.reliable,
    this.smoothedKg,
    this.kgPerWeek,
    this.measurements = 0,
    this.days = 0,
    this.reason,
  });
}

/// Оценка фактического TDEE по балансу «питание ↔ изменение массы».
class EnergyEstimate {
  final double? tdee;
  final Confidence confidence;
  final String? reason;
  const EnergyEstimate(this.tdee, this.confidence, [this.reason]);
}

/// Предложение изменить норму калорий.
class AdaptationProposal {
  final double deltaKcal;
  final double newOffsetKcal;
  final double newTargetKcal;
  final String reason;
  const AdaptationProposal(
      this.deltaKcal, this.newOffsetKcal, this.newTargetKcal, this.reason);
}

/// Исход проверки адаптации: либо предложение, либо понятная причина, почему его нет.
class AdaptationCheck {
  final AdaptationProposal? proposal;
  final String message;
  const AdaptationCheck(this.proposal, this.message);
}
