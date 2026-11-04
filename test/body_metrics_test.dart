import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/body/body_metrics.dart';

// Ожидаемые значения получены независимой перепиской формул на Python (не запуском оригинала):
// тест ловит опечатки и расхождения в порте. Формулы — оценка, а не измерение.
void main() {
  final cases = <(BodyInput, Map<String, double>, int)>[
    (BodyInput(weight: 69.5, height: 175.0, age: 35, female: false, impedance: 500.0),
        {'bmi': 22.693877551020407, 'fat': 19.26744604316546, 'water': 55.38253201438848, 'bone': 2.8552037275, 'muscle': 53.25392127250001, 'visceral': 10.14875, 'bmr': 1473.252, 'protein': 21.24181514028779, 'bodyAge': 27.64714999999999, 'score': 79.85125}, 4),
    (BodyInput(weight: 69.5, height: 175.0, age: 35, female: false, impedance: 420.0),
        {'bmi': 22.693877551020407, 'fat': 18.484712230215827, 'water': 55.919487410071945, 'bone': 2.8832632475, 'muscle': 53.769861752500006, 'visceral': 10.14875, 'bmr': 1473.252, 'protein': 21.44722014748202, 'bodyAge': 23.51114999999999, 'score': 89.85125}, 4),
    (BodyInput(weight: 55.0, height: 162.0, age: 28, female: true, impedance: 520.0),
        {'bmi': 20.957171162932475, 'fat': 28.55597236363637, 'water': 49.01060295854544, 'bone': 2.3582196060159997, 'muscle': 36.935995593983996, 'visceral': 1, 'bmr': 1188.36168, 'protein': 18.145752666880007, 'bodyAge': 23.695799999999977, 'score': 100.0}, 4),
    (BodyInput(weight: 82.3, height: 180.0, age: 47, female: false, impedance: 480.0),
        {'bmi': 25.40123456790123, 'fat': 25.518201701093556, 'water': 51.094513633049814, 'bone': 3.1228727216, 'muscle': 58.1756472784, 'visceral': 17.048499999999997, 'bmr': 1552.8348, 'protein': 19.592785611664652, 'bodyAge': 39.62453, 'score': 55.0688482308627}, 1),
    (BodyInput(weight: 48.0, height: 158.0, age: 52, female: true, impedance: 600.0),
        {'bmi': 19.227687870533565, 'fat': 23.393768699999974, 'water': 52.55187467180001, 'bone': 1.8877225320960005, 'muscle': 34.88326849190401, 'visceral': 1, 'bmr': 969.6139200000002, 'protein': 20.121601353000017, 'bodyAge': 31.509, 'score': 100.0}, 7),
    (BodyInput(weight: 95.0, height: 185.0, age: 61, female: false, impedance: 400.0),
        {'bmi': 27.757487216946675, 'fat': 29.683363157894725, 'water': 50.206078705263174, 'bone': 3.4066805819000003, 'muscle': 63.39412441810001, 'visceral': 24.0075, 'bmr': 1612.9739999999997, 'protein': 16.52457857694737, 'bodyAge': 49.245099999999994, 'score': 44.63574954336846}, 2),
    (BodyInput(weight: 62.0, height: 170.0, age: 17, female: true, impedance: 550.0),
        {'bmi': 21.453287197231838, 'fat': 29.297259458064527, 'water': 50.481756746941926, 'bone': 2.6180798935999996, 'muscle': 41.21761924239999, 'visceral': 1, 'bmr': 1324.8839999999998, 'protein': 15.998274289187094, 'bodyAge': 21.981099999999998, 'score': 94.99856190765591}, 4),
  ];

  test('порт формул совпадает с независимой переписью на семи наборах', () {
    for (final (inp, exp, type) in cases) {
      final m = BodyMetrics.compute(inp)!;
      expect(m.bmi, closeTo(exp['bmi']!, 1e-9));
      expect(m.fat, closeTo(exp['fat']!, 1e-9));
      expect(m.water, closeTo(exp['water']!, 1e-9));
      expect(m.bone, closeTo(exp['bone']!, 1e-9));
      expect(m.muscle, closeTo(exp['muscle']!, 1e-9));
      expect(m.visceral, closeTo(exp['visceral']!, 1e-9));
      expect(m.bmr, closeTo(exp['bmr']!, 1e-9));
      expect(m.protein, closeTo(exp['protein']!, 1e-9));
      expect(m.bodyAge, closeTo(exp['bodyAge']!, 1e-9));
      expect(m.score, closeTo(exp['score']!, 1e-9));
      expect(m.bodyType, type);
    }
  });

  test('невозможные входные данные отклоняются', () {
    BodyInput inp({double w = 70, double h = 175, int a = 35, double imp = 500}) =>
        BodyInput(weight: w, height: h, age: a, female: false, impedance: imp);
    expect(BodyMetrics.compute(inp(imp: 0)), isNull);
    expect(BodyMetrics.compute(inp(imp: 3500)), isNull);
    expect(BodyMetrics.compute(inp(h: 230)), isNull);
    expect(BodyMetrics.compute(inp(w: 5)), isNull);
    expect(BodyMetrics.compute(inp(a: 120)), isNull);
    expect(BodyMetrics.compute(inp()), isNotNull);
  });

  test('значения остаются в допустимых пределах на сетке входных данных', () {
    for (final female in [false, true]) {
      for (var w = 40.0; w <= 130; w += 15) {
        for (var h = 150.0; h <= 200; h += 12) {
          for (final age in [8, 20, 35, 55, 75]) {
            for (final imp in [250.0, 500.0, 800.0]) {
              final m = BodyMetrics.compute(
                  BodyInput(weight: w, height: h, age: age, female: female, impedance: imp));
              if (m == null) continue;
              expect(m.fat, inInclusiveRange(5, 75));
              expect(m.water, inInclusiveRange(35, 75));
              expect(m.bone, inInclusiveRange(0.5, 8));
              expect(m.muscle, inInclusiveRange(10, 120));
              expect(m.visceral, inInclusiveRange(1, 50));
              expect(m.protein, inInclusiveRange(5, 32));
              expect(m.bodyAge, inInclusiveRange(15, 80));
              expect(m.score, inInclusiveRange(0, 100));
              expect(m.bodyType, inInclusiveRange(0, 8));
            }
          }
        }
      }
    }
  });

  test('диапазоны нормы и категория ИМТ', () {
    final m = BodyMetrics.compute(const BodyInput(
        weight: 69.5, height: 175, age: 35, female: false, impedance: 500))!;
    expect(m.fatRange.lo, 11);
    expect(m.fatRange.hi, 22);
    expect(m.visceralRange.hi, 9);
    expect(m.proteinRange.lo, 16);
    expect(m.fatRange.of(5), Level.low);
    expect(m.fatRange.of(15), Level.normal);
    expect(m.fatRange.of(30), Level.high);
    expect(bmiCategory(17), 'Дефицит');
    expect(bmiCategory(22.7), 'Норма');
    expect(bmiCategory(27), 'Избыток');
    expect(bmiCategory(31), 'Ожирение');
    expect(bmiOf(70, 175), closeTo(22.857, 0.001));
    expect(bmiOf(70, null), isNull);
  });
}
