/// Чистая бизнес-логика расчётов. Без зависимостей от Flutter и БД.
/// Все значения хранятся точными числами; округление выполняет только UI.
class Nutrients {
  final double calories, proteins, fats, carbs;
  const Nutrients(this.calories, this.proteins, this.fats, this.carbs);
  static const zero = Nutrients(0, 0, 0, 0);

  Nutrients operator +(Nutrients o) => Nutrients(
      calories + o.calories, proteins + o.proteins, fats + o.fats, carbs + o.carbs);
  Nutrients operator *(double k) =>
      Nutrients(calories * k, proteins * k, fats * k, carbs * k);
  Nutrients operator /(double k) =>
      Nutrients(calories / k, proteins / k, fats / k, carbs / k);
}

/// Количество нутриента = (масса / 100) × значение на 100 г.
Nutrients nutrientsForAmount(Nutrients per100, double amount) =>
    per100 * (amount / 100);

enum QtyUnit { base, portion, piece }

/// Перевод введённого количества в граммы/мл. null, если данных не хватает.
double? baseAmount({
  required QtyUnit unit,
  required double qty,
  double? portionSize,
  double? pieceWeight,
}) {
  switch (unit) {
    case QtyUnit.base:
      return qty;
    case QtyUnit.portion:
      return portionSize == null ? null : qty * portionSize;
    case QtyUnit.piece:
      return pieceWeight == null ? null : qty * pieceWeight;
  }
}

class RecipeLine {
  final Nutrients per100;
  final double quantity;
  const RecipeLine(this.per100, this.quantity);
}

class RecipeResult {
  final Nutrients total;
  final double rawWeight;
  final double finalWeight;
  final Nutrients per100;
  final Nutrients perServing;
  final double servingWeight;
  const RecipeResult(this.total, this.rawWeight, this.finalWeight, this.per100,
      this.perServing, this.servingWeight);
}

/// Итоговая энергия берётся из ингредиентов и не зависит от массы готового
/// блюда. Масса готового блюда влияет только на пересчёт «на 100 г».
RecipeResult calcRecipe(List<RecipeLine> lines,
    {double? cookedWeight, int servings = 1}) {
  var total = Nutrients.zero;
  var raw = 0.0;
  for (final l in lines) {
    total = total + nutrientsForAmount(l.per100, l.quantity);
    raw += l.quantity;
  }
  final weight = (cookedWeight != null && cookedWeight > 0) ? cookedWeight : raw;
  final s = servings < 1 ? 1 : servings;
  final per100 = weight > 0 ? total / (weight / 100) : Nutrients.zero;
  return RecipeResult(total, raw, weight, per100, total / s.toDouble(), weight / s);
}

enum Sex { male, female }

enum GoalType { gain, lose, maintain }

enum ActivityLevel { sedentary, light, moderate, high, extreme }

const activityFactor = {
  ActivityLevel.sedentary: 1.2,
  ActivityLevel.light: 1.375,
  ActivityLevel.moderate: 1.55,
  ActivityLevel.high: 1.725,
  ActivityLevel.extreme: 1.9,
};

int ageOn(DateTime birth, DateTime now) {
  var a = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) {
    a--;
  }
  return a;
}

/// Формула Миффлина — Сан Жеора (ккал/сут, оценка).
double bmrMifflin(
    {required Sex sex,
    required double weightKg,
    required double heightCm,
    required int age}) {
  return 10 * weightKg + 6.25 * heightCm - 5 * age + (sex == Sex.male ? 5 : -161);
}

class GoalValues {
  final double calories, proteins, fats, carbs, waterMl;
  const GoalValues(this.calories, this.proteins, this.fats, this.carbs, this.waterMl);
  static const fallback = GoalValues(2000, 100, 70, 250, 2000);
}

/// Ориентировочные нормы. Пользователь вправе изменить любое значение.
GoalValues suggestGoals({
  required double bmr,
  required ActivityLevel level,
  required GoalType goal,
  required double weightKg,
}) {
  final tdee = bmr * activityFactor[level]!;
  final kcal = switch (goal) {
    GoalType.lose => tdee * 0.85,
    GoalType.gain => tdee * 1.10,
    GoalType.maintain => tdee,
  };
  final proteins = weightKg * (goal == GoalType.maintain ? 1.6 : 2.0);
  final fats = kcal * 0.25 / 9;
  final carbs = (kcal - proteins * 4 - fats * 9) / 4;
  final water = weightKg * 30;
  return GoalValues(kcal.roundToDouble(), proteins.roundToDouble(),
      fats.roundToDouble(), (carbs < 0 ? 0 : carbs).roundToDouble(),
      (water / 50).round() * 50.0);
}

enum CalorieMode { fixed, dynamic }

/// Режим 1: цель фиксирована. Режим 2: к базовой цели добавляется только та
/// часть активных калорий, что превышает уже учтённую в норме
/// (чтобы не считать активность дважды).
double effectiveCalorieTarget({
  required double base,
  required CalorieMode mode,
  required double activeKcal,
  double includedActiveKcal = 0,
}) {
  if (mode == CalorieMode.fixed) return base;
  final extra = activeKcal - includedActiveKcal;
  return base + (extra > 0 ? extra : 0);
}
