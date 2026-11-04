import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/app/theme.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/wearables/huami_fetch.dart';
import 'package:pitanie/features/wearables/watch_settings.dart';
import 'package:pitanie/features/wearables/watch_settings_page.dart';
import 'package:pitanie/features/wearables/wearable_controller.dart';

Uint8List u8(List<int> l) => Uint8List.fromList(l);

void main() {
  group('команды настроек часов', () {
    test('запрос группы «Здоровье»', () {
      expect(encodeHealthRequest(), [3, 0, 8, 5, 0x01, 0x11, 0x12, 0x13, 0x31]);
    });

    test('запись: байт и булево, интервал «авто» = 0xFF', () {
      expect(encodeHealthSet({keyHrInterval: 5, keySpo2AllDay: true}),
          [5, 8, 2, 0, 2, 0x01, 0x10, 5, 0x31, 0x0b, 1]);
      expect(encodeHealthSet({keyHrInterval: -1}),
          [5, 8, 2, 0, 1, 0x01, 0x10, 0xFF]);
      expect(
          encodeHealthSet({keyStress: false}), [5, 8, 2, 0, 1, 0x13, 0x0b, 0]);
      expect(() => encodeHealthSet({keyStress: 'да'}), throwsArgumentError);
    });

    test('разбор ответа без ограничений', () {
      final r = parseHealthResponse(u8([
        4,
        1,
        8,
        2,
        0,
        5,
        0x01,
        0x10,
        5,
        0x11,
        0x0b,
        1,
        0x12,
        0x0b,
        0,
        0x13,
        0x0b,
        1,
        0x31,
        0x0b,
        1,
      ]))!;
      expect(r.hrInterval, 5);
      expect([r.sleepHr, r.sleepBreathing, r.stress, r.spo2AllDay],
          [true, false, true, true]);
    });

    test('разбор ответа с ограничениями и отрицательным интервалом', () {
      final r = parseHealthResponse(u8([
        4, 1, 8, 2, 1, 2,
        0x01, 0x10, 0xFF, 3, 0, 0xFF, 5, // значение −1, допустимые: 0, −1, 5
        0x31, 0x0b, 0,
      ]))!;
      expect(r.hrInterval, -1);
      expect(r.spo2AllDay, false);
    });

    test('чужой или ошибочный ответ не принимается', () {
      expect(parseHealthResponse(u8([4, 0, 8, 2, 0, 1, 0x31, 0x0b, 1])),
          isNull); // статус ≠ 1
      expect(parseHealthResponse(u8([4, 1, 9, 2, 0, 1, 0x31, 0x0b, 1])),
          isNull); // другая группа
      expect(
          parseHealthResponse(u8([4, 1, 8, 2, 0, 1, 0x31])), isNull); // обрыв
      expect(parseHealthResponse(u8([6, 1])), isNull);
    });

    test('время: 11 байт, воскресенье = 0, пояс в четвертях часа', () {
      final b = currentTimeBytes(DateTime(2026, 11, 4, 13, 5, 9)); // среда
      expect(b.length, 11);
      expect(b.sublist(0, 7), [0xEA, 0x07, 11, 4, 13, 5, 9]);
      expect(b[7], 3);
      expect(currentTimeBytes(DateTime(2026, 11, 8))[7], 0); // воскресенье
      expect(
          b[10],
          (DateTime(2026, 11, 4, 13, 5, 9).timeZoneOffset.inMinutes ~/ 15) &
              0xFF);
    });

    test('настройки сохраняются и читаются из JSON', () {
      const s =
          WatchHealthSettings(hrInterval: 10, sleepHr: true, spo2AllDay: false);
      final back = WatchHealthSettings.fromJson(s.toJson());
      expect([back.hrInterval, back.sleepHr, back.spo2AllDay, back.stress],
          [10, true, false, null]);
      expect(const WatchHealthSettings().isEmpty, isTrue);
    });
  });

  group('показатели часов из истории', () {
    test('пульс покоя и максимальный: 6 байт на запись', () {
      final ts = 1762300800; // 2025-11-05 00:00 UTC
      final b = ByteData(12);
      b.setUint32(0, ts, Endian.little);
      b.setUint8(4, 12);
      b.setUint8(5, 58);
      b.setUint32(6, ts + 86400, Endian.little);
      b.setUint8(10, 12);
      b.setUint8(11, 61);
      final r = parseDayHeart(b.buffer.asUint8List())!;
      expect(r.map((e) => e.bpm), [58, 61]);
      expect(r.first.time.millisecondsSinceEpoch, ts * 1000);
      expect(parseDayHeart(u8([1, 2, 3])), isNull);
    });

    test('стресс: байт на минуту, 0xFF и недостоверное пропускаются', () {
      final start = DateTime.utc(2026, 11, 4, 10);
      final r = parseStress(u8([20, 0xFF, 45, 200, 80]), start);
      expect(r.map((e) => e.value), [20, 45, 80]);
      expect(r[1].time, start.add(const Duration(minutes: 2)));
    });

    test('дыхание во сне: 8 байт на запись', () {
      final b = ByteData(16);
      b.setUint32(0, 1762300800, Endian.little);
      b.setUint8(5, 15);
      b.setUint32(8, 1762300860, Endian.little);
      b.setUint8(13, 17);
      final r = parseSleepResp(b.buffer.asUint8List())!;
      expect(r.map((e) => e.value), [15, 17]);
      expect(parseSleepResp(u8([1, 2, 3])), isNull);
    });
  });

  for (final size in const [Size(393, 852), Size(320, 568)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'Настройки часов без подключения ${size.width.toInt()} $brightness',
          (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final db = AppDatabase(NativeDatabase.memory());
        await tester.pumpWidget(ProviderScope(
          overrides: [
            dbProvider.overrideWithValue(db),
            wearableProvider.overrideWith((ref) => WearableController(db)),
          ],
          child: MaterialApp(
              theme: buildTheme(brightness), home: const WatchSettingsPage()),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('не подключены'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(() =>
            db.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
      });
    }
  }
}
