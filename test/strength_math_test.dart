import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/training/strength_math.dart';

void main() {
  test('Эпли: 100 кг × 5 = 116.7, один повтор = рабочий вес', () {
    expect(estimated1Rm(100, 5), closeTo(116.67, 0.01));
    expect(estimated1Rm(100, 1), 100);
  });

  test('Эпли не применяется к длинным сериям, нулевому и пустому весу', () {
    expect(estimated1Rm(40, 20), isNull);
    expect(estimated1Rm(0, 5), isNull);
    expect(estimated1Rm(null, 5), isNull);
  });

  test('тоннаж считает только подходы с весом', () {
    final sets = [
      const SetData(10, 50),
      const SetData(8, 60),
      const SetData(12, null)
    ];
    expect(volumeKg(sets), 50 * 10 + 60 * 8);
    expect(totalReps(sets), 30);
    expect(maxWeight(sets), 60);
  });

  test('собственный вес без отягощения не даёт веса, тоннажа и 1ПМ', () {
    final sets = [const SetData(12, null), const SetData(10, 0)];
    expect(volumeKg(sets), 0);
    expect(maxWeight(sets), isNull);
    expect(best1Rm(sets), isNull);
  });

  test('точка прогресса и изменение в процентах', () {
    final p = exercisePoint(
        DateTime(2026, 11, 5), [const SetData(5, 100), const SetData(5, 90)]);
    expect(p.sets, 2);
    expect(p.volume, 950);
    expect(p.maxWeight, 100);
    expect(p.est1Rm, closeTo(116.67, 0.01));
    expect(changePercent([100, 110]), closeTo(10, 0.001));
    expect(changePercent([100]), isNull);
    expect(changePercent([0, 5]), isNull);
  });
}
