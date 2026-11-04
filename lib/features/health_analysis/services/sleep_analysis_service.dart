import '../domain/algorithms/baseline.dart';
import '../domain/models/health_models.dart';

class SleepAnalysis {
  final List<SleepNight> nights;
  final bool lastNightShort;
  final bool shortStreak; // 3 ночи подряд короче порога
  final double? irregularityMin; // разброс времени засыпания за 7 ночей, мин
  final bool irregular;
  final Baseline? baseline;
  final String note;
  const SleepAnalysis({
    required this.nights,
    this.lastNightShort = false,
    this.shortStreak = false,
    this.irregularityMin,
    this.irregular = false,
    this.baseline,
    required this.note,
  });
}

/// Анализ ночного сна. Порог недостаточности задаёт пользователь (по умолчанию 6 ч).
/// «Несколько ночей» = три последние ночи подряд (по дням пробуждения) короче порога.
/// Стадии сна считаются приблизительно и здесь не используются для выводов.
SleepAnalysis analyzeSleep(List<SleepNight> nights, DateTime today,
    {double minHours = 6}) {
  final list = [...nights]..sort((a, b) => a.day.compareTo(b.day));
  final t = dayOf(today);
  final thr = minHours * 60;
  if (list.isEmpty) {
    return const SleepAnalysis(nights: [], note: 'Нет данных о сне.');
  }
  final last = list.last;
  final fresh = !last.day.isBefore(t.subtract(const Duration(days: 1)));
  final lastShort = fresh && last.sleepMin < thr;
  var streak = false;
  if (list.length >= 3) {
    final l3 = list.sublist(list.length - 3);
    final consecutive = l3[2].day.difference(l3[0].day).inDays == 2 &&
        l3[1].day.difference(l3[0].day).inDays == 1 &&
        !l3[2].day.isBefore(t.subtract(const Duration(days: 1)));
    streak = consecutive && l3.every((n) => n.sleepMin < thr);
  }
  // Регулярность: время засыпания относительно 18:00 (чтобы ночь не разрывалась на полуночи).
  final week = [
    for (final n in list)
      if (!n.day.isBefore(t.subtract(const Duration(days: 6)))) n
  ];
  double? irr;
  if (week.length >= 5) {
    irr = stdDev([
      for (final n in week)
        ((n.start.hour * 60 + n.start.minute) - 18 * 60 + 24 * 60) %
            (24 * 60).toDouble()
    ]);
  }
  final base =
      buildBaseline([for (final n in list) n.sleepMin.toDouble()], minN: 14);
  return SleepAnalysis(
      nights: list,
      lastNightShort: lastShort,
      shortStreak: streak,
      irregularityMin: irr,
      irregular: irr != null && irr > 90,
      baseline: base,
      note: streak
          ? 'Несколько ночей короче порога'
          : lastShort
              ? 'Последняя ночь короче порога'
              : 'Продолжительность в пределах привычной');
}
