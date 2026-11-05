// Расчёты силовых тренировок. Чистые функции, без доступа к базе.

class SetData {
  final int reps;
  final double? weightKg;
  const SetData(this.reps, this.weightKg);
}

/// Оценка одноповторного максимума по формуле Эпли: вес × (1 + повторения / 30).
/// Только для внешнего веса и 1–12 повторений: на больших сериях оценка ненадёжна.
/// Для собственного веса без отягощения и для 0 кг возвращает null.
double? estimated1Rm(double? weightKg, int reps, {int maxReps = 12}) {
  if (weightKg == null || weightKg <= 0) return null;
  if (reps < 1 || reps > maxReps) return null;
  return reps == 1 ? weightKg : weightKg * (1 + reps / 30);
}

/// Тоннаж: сумма вес × повторения по подходам с весом. Подходы без веса не добавляют ничего.
double volumeKg(Iterable<SetData> sets) {
  var v = 0.0;
  for (final s in sets) {
    if (s.weightKg != null && s.weightKg! > 0) v += s.weightKg! * s.reps;
  }
  return v;
}

int totalReps(Iterable<SetData> sets) => sets.fold(0, (a, s) => a + s.reps);

/// Максимальный фактический рабочий вес (не оценка).
double? maxWeight(Iterable<SetData> sets) {
  double? m;
  for (final s in sets) {
    final w = s.weightKg;
    if (w != null && w > 0 && (m == null || w > m)) m = w;
  }
  return m;
}

/// Лучшая оценка 1ПМ среди подходов.
double? best1Rm(Iterable<SetData> sets) {
  double? m;
  for (final s in sets) {
    final e = estimated1Rm(s.weightKg, s.reps);
    if (e != null && (m == null || e > m)) m = e;
  }
  return m;
}

/// Итоги одной тренировки по одному упражнению (точка для графика прогресса).
class ExercisePoint {
  final DateTime date;
  final int sets, reps;
  final double volume;
  final double? maxWeight, est1Rm;
  const ExercisePoint(this.date, this.sets, this.reps, this.volume,
      this.maxWeight, this.est1Rm);
}

ExercisePoint exercisePoint(DateTime date, List<SetData> sets) => ExercisePoint(
    date,
    sets.length,
    totalReps(sets),
    volumeKg(sets),
    maxWeight(sets),
    best1Rm(sets));

/// Изменение между первой и последней точками ряда в процентах; null, если точек
/// меньше двух или начальное значение не положительное.
double? changePercent(List<double> values) {
  if (values.length < 2 || values.first <= 0) return null;
  return (values.last - values.first) / values.first * 100;
}
