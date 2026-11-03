import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/huami_chunked.dart';
import 'package:pitanie/features/wearables/huami_crypto.dart';

Uint8List _hex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

void main() {
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
