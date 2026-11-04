import '../../services/health_data_quality_service.dart';
import '../models/health_models.dart';
import 'baseline.dart';

int _minute(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;

class DayHeart {
  final DateTime day;
  final double? resting; // расчётный пульс покоя (по данным часов)
  final double? night; // средний ночной пульс
  final int restingSamples;
  const DayHeart(this.day, this.resting, this.night, this.restingSamples);
}

/// Пульс покоя по минутным значениям часов. Часы отдельное значение «пульс в покое» по этому
/// каналу не передают, поэтому оно рассчитывается: берутся только отсчёты без шагов за
/// предыдущие [quietMin] минут и вне тренировок (+30 мин после них); результат — медиана
/// самых низких 25 % таких отсчётов. Если отсчётов меньше [minSamples], значения нет.
List<DayHeart> dailyHeart(
  List<Sample> hr, {
  required Set<int> stepMinutes,
  required Set<int> sleepMinutes,
  List<(DateTime, DateTime)> workouts = const [],
  int quietMin = 10,
  int minSamples = 40,
  int minNightSamples = 20,
}) {
  final byDay = <DateTime, List<Sample>>{};
  for (final s in cleanHeartRate(hr)) {
    byDay.putIfAbsent(dayOf(s.at), () => []).add(s);
  }
  bool inWorkout(DateTime t) {
    for (final w in workouts) {
      if (!t.isBefore(w.$1) &&
          t.isBefore(w.$2.add(const Duration(minutes: 30)))) return true;
    }
    return false;
  }

  bool recentSteps(int m) {
    for (var k = 0; k <= quietMin; k++) {
      if (stepMinutes.contains(m - k)) return true;
    }
    return false;
  }

  final out = <DayHeart>[];
  final days = byDay.keys.toList()..sort();
  for (final d in days) {
    final qualified = <double>[];
    final night = <double>[];
    for (final s in byDay[d]!) {
      final m = _minute(s.at);
      if (sleepMinutes.contains(m)) night.add(s.v);
      if (!recentSteps(m) && !inWorkout(s.at)) qualified.add(s.v);
    }
    double? resting;
    if (qualified.length >= minSamples) {
      qualified.sort();
      final k = (qualified.length * 0.25).ceil();
      resting = medianOf(qualified.sublist(0, k));
    }
    out.add(DayHeart(
        d,
        resting,
        night.length >= minNightSamples ? meanOf(night) : null,
        qualified.length));
  }
  return out;
}
