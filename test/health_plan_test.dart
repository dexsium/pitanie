import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/health_integration/health_service.dart';

void main() {
  final now = DateTime(2026, 11, 11, 12);
  const types = ['HEART_RATE', 'STEPS', 'SLEEP_SESSION'];
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  test('первая и полная синхронизация читают 30 суток со сверкой', () {
    final a = planHealthRead(
        now: now, lastSync: null, full: false, watermarks: {}, lastReconcile: null, typeNames: types);
    expect(a.reconcile, isTrue);
    expect(a.from, now.subtract(const Duration(days: 30)));
    final b = planHealthRead(
        now: now,
        lastSync: now.subtract(const Duration(hours: 1)),
        full: true,
        watermarks: {'STEPS': ms(now)},
        lastReconcile: now,
        typeNames: types);
    expect(b.reconcile, isTrue);
    expect(b.fromFor('STEPS'), now.subtract(const Duration(days: 30)));
  });

  test('обычная синхронизация: каждый тип от своей отметки с запасом, без сверки', () {
    final wm = {
      'HEART_RATE': ms(now.subtract(const Duration(minutes: 30))),
      'STEPS': ms(now.subtract(const Duration(hours: 5))),
      'SLEEP_SESSION': ms(now.subtract(const Duration(hours: 6))),
    };
    final p = planHealthRead(
        now: now,
        lastSync: now.subtract(const Duration(minutes: 20)),
        full: false,
        watermarks: wm,
        lastReconcile: now.subtract(const Duration(hours: 2)),
        typeNames: types);
    expect(p.reconcile, isFalse);
    expect(p.fromFor('HEART_RATE'), now.subtract(const Duration(hours: 3, minutes: 30)));
    expect(p.fromFor('STEPS'), now.subtract(const Duration(hours: 8)));
    expect(p.fromFor('SLEEP_SESSION'), now.subtract(const Duration(hours: 24)));
  });

  test('раз в сутки сверочный проход: общее окно не короче 2 суток', () {
    final wm = {for (final t in types) t: ms(now.subtract(const Duration(minutes: 10)))};
    final p = planHealthRead(
        now: now,
        lastSync: now.subtract(const Duration(minutes: 20)),
        full: false,
        watermarks: wm,
        lastReconcile: now.subtract(const Duration(hours: 21)),
        typeNames: types);
    expect(p.reconcile, isTrue);
    expect(p.from, now.subtract(const Duration(days: 2)));
    expect(p.fromFor('STEPS'), p.from);
  });

  test('давно не открывали: окно не длиннее 30 суток; нет отметки: два дня от прошлой синхронизации', () {
    final p = planHealthRead(
        now: now,
        lastSync: now.subtract(const Duration(days: 90)),
        full: false,
        watermarks: {'HEART_RATE': ms(now.subtract(const Duration(days: 80)))},
        lastReconcile: now,
        typeNames: types);
    expect(p.fromFor('HEART_RATE'), now.subtract(const Duration(days: 30)));
    final q = planHealthRead(
        now: now,
        lastSync: now.subtract(const Duration(hours: 5)),
        full: false,
        watermarks: {},
        lastReconcile: now,
        typeNames: types);
    expect(q.fromFor('STEPS'), now.subtract(const Duration(days: 2, hours: 5)));
  });

  test('отметки: двигаются вперёд, без данных встают на «сутки назад», ошибка не сдвигает', () {
    final dayAgo = ms(now.subtract(const Duration(days: 1)));
    final old = {
      'HEART_RATE': ms(now.subtract(const Duration(days: 5))),
      'STEPS': ms(now.subtract(const Duration(hours: 1))),
      'SLEEP_SESSION': ms(now.subtract(const Duration(days: 4))),
    };
    final m = advanceWatermarks(
        old: old,
        newest: {'STEPS': ms(now)},
        failed: {'SLEEP_SESSION'},
        now: now,
        typeNames: types);
    expect(m['STEPS'], ms(now));
    expect(m['HEART_RATE'], dayAgo);
    expect(m['SLEEP_SESSION'], old['SLEEP_SESSION']);
    // Свежая запись не откатывается назад, если новых данных нет в пределах окна чтения.
    final newer = advanceWatermarks(
        old: {'STEPS': ms(now)},
        newest: {'STEPS': ms(now.subtract(const Duration(hours: 2)))},
        failed: {},
        now: now,
        typeNames: ['STEPS']);
    expect(newer['STEPS'], ms(now));
  });

  test('разбор отметок: мусор даёт пустой список', () {
    expect(parseWatermarks(null), isEmpty);
    expect(parseWatermarks('не json'), isEmpty);
    expect(parseWatermarks('{"A":5,"B":"x","C":-1}'), {'A': 5});
  });
}
