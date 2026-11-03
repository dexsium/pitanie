import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/huami_chunked.dart';
import 'package:pitanie/features/wearables/huami_crypto.dart';
import 'package:pitanie/features/wearables/huami_fetch.dart';

Uint8List _hex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

void main() {
  historyTests();
  test('CRC32 стандартный тестовый вектор', () {
    expect(crc32(Uint8List.fromList('123456789'.codeUnits)), 0xCBF43926);
  });

  test('AES-128 ECB: вектор FIPS-197', () {
    final key = _hex('000102030405060708090a0b0c0d0e0f');
    final pt = _hex('00112233445566778899aabbccddeeff');
    final ct = aesEcbEncrypt(pt, key);
    expect(ct, _hex('69c4e0d86a7b0430d8cdb78070b4c55a'));
    expect(aesEcbDecrypt(ct, key), pt);
  });

  group('ECDH B-163', () {
    test('базовая точка лежит на кривой, порядок n даёт бесконечность', () {
      final g = EcPoint(baseX, baseY);
      expect(onCurve(g), isTrue);
      expect(pointMul(g, baseOrder).isZero, isTrue);
    });

    test('общий секрет совпадает у обеих сторон', () {
      final a = Uint8List.fromList(List.generate(24, (i) => (i * 37 + 11) & 0xff));
      final b = Uint8List.fromList(List.generate(24, (i) => (i * 91 + 5) & 0xff));
      final pa = ecdhPublic(a)!, pb = ecdhPublic(b)!;
      expect(ecdhShared(a, pb), ecdhShared(b, pa));
      expect(ecdhShared(a, pb), isNotNull);
    });

    test('чужой ключ не на кривой отклоняется', () {
      final a = Uint8List.fromList(List.generate(24, (i) => (i * 37 + 11) & 0xff));
      final bad = Uint8List(48)..[0] = 1..[24] = 1;
      expect(ecdhShared(a, bad), isNull);
    });
  });

  group('Chunked', () {
    test('открытое сообщение собирается обратно из частей', () {
      final enc = ChunkedEncoder(mtu: 23);
      final data = Uint8List.fromList(List.generate(52, (i) => i));
      Uint8List? got;
      int? type;
      final dec = ChunkedDecoder((t, p) {
        type = t;
        got = p;
      });
      final chunks = enc.encode(endpointAuth, data);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        dec.decode(c);
      }
      expect(type, endpointAuth);
      expect(got, data);
    });

    test('шифрованное сообщение расшифровывается тем же ключом', () {
      final key = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final enc = ChunkedEncoder(mtu: 185)..setEncryption(1000, key);
      Uint8List? got;
      final dec = ChunkedDecoder((t, p) => got = p)..setKey(key);
      final data = Uint8List.fromList(List.generate(40, (i) => 255 - i));
      for (final c in enc.encode(0x0029, data, encrypt: true)) {
        dec.decode(c);
      }
      expect(got, data);
    });
  });
}

// ---- история ----
void historyTests() {
  group('История', () {
    test('минутная активность: 8 байт на запись, время идёт по минутам', () {
      final start = DateTime.utc(2026, 11, 3, 10, 0);
      final bytes = Uint8List.fromList([
        1, 5, 20, 80, 0, 0, 0, 0, // шаги 20, пульс 80
        1, 0, 0, 255, 0, 0, 0, 0, // нет пульса
      ]);
      final s = parseActivity(bytes, start)!;
      expect(s.length, 2);
      expect(s[0].steps, 20);
      expect(s[0].hasHeartRate, isTrue);
      expect(s[1].time, start.add(const Duration(minutes: 1)));
      expect(s[1].hasHeartRate, isFalse);
      expect(parseActivity(Uint8List(7), start), isNull);
    });

    test('сон: вид 120, фаза по порогам Gadgetbridge (оценка)', () {
      final start = DateTime.utc(2026, 11, 3, 23, 0);
      final bytes = Uint8List.fromList([
        120, 0, 0, 60, 0, 30, 10, 5, // лёгкий
        120, 0, 0, 55, 0, 30, 50, 5, // глубокий (deep > 42)
        120, 0, 0, 52, 0, 30, 10, 70, // REM (rem > 55)
        115, 0, 0, 0, 0, 0, 0, 0, // часы сняты
      ]);
      final s = parseActivity(bytes, start)!;
      expect(s.map((e) => e.isSleep), [true, true, true, false]);
      expect(s[0].stage, SleepStage.light);
      expect(s[1].stage, SleepStage.deep);
      expect(s[2].stage, SleepStage.rem);
    });

    test('SpO2: версия 2, запись 65 байт, бит 7 — автоматическое измерение', () {
      final b = Uint8List(1 + 65)..[0] = 2;
      ByteData.sublistView(b).setUint32(1, 1700000000, Endian.little);
      b[5] = 128 + 97;
      final s = parseSpo2(b)!;
      expect(s.single.value, 97);
      expect(s.single.automatic, isTrue);
      expect(s.single.time.millisecondsSinceEpoch, 1700000000 * 1000);
      expect(parseSpo2(Uint8List.fromList([3, 0])), isNull);
    });

    test('время запроса и разбор ответа согласованы (с учётом пояса)', () {
      final local = DateTime(2026, 11, 3, 14, 30);
      final tzQuarters = local.timeZoneOffset.inMinutes ~/ 15;
      final b = fetchTimeBytes(local);
      expect(b.length, 8);
      expect(b[2], 11);
      expect(b[7], tzQuarters & 0xff);
      final parsed = parseFetchTime(b, 0);
      expect(parsed.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
    });
  });
}
