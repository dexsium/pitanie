import '../nutrition.dart' show GoalType;
import 'nutrition_calculation_models.dart';

/// Стартовые значения белка, г на кг текущей массы.
double defaultProteinPerKg(GoalType g) => switch (g) {
      GoalType.gain => 2.0,
      GoalType.lose =>
        2.0, // при дефиците белок помогает удерживать мышечную массу
      GoalType.maintain => 1.6,
    };

const kDefaultFatPerKg = 0.9;
const kMinFatPerKg = 0.8;

/// Белок и жир считаются от текущей массы, углеводы — остаток:
/// Carbs = (Target − Protein·4 − Fat·9) / 4.
/// Если калорий не хватает, сначала жир снижается до 0,8 г/кг, затем углеводы обнуляются
/// и добавляется предупреждение; отрицательных значений не бывает.
MacroPlan calcMacros({
  required double targetCalories,
  required double weightKg,
  required GoalType goal,
  double? proteinPerKg,
  double? fatPerKg,
}) {
  final warnings = <String>[];
  final protein = weightKg * (proteinPerKg ?? defaultProteinPerKg(goal));
  var fat = weightKg * (fatPerKg ?? kDefaultFatPerKg);
  var carbs = (targetCalories - protein * 4 - fat * 9) / 4;
  if (carbs < 0) {
    final minFat = weightKg * kMinFatPerKg;
    if (fat > minFat) {
      fat = minFat;
      carbs = (targetCalories - protein * 4 - fat * 9) / 4;
    }
  }
  if (carbs < 0) {
    final need = protein * 4 + fat * 9;
    warnings.add(
        'Калорий ${targetCalories.round()} не хватает на выбранные белок и жир '
        '(нужно не менее ${need.ceil()} ккал). Углеводы поставлены в 0: '
        'увеличьте калорийность или снизьте норму белка.');
    carbs = 0;
  }
  if (targetCalories > 0 && fat * 9 / targetCalories < 0.20) {
    warnings.add(
        'Доля жиров ниже 20 % калорий: проверьте, достаточно ли жиров в рационе.');
  }
  return MacroPlan(targetCalories, protein, fat, carbs, warnings);
}
