import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/workout_detector.dart';

void main() {
  final t0 = DateTime(2026, 11, 5, 18, 0);
  List<({DateTime t, double bpm})> series(List<double> v) => [
        for (var i = 0; i < v.length; i++)
          (t: t0.add(Duration(minutes: i)), bpm: v[i])
      ];

  test('порог зависит от пульса покоя и возраста', () {
    final t = workoutThreshold(rest: 58, age: 30);
    expect(t, inInclusiveRange(115, 125));
    expect(workoutThreshold(), inInclusiveRange(100, 150));
  });

  test('находит отрезок с высоким пульсом и считает среднее и максимум', () {
    final v = [70, 72, ...List.filled(20, 130.0), 135, 70, 68];
    final r = detectWorkouts(series(v.map((e) => e.toDouble()).toList()),
        threshold: 115);
    expect(r.length, 1);
    expect(r.first.minutes, greaterThanOrEqualTo(20));
    expect(r.first.maxHr, 135);
  });

  test('короткий отдых между подходами не разрывает тренировку', () {
    final v = <double>[
      ...List.filled(8, 130),
      100,
      100,
      ...List.filled(8, 132),
    ];
    expect(detectWorkouts(series(v), threshold: 115).length, 1);
  });

  test('короткий всплеск пульса тренировкой не считается', () {
    final v = <double>[70, ...List.filled(4, 140), 70, 70];
    expect(detectWorkouts(series(v), threshold: 115), isEmpty);
  });

  test('ккал по пульсу положительны и растут с пульсом', () {
    double k(double hr) => workoutKcal(
        avgHr: hr, weightKg: 80, age: 30, female: false, minutes: 30);
    expect(k(120), greaterThan(0));
    expect(k(140), greaterThan(k(120)));
  });
}
