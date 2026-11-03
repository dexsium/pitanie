// Авторизация на часах Zepp OS (GTR 4): обмен ключами ECDH (NIST B-163) и
// подтверждение знания секретного ключа Zepp. Схема описана по Gadgetbridge
// (AGPLv3), InitOperation2021. Подтверждена только по исходникам; на реальных
// часах результат фиксируется статусом, а не предполагается.
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'huami_chunked.dart';
import 'huami_crypto.dart';

/// Хранение ключа: Keychain (iOS) / Android Keystore через flutter_secure_storage.
class AuthKeyStore {
  static const _name = 'amazfit_auth_key';
  static const _storage = FlutterSecureStorage();

  /// Принимает 32 hex-символа, допускается префикс 0x. Возвращает null, если формат неверен.
  static Uint8List? parse(String input) {
    var s = input.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(s)) return null;
    return Uint8List.fromList(
        [for (var i = 0; i < 32; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
  }

  static Future<bool> save(String input) async {
    final k = parse(input);
    if (k == null) return false;
    await _storage.write(key: _name, value: k.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    return true;
  }

  static Future<Uint8List?> load() async {
    final v = await _storage.read(key: _name);
    return v == null ? null : parse(v);
  }

  static Future<bool> exists() async => (await load()) != null;

  static Future<void> delete() => _storage.delete(key: _name);
}

enum AuthStatus { success, wrongKey, timeout, failed }

class AuthResult {
  final AuthStatus status;
  final String message;
  const AuthResult(this.status, this.message);
  bool get ok => status == AuthStatus.success;
}

class HuamiAuthenticator {
  final BluetoothCharacteristic write; // 0016
  final BluetoothCharacteristic read; // 0017
  final Uint8List secret;
  final int mtu;
  late final ChunkedEncoder _encoder = ChunkedEncoder(mtu: mtu);
  late final ChunkedDecoder _decoder = ChunkedDecoder(_onPayload);
  final _done = Completer<AuthResult>();
  Uint8List? _priv;
  StreamSubscription<List<int>>? _sub;

  HuamiAuthenticator(
      {required this.write, required this.read, required this.secret, required this.mtu});

  /// Ключ сессии после успешной авторизации (нужен для дальнейшего шифрованного обмена).
  Uint8List? sessionKey;
  int? sequence;

  /// Сообщения сервисов после авторизации (кроме самой авторизации и списка сервисов).
  void Function(int type, Uint8List payload)? onPayload;

  /// Эндпоинты, которые часы просят шифровать (из списка сервисов, эндпоинт 0x0000).
  final Set<int> encryptedEndpoints = {};
  Completer<void>? _services;

  /// Отправляет команду сервису; шифрование включается по списку сервисов часов.
  Future<void> send(int endpoint, List<int> data) async {
    final enc = encryptedEndpoints.contains(endpoint);
    for (final chunk in _encoder.encode(endpoint, Uint8List.fromList(data), encrypt: enc)) {
      await _send(write, chunk);
    }
  }

  /// Запрашивает у часов список сервисов (какие шифруются). Ждёт ответ до [timeout].
  Future<bool> requestServices({Duration timeout = const Duration(seconds: 6)}) async {
    _services = Completer<void>();
    await send(0x0000, [0x03]);
    try {
      await _services!.future.timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
  }
  ChunkedEncoder get encoder => _encoder;
  ChunkedDecoder get decoder => _decoder;

  Future<void> _send(BluetoothCharacteristic c, List<int> data) =>
      c.write(data, withoutResponse: c.properties.writeWithoutResponse);

  Future<AuthResult> authenticate({Duration timeout = const Duration(seconds: 30)}) async {
    try {
      await read.setNotifyValue(true);
      _sub = read.onValueReceived.listen(_onData);

      // Ключи ECDH считаются в отдельном изоляте: операция тяжёлая.
      final pair = await Isolate.run(() {
        final r = Random.secure();
        while (true) {
          final p = Uint8List.fromList([for (var i = 0; i < 24; i++) r.nextInt(256)]);
          final pub = ecdhPublic(p);
          if (pub != null) return [p, pub];
        }
      });
      _priv = pair[0];
      final cmd = Uint8List(52)..setAll(0, [0x04, 0x02, 0x00, 0x02]);
      cmd.setRange(4, 52, pair[1]);
      for (final chunk in _encoder.encode(endpointAuth, cmd)) {
        await _send(write, chunk);
      }
      final r = await _done.future.timeout(timeout,
          onTimeout: () => const AuthResult(AuthStatus.timeout,
              'Часы не ответили на авторизацию. Закройте Zepp и повторите.'));
      if (!r.ok) await close();
      return r;
    } catch (e) {
      await close();
      return AuthResult(AuthStatus.failed, 'Ошибка авторизации: $e');
    }
  }

  void _onData(List<int> v) {
    if (v.isEmpty) return;
    final data = Uint8List.fromList(v);
    if (data[0] != 0x03) return; // 0x04 - подтверждение от часов, не требует обработки
    final needsAck = _decoder.decode(data);
    if (needsAck) {
      _send(read, [0x04, 0x00, _decoder.lastHandle, 0x01, _decoder.lastCount]);
    }
  }

  Future<void> _onPayload(int type, Uint8List p) async {
    if (type == 0x0000) {
      _parseServices(p);
      return;
    }
    if (type != endpointAuth) {
      onPayload?.call(type, p);
      return;
    }
    if (p.length < 3) return;
    if (p[0] == 0x10 && p[1] == 0x04 && p[2] == 0x01 && p.length >= 67) {
      final remoteRandom = Uint8List.sublistView(p, 3, 19);
      final remotePub = Uint8List.fromList(p.sublist(19, 67));
      final priv = _priv!;
      final shared = await Isolate.run(() => ecdhShared(priv, remotePub));
      if (shared == null) {
        _finish(const AuthResult(AuthStatus.failed, 'Часы прислали некорректный ключ.'));
        return;
      }
      final seq = ByteData.sublistView(shared, 0, 4).getUint32(0, Endian.little);
      final session = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        session[i] = shared[i + 8] ^ secret[i];
      }
      _encoder.setEncryption(seq, session);
      _decoder.setKey(session);
      sessionKey = session;
      sequence = seq;
      final e1 = aesEcbEncrypt(remoteRandom, secret);
      final e2 = aesEcbEncrypt(remoteRandom, session);
      final cmd = Uint8List(33)..[0] = 0x05;
      cmd.setRange(1, 17, e1);
      cmd.setRange(17, 33, e2);
      for (final chunk in _encoder.encode(endpointAuth, cmd)) {
        await _send(write, chunk);
      }
    } else if (p[0] == 0x10 && p[1] == 0x05 && p[2] == 0x01) {
      _finish(const AuthResult(AuthStatus.success, 'Авторизация выполнена: часы приняли ключ.'));
    } else if (p[0] == 0x10 && p[1] == 0x05 && p[2] == 0x25) {
      _finish(const AuthResult(
          AuthStatus.wrongKey, 'Часы отклонили ключ. Проверьте ключ и не отвязывайте часы в Zepp.'));
    } else {
      _finish(AuthResult(AuthStatus.failed, 'Неожиданный ответ часов: ${p.take(3).toList()}'));
    }
  }

  /// Ответ списка сервисов: 04, число (u16 LE), затем по 3 байта: эндпоинт (u16 LE) и флаг шифрования.
  void _parseServices(Uint8List p) {
    if (p.isEmpty || p[0] != 0x04 || p.length < 3) return;
    final bd = ByteData.sublistView(p);
    final n = bd.getUint16(1, Endian.little);
    var o = 3;
    encryptedEndpoints.clear();
    for (var i = 0; i < n && o + 3 <= p.length; i++, o += 3) {
      final endpoint = bd.getUint16(o, Endian.little);
      if (p[o + 2] == 1) encryptedEndpoints.add(endpoint);
    }
    if (_services != null && !_services!.isCompleted) _services!.complete();
  }

  void _finish(AuthResult r) {
    if (!_done.isCompleted) _done.complete(r);
  }
}
