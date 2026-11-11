import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/health_integration/health_service.dart';

void main() {
  test('пульс за интервал: среднее и максимум только по нужному источнику, границы включены', () {
    final i = HeartRateIndex()
      ..add('watch', 5000, 150)
      ..add('watch', 1000, 60)
      ..add('watch', 3000, 100)
      ..add('watch', 2000, 80)
      ..add('phone', 2500, 200);
    i.freeze();
    final r = i.between('watch', 2000, 3000)!;
    expect(r.avg, 90);
    expect(r.max, 100);
    expect(i.between('watch', 1000, 5000)!.max, 150);
    expect(i.between('watch', 3001, 4999), isNull, reason: 'в интервале точек нет');
    expect(i.between('unknown', 0, 9999), isNull);
    expect(i.between('phone', 0, 9999)!.avg, 200);
  });

  test('большой объём: выборка не перебирает все точки', () {
    final i = HeartRateIndex();
    for (var t = 0; t < 200000; t++) {
      i.add('w', t * 5000, 60.0 + t % 100);
    }
    i.freeze();
    final sw = Stopwatch()..start();
    for (var k = 0; k < 500; k++) {
      i.between('w', k * 1000000, k * 1000000 + 600000);
    }
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
}
