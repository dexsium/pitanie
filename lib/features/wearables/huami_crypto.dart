// Криптография обмена с часами Huami / Zepp OS.
//
// Алгоритмы (ECDH на кривой NIST B-163, формат ключей, AES-ECB) описаны по
// проекту Gadgetbridge (AGPLv3, https://codeberg.org/Freeyourgadget/Gadgetbridge),
// классы ECDH_B163, CryptoUtils, Huami2021Chunked*. Реализация на Dart написана заново.
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// ---------- GF(2^163), x^163 + x^7 + x^6 + x^3 + 1 ----------

final BigInt _poly = (BigInt.one << 163) | BigInt.from(0xC9);

BigInt _words(List<int> w) {
  var r = BigInt.zero;
  for (var i = w.length - 1; i >= 0; i--) {
    r = (r << 32) | BigInt.from(w[i]);
  }
  return r;
}

final BigInt _coeffB = _words([0x4a3205fd, 0x512f7874, 0x1481eb10, 0xb8c953ca, 0x0a601907, 0x2]);
final BigInt baseX = _words([0xe8343e36, 0xd4994637, 0xa0991168, 0x86a2d57e, 0xf0eba162, 0x3]);
final BigInt baseY = _words([0x797324f1, 0xb11c5c0c, 0xa2cdd545, 0x71a0094f, 0xd51fbc6c, 0x0]);
final BigInt baseOrder = _words([0xa4234c33, 0x77e70c12, 0x000292fe, 0x0, 0x0, 0x4]);

BigInt _mul(BigInt a, BigInt b) {
  var res = BigInt.zero;
  var x = a;
  var y = b;
  final top = BigInt.one << 163;
  while (y != BigInt.zero) {
    if ((y & BigInt.one) == BigInt.one) res ^= x;
    y >>= 1;
    x <<= 1;
    if ((x & top) != BigInt.zero) x ^= _poly;
  }
  return res;
}

BigInt _inv(BigInt x) {
  // x^(2^163 - 2) = произведение x^(2^i), i = 1..162
  var r = BigInt.one;
  var t = x;
  for (var i = 1; i < 163; i++) {
    t = _mul(t, t);
    r = _mul(r, t);
  }
  return r;
}

class EcPoint {
  BigInt x, y;
  EcPoint(this.x, this.y);
  EcPoint.zero()
      : x = BigInt.zero,
        y = BigInt.zero;
  bool get isZero => x == BigInt.zero && y == BigInt.zero;
  EcPoint copy() => EcPoint(x, y);
}

void _double(EcPoint p) {
  if (p.x == BigInt.zero) {
    p.y = BigInt.zero;
    return;
  }
  var l = _inv(p.x);
  l = _mul(l, p.y);
  l = l ^ p.x;
  final y = _mul(p.x, p.x);
  var x = _mul(l, l);
  l = l ^ BigInt.one;
  x = x ^ l;
  l = _mul(l, x);
  p.x = x;
  p.y = y ^ l;
}

void _add(EcPoint p, EcPoint q) {
  if (q.isZero) return;
  if (p.isZero) {
    p.x = q.x;
    p.y = q.y;
    return;
  }
  if (p.x == q.x) {
    if (p.y == q.y) {
      _double(p);
    } else {
      p.x = BigInt.zero;
      p.y = BigInt.zero;
    }
    return;
  }
  final a = p.y ^ q.y;
  final b = p.x ^ q.x;
  var c = _inv(b);
  c = _mul(c, a);
  var d = _mul(c, c);
  d = d ^ c ^ b ^ BigInt.one;
  final x1 = p.x ^ d;
  var a2 = _mul(x1, c);
  a2 = a2 ^ d;
  p.y = p.y ^ a2;
  p.x = d;
}

EcPoint pointMul(EcPoint p, BigInt exp) {
  final r = EcPoint.zero();
  for (var i = exp.bitLength - 1; i >= 0; i--) {
    _double(r);
    if (((exp >> i) & BigInt.one) == BigInt.one) _add(r, p);
  }
  return r;
}

bool onCurve(EcPoint p) {
  if (p.isZero) return false;
  var a = _mul(p.x, p.x);
  final b = _mul(a, p.x);
  a = a ^ b ^ _coeffB;
  a = a ^ _mul(p.y, p.y);
  return a == _mul(p.x, p.y);
}

// ---------- байты <-> числа (little-endian, 24 байта) ----------

BigInt _fromLe(Uint8List b, int offset) {
  var r = BigInt.zero;
  for (var i = 23; i >= 0; i--) {
    r = (r << 8) | BigInt.from(b[offset + i]);
  }
  return r;
}

void _toLe(BigInt v, Uint8List out, int offset) {
  for (var i = 0; i < 24; i++) {
    out[offset + i] = ((v >> (8 * i)) & BigInt.from(0xff)).toInt();
  }
}

BigInt _prepPrivate(Uint8List priv) {
  // Как в tiny-ECDH: биты >= 162 сбрасываются (ограничение 1 <= k < n).
  final mask = (BigInt.one << 162) - BigInt.one;
  return _fromLe(priv, 0) & mask;
}

/// Открытый ключ (48 байт: x || y), или null, если приватный ключ слишком мал.
Uint8List? ecdhPublic(Uint8List priv) {
  if (priv.length != 24) return null;
  if (_fromLe(priv, 0).bitLength < 81) return null;
  final p = pointMul(EcPoint(baseX, baseY), _prepPrivate(priv));
  final out = Uint8List(48);
  _toLe(p.x, out, 0);
  _toLe(p.y, out, 24);
  return out;
}

/// Общий секрет (48 байт), или null, если чужой ключ не лежит на кривой.
Uint8List? ecdhShared(Uint8List priv, Uint8List remotePub) {
  if (priv.length != 24 || remotePub.length != 48) return null;
  final q = EcPoint(_fromLe(remotePub, 0), _fromLe(remotePub, 24));
  if (q.isZero || !onCurve(q)) return null;
  final r = pointMul(q, _prepPrivate(priv));
  final out = Uint8List(48);
  _toLe(r.x, out, 0);
  _toLe(r.y, out, 24);
  return out;
}

// ---------- AES-ECB без выравнивания и CRC32 ----------

Uint8List _aes(bool encrypt, Uint8List data, Uint8List key) {
  if (data.length % 16 != 0) throw ArgumentError('Длина данных должна быть кратна 16');
  final cipher = AESEngine()..init(encrypt, KeyParameter(key));
  final out = Uint8List(data.length);
  for (var o = 0; o < data.length; o += 16) {
    cipher.processBlock(data, o, out, o);
  }
  return out;
}

Uint8List aesEcbEncrypt(Uint8List data, Uint8List key) => _aes(true, data, key);
Uint8List aesEcbDecrypt(Uint8List data, Uint8List key) => _aes(false, data, key);

int crc32(Uint8List data, [int start = 0, int? end]) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < (end ?? data.length); i++) {
    c ^= data[i];
    for (var k = 0; k < 8; k++) {
      c = (c & 1) == 1 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
