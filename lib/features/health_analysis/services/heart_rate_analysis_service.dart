import '../domain/algorithms/baseline.dart';
import '../domain/models/health_models.dart';

class HeartAnalysis {
  final Baseline? baseline;
  final List<DailyValue> recent; // последние до 3 дней с данными
  final bool persistentHigh;
  final double? weekDelta; // средний покой за 7 дней − за предыдущие 7, уд/мин
  final DateTime? lastDay;
  final String note;
  const HeartAnalysis({
    this.baseline,
    this.recent = const [],
    this.persistentHigh = false,
    this.weekDelta,
    this.lastDay,
    required this.note,
  });
}

/// Устойчивое повышение пульса покоя относительно личной нормы.
/// База — 14–28 дней достоверных значений без последних трёх дней. «Устойчиво» = каждое из трёх
/// последних дней с данными выше медианы на max(minDelta, 2,5 × разброс). Одно высокое значение
/// отклонением не считается.
HeartAnalysis analyzeHeartRate(List<DailyValue> resting, DateTime today,
    {double minDelta = 5}) {
  final t = dayOf(today);
  final vals = [...resting]..sort((a, b) => a.day.compareTo(b.day));
  if (vals.isEmpty) {
    return const HeartAnalysis(note: 'Нет достоверных значений пульса покоя.');
  }
  final within5 = vals
      .where((v) => !v.day.isBefore(t.subtract(const Duration(days: 4))))
      .toList();
  final recent =
      within5.length >= 3 ? within5.sublist(within5.length - 3) : within5;
  final cutoff = recent.isEmpty ? t : recent.first.day;
  final base = buildBaseline([
    for (final v in vals)
      if (!v.day.isBefore(t.subtract(const Duration(days: 27))) &&
          v.day.isBefore(cutoff))
        v.v
  ]);
  double? weekDelta;
  final w1 = [
    for (final v in vals)
      if (!v.day.isBefore(t.subtract(const Duration(days: 6)))) v.v
  ];
  final w0 = [
    for (final v in vals)
      if (!v.day.isBefore(t.subtract(const Duration(days: 13))) &&
          v.day.isBefore(t.subtract(const Duration(days: 6))))
        v.v
  ];
  if (w1.length >= 4 && w0.length >= 4) weekDelta = meanOf(w1) - meanOf(w0);
  if (base == null) {
    return HeartAnalysis(
        recent: recent,
        weekDelta: weekDelta,
        lastDay: vals.last.day,
        note:
            'Личная норма пока не сформирована: нужно не менее 14 дней достоверных значений '
            '(сейчас ${vals.length}).');
  }
  final thr = base.median +
      (2.5 * base.spread > minDelta ? 2.5 * base.spread : minDelta);
  final high = recent.length >= 3 && recent.every((v) => v.v > thr);
  return HeartAnalysis(
      baseline: base,
      recent: recent,
      persistentHigh: high,
      weekDelta: weekDelta,
      lastDay: vals.last.day,
      note: high ? 'Устойчиво выше личной нормы' : 'В пределах личной нормы');
}
