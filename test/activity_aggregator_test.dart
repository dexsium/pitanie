import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/activity_aggregator.dart';

Interval iv(String s, DateTime a, DateTime b, double v) => Interval(s, a, b, v);

void main() {
  final from = DateTime.utc(2025, 1, 24);
  final to = DateTime.utc(2025, 1, 25);
  DateTime t(int h, [int m = 0]) => DateTime.utc(2025, 1, 24, h, m);

  group('источники', () {
    final watch = [iv('watch', t(8), t(9), 1000), iv('watch', t(9), t(10), 2000)];
    final phone = [iv('phone', t(8), t(9), 900), iv('phone', t(9), t(10), 2500)];

    test('данные двух источников не суммируются', () {
      expect(dayTotal([...watch, ...phone], from, to), 3400); // phone: 3400 > watch: 3000
    });

    test('приоритетный источник имеет преимущество', () {
      expect(dayTotal([...watch, ...phone], from, to, preferred: 'watch'), 3000);
    });

    test('если у приоритетного нет данных — берётся другой', () {
      expect(dayTotal(phone, from, to, preferred: 'watch'), 3400);
    });

    test('нет данных', () {
      expect(dayTotal([], from, to), 0);
    });
  });

  group('перекрытия и дубликаты', () {
    test('перекрывающиеся записи одного источника не суммируются', () {
      final r = [iv('w', t(8), t(10), 100), iv('w', t(9), t(11), 150)];
      expect(dayTotal(r, from, to), 150);
    });

    test('повторная запись той же записи не удваивает значение', () {
      final r = [iv('w', t(8), t(9), 500), iv('w', t(8), t(9), 500)];
      expect(dayTotal(r, from, to), 500);
    });

    test('смежные записи суммируются', () {
      final r = [iv('w', t(8), t(9), 100), iv('w', t(9), t(10), 150)];
      expect(dayTotal(r, from, to), 250);
    });
  });

  group('сутки и часовые пояса', () {
    test('запись через полночь делится пропорционально', () {
      final r = [iv('w', DateTime.utc(2025, 1, 23, 23), DateTime.utc(2025, 1, 24, 1), 200)];
      expect(dayTotal(r, from, to), closeTo(100, 1e-9));
      expect(dayTotal(r, DateTime.utc(2025, 1, 23), from), closeTo(100, 1e-9));
    });

    test('границы суток считаются по локальному дню, а не по UTC', () {
      final r = [iv('w', DateTime.utc(2025, 1, 24, 21, 30), DateTime.utc(2025, 1, 24, 21, 40), 300)];
      // UTC+3: локальные сутки 24 января = 23:00 UTC 23-го → 21:00 UTC 24-го
      final localFrom = DateTime.utc(2025, 1, 23, 21);
      final localTo = DateTime.utc(2025, 1, 24, 21);
      expect(dayTotal(r, localFrom, localTo), 0);
      expect(dayTotal(r, localTo, localTo.add(const Duration(days: 1))), 300);
      // После смены пояса на UTC+0 та же запись попадает в 24 января
      expect(dayTotal(r, from, to), 300);
    });

    test('мгновенная запись попадает в сутки целиком', () {
      final r = [iv('w', t(12), t(12), 77)];
      expect(dayTotal(r, from, to), 77);
      expect(dayTotal(r, to, to.add(const Duration(days: 1))), 0);
    });
  });

  group('время активности', () {
    test('пересекающиеся тренировки не суммируются', () {
      final m = unionMinutes([(t(8), t(9)), (t(8, 30), t(9, 30))], from, to);
      expect(m, 90);
    });

    test('раздельные тренировки суммируются', () {
      expect(unionMinutes([(t(8), t(9)), (t(10), t(10, 30))], from, to), 90);
    });

    test('тренировка через полночь обрезается по суткам', () {
      final m = unionMinutes([(DateTime.utc(2025, 1, 24, 23, 30), DateTime.utc(2025, 1, 25, 0, 30))], from, to);
      expect(m, 30);
    });
  });
}
