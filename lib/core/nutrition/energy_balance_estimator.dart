import 'nutrition_calculation_models.dart';

/// Приближённый энергетический эквивалент изменения массы, ккал/кг.
/// Не постоянная величина: зависит от воды, гликогена и состава тела.
const kEnergyPerKg = 7700.0;

/// EstimatedTDEE ≈ средний приём − 7700 × изменение массы в сутки.
/// Возвращает null без достоверного тренда и без полноценного дневника питания
/// (иначе «расход» был бы вымышлен). Оценка ограничена диапазоном 0,8–1,3 от формульного TDEE.
EnergyEstimate estimateTdee({
  required WeightTrend trend,
  required List<double>
      dailyIntakeKcal, // по дням периода, 0 — питание не вёлся
  required int observedDays,
  required double formulaTdee,
}) {
  if (!trend.reliable || trend.kgPerWeek == null) {
    return EnergyEstimate(
        null, Confidence.none, trend.reason ?? 'Нет достоверного тренда веса.');
  }
  final logged = dailyIntakeKcal.where((v) => v >= 800).toList();
  final coverage = observedDays <= 0 ? 0.0 : logged.length / observedDays;
  if (logged.length < 10 || coverage < 0.7) {
    return const EnergyEstimate(
        null,
        Confidence.none,
        'Дневник питания заполнен не полностью: для оценки реального расхода нужно не менее '
        '10 дней и около 70 % дней периода.');
  }
  final avg = logged.reduce((a, b) => a + b) / logged.length;
  final raw = avg - kEnergyPerKg * trend.kgPerWeek! / 7;
  final clamped = raw.clamp(formulaTdee * 0.8, formulaTdee * 1.3).toDouble();
  final conf =
      trend.days >= 21 && coverage >= 0.85 ? Confidence.medium : Confidence.low;
  return EnergyEstimate(
      clamped,
      conf,
      raw == clamped
          ? null
          : 'Оценка ограничена разумным диапазоном около формульного TDEE.');
}
