import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/zepp_notifications.dart';

void main() {
  test('разбор возможностей версии 5', () {
    // 02, версия 5, служебный блок: u16, u8, u8, u16 длина (0), затем флаги картинки и ключа.
    final p = Uint8List.fromList([2, 5, 100, 0, 1, 1, 0, 0, 1, 1]);
    final c = parseNotifCaps(p)!;
    expect(c.version, 5);
    expect(c.supportsPictures, isTrue);
    expect(c.supportsKey, isTrue);
  });

  test('реальный ответ GTR 4 (прошивка 7.6.0.2)', () {
    // Из журнала часов: 0x001e: 02 05 64 00 01 01 05 00 01 02 03 04 05 01 01
    final p = Uint8List.fromList(
        [0x02, 0x05, 0x64, 0x00, 0x01, 0x01, 0x05, 0x00, 1, 2, 3, 4, 5, 1, 1]);
    final c = parseNotifCaps(p)!;
    expect(c.version, 5);
    expect(c.supportsPictures, isTrue);
    expect(c.supportsKey, isTrue);
  });

  test('оборванные и чужие ответы дают null', () {
    expect(parseNotifCaps(Uint8List.fromList([2, 5, 100])), isNull);
    expect(parseNotifCaps(Uint8List.fromList([3, 5])), isNull);
    expect(parseNotifCaps(Uint8List(0)), isNull);
  });

  test('формат уведомления версии 5', () {
    const caps = NotifCaps(5, false, false);
    final b = buildNotification(
        id: 0x01020304,
        appId: 'a.b',
        title: 'T',
        body: 'Привет',
        appName: 'App',
        caps: caps);
    expect(b.sublist(0, 7), [3, 4, 3, 2, 1, 0xfa, 0]);
    final rest = b.sublist(7);
    final zeros = [
      for (var i = 0; i < rest.length; i++)
        if (rest[i] == 0) i
    ];
    expect(utf8.decode(rest.sublist(0, zeros[0])), 'a.b');
    expect(utf8.decode(rest.sublist(zeros[0] + 1, zeros[1])), 'T');
    expect(utf8.decode(rest.sublist(zeros[1] + 1, zeros[2])), 'Привет');
    expect(utf8.decode(rest.sublist(zeros[2] + 1, zeros[3])), 'App');
    // после названия: «ответить» и «беззвучное» (версия 5)
    expect(rest.sublist(zeros[3] + 1), [0, 0]);
  });

  test('длинный текст режется по границе символа', () {
    const caps = NotifCaps(4, false, false);
    final b = buildNotification(
        id: 1,
        appId: 'a',
        title: 't',
        body: 'я' * 600,
        appName: 'n',
        caps: caps);
    final rest = b.sublist(7);
    final zeros = [
      for (var i = 0; i < rest.length; i++)
        if (rest[i] == 0) i
    ];
    final body = rest.sublist(zeros[1] + 1, zeros[2]);
    expect(body.length, lessThanOrEqualTo(512));
    expect(() => utf8.decode(body), returnsNormally);
  });

  test('список приложений 0x001f: реальное начало ответа GTR 4', () {
    final ids = ['ru.oneme.app', 'ru.app.gift.mate.prod', 'com.apple.mobilemail'];
    final b = <int>[0x04, ids.length, 0];
    for (final id in ids) {
      b..addAll(utf8.encode(id))..add(0)..add(1);
    }
    final l = parseWatchApps(Uint8List.fromList(b))!;
    expect(l.consistent, isTrue);
    expect(l.apps.map((a) => a.id), ids);
    expect(l.apps.every((a) => a.enabled), isTrue);
    // число записей не совпало — структура не считается сошедшейся
    b[1] = 9;
    expect(parseWatchApps(Uint8List.fromList(b))!.consistent, isFalse);
    expect(parseWatchApps(Uint8List.fromList([2, 0, 0])), isNull);
  });

  test('гипотеза C: весь список с изменённым флагом', () {
    final p = buildAppSetAll(
        const [WatchApp('a', true), WatchApp('b', false)], 'b', true);
    expect(p, [5, 2, 0, 0x61, 0, 1, 0x62, 0, 1]);
    // собранный пакет читается тем же разбором, что и ответ часов (кроме кода команды)
    final back = parseWatchApps(Uint8List.fromList([4, ...p.sublist(1)]))!;
    expect(back.consistent, isTrue);
    expect(back.apps[1].enabled, isTrue);
  });

  test('гипотезы записи приложения собираются предсказуемо', () {
    expect(buildAppSetA('a', false), [5, 0x61, 0, 0]);
    expect(buildAppSetB('a', true), [5, 1, 0, 0x61, 0, 1]);
  });
}
