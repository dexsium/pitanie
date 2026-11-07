import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/nutrition/goal_eta.dart';
import 'package:pitanie/core/nutrition/nutrition_calculation_models.dart';
import 'package:pitanie/features/weight/weight_page.dart' show etaSpan;

void main() {
  final now = DateTime(2026, 11, 8, 12);

  /// Ряд из [days] дней, заканчивающийся сегодня: вес линейно меняется на [perDay] в день.
  List<WeightPoint> series(int days, double endKg, double perDay) => [
        for (var i = days - 1; i >= 0; i--)
          WeightPoint(now.subtract(Duration(days: i)), endKg - perDay * i)
      ];

  test('цель не задана', () {
    final e = estimateGoalEta(series(20, 80, 0), null, now);
    expect(e.status, GoalEtaStatus.noTarget);
  });

  test('нет взвешиваний', () {
    final e = estimateGoalEta(const [], 70, now);
    expect(e.status, GoalEtaStatus.noData);
  });

  test('снижение: срок = осталось / темп', () {
    // Худеет на 0.05 кг в день (0.35 кг/нед), сейчас 80, цель 77.
    final pts = series(28, 80, -0.05);
    final e = estimateGoalEta(pts, 77, now);
    expect(e.status, GoalEtaStatus.ok);
    expect(e.kgPerWeek!, closeTo(-0.35, 0.02));
    // осталось около 3 кг (сглаженный вес чуть выше текущего), примерно 60 дней
    expect(e.days!, inInclusiveRange(55, 75));
    expect(e.date!.isAfter(now), isTrue);
    expect(e.approximate, isFalse);
  });

  test('набор массы: цель выше текущего веса', () {
    final pts = series(28, 60, 0.05);
    final e = estimateGoalEta(pts, 62, now);
    expect(e.status, GoalEtaStatus.ok);
    expect(e.kgPerWeek!, greaterThan(0));
    expect(e.remainingKg!, greaterThan(0));
  });

  test('вес идёт от цели: срока нет', () {
    final pts = series(28, 82, 0.05); // растёт, а цель ниже
    final e = estimateGoalEta(pts, 75, now);
    expect(e.status, GoalEtaStatus.notApproaching);
    expect(e.days, isNull);
  });

  test('вес стоит на месте: срока нет', () {
    final e = estimateGoalEta(series(28, 80, 0), 75, now);
    expect(e.status, GoalEtaStatus.notApproaching);
  });

  test('цель достигнута: в допуске и после пересечения', () {
    expect(estimateGoalEta(series(28, 75.1, -0.05), 75, now).status,
        GoalEtaStatus.reached);
    // Начинал выше цели, последнее взвешивание уже ниже.
    final below = [
      WeightPoint(now.subtract(const Duration(days: 20)), 80),
      WeightPoint(now.subtract(const Duration(days: 10)), 77),
      WeightPoint(now, 74),
    ];
    expect(estimateGoalEta(below, 75, now).status, GoalEtaStatus.reached);
  });

  test('мало данных: срок не называется', () {
    final pts = [
      WeightPoint(now.subtract(const Duration(days: 1)), 80),
      WeightPoint(now, 79.9),
    ];
    final e = estimateGoalEta(pts, 75, now);
    expect(e.status, GoalEtaStatus.tooFewData);
    expect(e.days, isNull);
  });

  test('короткий, но достаточный ряд помечается как приблизительный', () {
    // 9 дней наблюдений: строгий тренд (14 дней) недоступен, облегчённый — доступен.
    final e = estimateGoalEta(series(9, 80, -0.07), 77, now);
    expect(e.status, GoalEtaStatus.ok);
    expect(e.approximate, isTrue);
  });

  test('слишком далёкая цель не превращается в дату', () {
    final e = estimateGoalEta(series(28, 80, -0.01), 60, now);
    expect(e.status, GoalEtaStatus.notApproaching);
    expect(e.date, isNull);
  });

  test('пересчёт при новом взвешивании', () {
    final base = series(28, 80, -0.05);
    final before = estimateGoalEta(base, 77, now);
    // Резкое улучшение: ещё одно взвешивание заметно ниже
    final more = [...base, WeightPoint(now, 78.5)];
    final after = estimateGoalEta(more, 77, now);
    expect(after.remainingKg!.abs(), lessThan(before.remainingKg!.abs()));
  });

  test('подпись срока', () {
    expect(etaSpan(10), '10 дн.');
    expect(etaSpan(60), '≈ 9 нед.');
    expect(etaSpan(200), '≈ 7 мес.');
  });
}
