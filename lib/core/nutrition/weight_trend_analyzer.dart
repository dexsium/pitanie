import 'nutrition_calculation_models.dart';

const kMinPlausibleKg = 25.0;
const kMaxPlausibleKg = 350.0;

/// Правдоподобное значение массы взрослого.
bool isPlausibleWeight(double kg) =>
    kg >= kMinPlausibleKg && kg <= kMaxPlausibleKg;

/// Резкое изменение: более 3 кг относительно последнего значения за ≤ 2 суток,
/// либо более 5 % массы за ≤ 7 суток. Такое значение стоит подтвердить.
bool isSuddenChange(
    {required double previousKg,
    required Duration since,
    required double newKg}) {
  final d = (newKg - previousKg).abs();
  if (since.inHours <= 48 && d > 3) return true;
  if (since.inDays <= 7 && previousKg > 0 && d / previousKg > 0.05) return true;
  return false;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Анализ тренда массы. Несколько взвешиваний за день усредняются; тренд — оценка
/// Тейла — Сена (медиана попарных наклонов), устойчивая к единичным выбросам
/// (вода, соль, гликоген, время взвешивания).
WeightTrend analyzeWeightTrend(
  List<WeightPoint> points,
  DateTime now, {
  int windowDays = 28,
  int minDays = 14,
  int minDistinctDays = 6,
}) {
  final today = _day(now);
  final from = today.subtract(Duration(days: windowDays - 1));
  final byDay = <DateTime, List<double>>{};
  var n = 0;
  for (final p in points) {
    final d = _day(p.at);
    if (d.isBefore(from) || d.isAfter(today) || !isPlausibleWeight(p.kg))
      continue;
    byDay.putIfAbsent(d, () => []).add(p.kg);
    n++;
  }
  if (byDay.isEmpty) {
    return const WeightTrend(
        reliable: false, reason: 'Нет измерений веса за последние 4 недели.');
  }
  final days = byDay.keys.toList()..sort();
  final avg = [
    for (final d in days) byDay[d]!.reduce((a, b) => a + b) / byDay[d]!.length
  ];
  final recentFrom = today.subtract(const Duration(days: 6));
  final recent = [
    for (var i = 0; i < days.length; i++)
      if (!days[i].isBefore(recentFrom)) avg[i]
  ];
  final smoothed = recent.isEmpty
      ? avg.last
      : recent.reduce((a, b) => a + b) / recent.length;
  final span = days.last.difference(days.first).inDays + 1;
  if (days.length < minDistinctDays || span < minDays) {
    return WeightTrend(
        reliable: false,
        smoothedKg: smoothed,
        measurements: n,
        days: span,
        reason:
            'Для тренда нужно не менее $minDays дней наблюдений и $minDistinctDays дней '
            'с взвешиванием (сейчас: $span дн., ${days.length} взвешиваний).');
  }
  final slopes = <double>[];
  for (var i = 0; i < days.length; i++) {
    for (var j = i + 1; j < days.length; j++) {
      final dd = days[j].difference(days[i]).inDays;
      if (dd >= 3) slopes.add((avg[j] - avg[i]) / dd);
    }
  }
  if (slopes.isEmpty) {
    return WeightTrend(
        reliable: false,
        smoothedKg: smoothed,
        measurements: n,
        days: span,
        reason: 'Взвешивания слишком близки по времени для оценки тренда.');
  }
  return WeightTrend(
      reliable: true,
      smoothedKg: smoothed,
      kgPerWeek: _median(slopes) * 7,
      measurements: n,
      days: span);
}
