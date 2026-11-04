import '../domain/algorithms/baseline.dart';
import '../domain/models/health_models.dart';

class HrvAnalysis {
  final bool available; // есть ли вообще HRV от часов
  final HrvMetric? metric;
  final Baseline? baseline;
  final bool lowStreak;
  final double? latest;
  final int nights;
  final bool
      mixedMetrics; // в данных есть несколько типов — анализируется только один
  final String note;
  const HrvAnalysis({
    required this.available,
    this.metric,
    this.baseline,
    this.lowStreak = false,
    this.latest,
    this.nights = 0,
    this.mixedMetrics = false,
    required this.note,
  });
}

String hrvMetricLabel(HrvMetric m) => switch (m) {
      HrvMetric.rmssd => 'RMSSD',
      HrvMetric.sdnn => 'SDNN',
      HrvMetric.unknown => 'тип не указан',
    };

/// Анализ ночной HRV относительно собственной базовой линии (≥14 ночей).
/// Значения разных типов (RMSSD/SDNN/неизвестный) никогда не смешиваются: берётся тип с большим
/// числом ночей. Абсолютные нормативы не используются; «больше HRV = здоровее» не предполагается.
HrvAnalysis analyzeHrv(List<HrvSample> samples, DateTime today) {
  if (samples.isEmpty) {
    return const HrvAnalysis(
        available: false,
        note: 'Часы по текущему каналу HRV не передают, анализ идёт без неё.');
  }
  final byMetric = <HrvMetric, Map<DateTime, List<double>>>{};
  for (final s in samples) {
    if (s.v <= 0 || s.v > 400) continue; // недостоверные значения
    byMetric
        .putIfAbsent(s.metric, () => {})
        .putIfAbsent(dayOf(s.at), () => [])
        .add(s.v);
  }
  if (byMetric.isEmpty) {
    return const HrvAnalysis(
        available: false, note: 'Нет достоверных значений HRV.');
  }
  final main = byMetric.entries
      .reduce((a, b) => a.value.length >= b.value.length ? a : b);
  final days = main.value.keys.toList()..sort();
  final nightly = [for (final d in days) DailyValue(d, meanOf(main.value[d]!))];
  final t = dayOf(today);
  final recent = nightly
      .where((v) => !v.day.isBefore(t.subtract(const Duration(days: 4))))
      .toList();
  final last3 = recent.length >= 3 ? recent.sublist(recent.length - 3) : recent;
  final cutoff = last3.isEmpty ? t : last3.first.day;
  final base = buildBaseline([
    for (final v in nightly)
      if (!v.day.isBefore(t.subtract(const Duration(days: 27))) &&
          v.day.isBefore(cutoff))
        v.v
  ]);
  final mixed = byMetric.length > 1;
  if (base == null) {
    return HrvAnalysis(
        available: true,
        metric: main.key,
        latest: nightly.last.v,
        nights: nightly.length,
        mixedMetrics: mixed,
        note:
            'Личный диапазон HRV пока не сформирован: нужно не менее 14 ночей '
            '(сейчас ${nightly.length}).');
  }
  final drop = 2 * base.spread > 0.15 * base.median
      ? 2 * base.spread
      : 0.15 * base.median;
  final low = last3.length >= 3 && last3.every((v) => v.v < base.median - drop);
  return HrvAnalysis(
      available: true,
      metric: main.key,
      baseline: base,
      lowStreak: low,
      latest: nightly.last.v,
      nights: nightly.length,
      mixedMetrics: mixed,
      note: low
          ? 'Несколько ночей ниже личного диапазона'
          : 'В пределах личного диапазона');
}
