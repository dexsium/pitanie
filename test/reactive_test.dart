import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/database/database.dart';

void main() {
  test('пачка изменений во время расчёта даёт один повторный расчёт, а не по расчёту на событие',
      () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var loads = 0;
    final values = <int>[];
    final sub = reactive<int>(db, () async {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return loads;
    }, debounce: const Duration(milliseconds: 10)).listen(values.add);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(loads, 1);

    // 15 записей подряд, пока идёт расчёт.
    for (var i = 0; i < 15; i++) {
      await db.setSetting('k$i', 'v');
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(loads, lessThanOrEqualTo(4), reason: 'события схлопываются');
    expect(loads, greaterThanOrEqualTo(2), reason: 'изменение не потеряно');
    expect(values.last, loads, reason: 'последнее значение отражает последний расчёт');
    await sub.cancel();
  });

  test('после отмены подписки расчёты прекращаются; ошибка расчёта не ломает поток', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    var loads = 0;
    final errors = <Object>[];
    final values = <int>[];
    final sub = reactive<int>(db, () async {
      loads++;
      if (loads == 2) throw StateError('сбой');
      return loads;
    }, debounce: const Duration(milliseconds: 10)).listen(values.add, onError: errors.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.setSetting('a', '1');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await db.setSetting('b', '2');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(errors.length, 1);
    expect(loads, greaterThan(2));
    expect(values.last, loads, reason: 'после ошибки поток продолжает работать');
    await sub.cancel();
    final before = loads;
    await db.setSetting('c', '3');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(loads, before);
  });

  test('изменения игнорируемых таблиц не запускают пересчёт, серия записей даёт один расчёт', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.getUser(); // открытие базы (начальное наполнение) до подписки
    await Future<void>.delayed(const Duration(milliseconds: 50));
    var loads = 0;
    final sub = reactive<int>(db, () async => ++loads,
        ignore: const {'app_settings'}, debounce: const Duration(milliseconds: 30)).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(loads, 1);
    for (var i = 0; i < 10; i++) {
      await db.setSetting('x$i', '1');
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(loads, 1, reason: 'настройки игнорируются');
    for (var i = 0; i < 5; i++) {
      await db.addWeight(DateTime(2026, 11, 1 + i, 8), 70.0 + i);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(loads, 2, reason: 'серия записей веса даёт один пересчёт');
    await sub.cancel();
  });
}
