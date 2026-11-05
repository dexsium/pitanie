// Поиск тренировок по пульсу. Чистые функции без доступа к базе: удобно проверять тестами.

class DetectedWorkout {
  final DateTime start, end;
  final double avgHr, maxHr;
  const DetectedWorkout(this.start, this.end, this.avgHr, this.maxHr);

  int get minutes => end.difference(start).inMinutes;
  int get key => start.millisecondsSinceEpoch ~/ 60000;

  Map<String, dynamic> toJson() => {
        's': start.millisecondsSinceEpoch,
        'e': end.millisecondsSinceEpoch,
        'avg': avgHr,
        'max': maxHr,
      };

  factory DetectedWorkout.fromJson(Map<String, dynamic> j) => DetectedWorkout(
      DateTime.fromMillisecondsSinceEpoch(j['s'] as int),
      DateTime.fromMillisecondsSinceEpoch(j['e'] as int),
      (j['avg'] as num).toDouble(),
      (j['max'] as num).toDouble());
}

/// Порог пульса, выше которого считаем, что идёт нагрузка: 45% резерва пульса
/// (пульс покоя + 0.45 × (максимум − покой)), максимум = 220 − возраст.
/// Без пульса покоя берём 60, без возраста 30 лет. Порог не ниже 100 и не выше 150.
double workoutThreshold({int? rest, int? age}) {
  final r = (rest ?? 60).toDouble();
  final maxHr = 220.0 - (age ?? 30);
  return (r + 0.45 * (maxHr - r)).clamp(100.0, 150.0);
}

/// Отрезки, где пульс держится не ниже [threshold] минимум [minMinutes] минут.
/// Провалы короче [maxGapMin] минут (отдых между подходами) отрезок не прерывают.
List<DetectedWorkout> detectWorkouts(
  List<({DateTime t, double bpm})> hr, {
  required double threshold,
  int minMinutes = 10,
  int maxGapMin = 3,
}) {
  final s = [...hr]..sort((a, b) => a.t.compareTo(b.t));
  final out = <DetectedWorkout>[];
  DateTime? start, lastHigh;
  var sum = 0.0, n = 0;
  var mx = 0.0;
  final minutes = <int>{};

  void close() {
    if (start != null && lastHigh != null) {
      final end = lastHigh!.add(const Duration(minutes: 1));
      final span = end.difference(start!).inMinutes;
      if (span >= minMinutes && minutes.length >= minMinutes * 0.6) {
        out.add(DetectedWorkout(start!, end, sum / n, mx));
      }
    }
    start = null;
    lastHigh = null;
    sum = 0;
    n = 0;
    mx = 0;
    minutes.clear();
  }

  for (final x in s) {
    if (x.bpm < threshold) continue;
    if (lastHigh != null && x.t.difference(lastHigh!).inMinutes > maxGapMin) {
      close();
    }
    start ??= x.t;
    lastHigh = x.t;
    sum += x.bpm;
    n++;
    if (x.bpm > mx) mx = x.bpm;
    minutes.add(x.t.millisecondsSinceEpoch ~/ 60000);
  }
  close();
  return out;
}

/// Расход энергии по среднему пульсу (формула Keytel, 2005), ккал.
/// Это оценка: при больших отклонениях от средних людей ошибка заметна.
double workoutKcal(
    {required double avgHr,
    required double weightKg,
    required int age,
    required bool female,
    required int minutes}) {
  final perMin = female
      ? (-20.4022 + 0.4472 * avgHr - 0.1263 * weightKg + 0.074 * age) / 4.184
      : (-55.0969 + 0.6309 * avgHr + 0.1988 * weightKg + 0.2017 * age) / 4.184;
  return perMin <= 0 ? 0 : perMin * minutes;
}
