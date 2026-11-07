import 'nutrition_calculation_models.dart';
import 'weight_trend_analyzer.dart';

/// Состояние оценки срока достижения целевого веса.
enum GoalEtaStatus {
  /// Цель не задана.
  noTarget,

  /// Нет ни одного взвешивания.
  noData,

  /// Цель уже достигнута (в пределах допуска или пройдена в нужную сторону).
  reached,

  /// Данных мало: оценка срока невозможна.
  tooFewData,

  /// Вес стоит на месте или идёт в сторону от цели.
  notApproaching,

  /// Срок посчитан.
  ok,
}

class GoalEta {
  final GoalEtaStatus status;

  /// Сглаженный текущий вес, кг.
  final double? currentKg;

  /// Сколько осталось до цели, кг (со знаком: минус — нужно сбросить).
  final double? remainingKg;

  /// Темп изменения, кг в неделю (со знаком).
  final double? kgPerWeek;

  /// Оценка числа дней до цели и ожидаемая дата.
  final int? days;
  final DateTime? date;

  /// Оценка по менее надёжному ряду (мало дней наблюдений).
  final bool approximate;

  /// Пояснение для пользователя.
  final String message;

  const GoalEta(this.status, this.message,
      {this.currentKg,
      this.remainingKg,
      this.kgPerWeek,
      this.days,
      this.date,
      this.approximate = false});
}

/// Допуск, в котором цель считается достигнутой, кг.
const kGoalToleranceKg = 0.3;

/// Дольше этого срока оценку не показываем как дату: она ничего не значит.
const kMaxEtaDays = 730;

/// Минимальный значимый темп, кг/нед: меньше — вес фактически стоит.
const kMinMeaningfulKgPerWeek = 0.05;

/// Оценка срока достижения целевого веса по тренду взвешиваний.
///
/// Тренд берётся из [analyzeWeightTrend]: сначала строгий (28 дней, не менее 14 дней
/// наблюдений), при нехватке данных — облегчённый (до 8 недель, от 7 дней и трёх дней
/// с взвешиванием), такая оценка помечается как приблизительная. Срок считается
/// как «осталось / темп» и не является прогнозом: он предполагает, что темп сохранится.
GoalEta estimateGoalEta(
    List<WeightPoint> points, double? targetKg, DateTime now) {
  if (targetKg == null) {
    return const GoalEta(GoalEtaStatus.noTarget, 'Целевой вес не задан.');
  }
  final valid = [
    for (final p in points)
      if (isPlausibleWeight(p.kg) && !p.at.isAfter(now)) p
  ]..sort((a, b) => a.at.compareTo(b.at));
  if (valid.isEmpty) {
    return const GoalEta(GoalEtaStatus.noData, 'Добавьте первое взвешивание.');
  }

  var trend = analyzeWeightTrend(valid, now);
  var approximate = false;
  if (!trend.reliable) {
    final loose = analyzeWeightTrend(valid, now,
        windowDays: 56, minDays: 7, minDistinctDays: 3);
    if (loose.reliable) {
      trend = loose;
      approximate = true;
    }
  }
  final current = trend.smoothedKg ?? valid.last.kg;
  final remaining = targetKg - current;

  // Цель достигнута: в допуске или последнее взвешивание уже по ту сторону цели.
  final startedAbove = valid.first.kg > targetKg;
  final last = valid.last.kg;
  final crossed = startedAbove ? last <= targetKg : last >= targetKg;
  if (remaining.abs() <= kGoalToleranceKg || crossed) {
    return GoalEta(GoalEtaStatus.reached, 'Целевой вес достигнут.',
        currentKg: current, remainingKg: remaining);
  }

  final rate = trend.reliable ? trend.kgPerWeek : null;
  if (rate == null) {
    return GoalEta(
        GoalEtaStatus.tooFewData,
        trend.reason ??
            'Нужно больше взвешиваний: для оценки срока нужны наблюдения хотя бы за неделю.',
        currentKg: current,
        remainingKg: remaining);
  }
  final towardsTarget = rate * remaining > 0;
  if (!towardsTarget || rate.abs() < kMinMeaningfulKgPerWeek) {
    return GoalEta(
        GoalEtaStatus.notApproaching,
        rate.abs() < kMinMeaningfulKgPerWeek
            ? 'Вес почти не меняется, срок достижения цели оценить нельзя.'
            : 'Вес сейчас идёт в сторону от цели, срок оценить нельзя.',
        currentKg: current,
        remainingKg: remaining,
        kgPerWeek: rate,
        approximate: approximate);
  }
  final weeks = remaining / rate;
  final days = (weeks * 7).ceil();
  if (days > kMaxEtaDays) {
    return GoalEta(
        GoalEtaStatus.notApproaching,
        'При текущем темпе цель дальше чем через два года.',
        currentKg: current,
        remainingKg: remaining,
        kgPerWeek: rate,
        approximate: approximate);
  }
  final d = DateTime(now.year, now.month, now.day).add(Duration(days: days));
  return GoalEta(GoalEtaStatus.ok, '',
      currentKg: current,
      remainingKg: remaining,
      kgPerWeek: rate,
      days: days,
      date: d,
      approximate: approximate);
}
