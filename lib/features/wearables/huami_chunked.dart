// Chunked-обмен Huami 2021 / Zepp OS (характеристики 0016 / 0017).
// Формат пакетов описан по Gadgetbridge (AGPLv3): Huami2021ChunkedEncoder / Decoder.
import 'dart:typed_data';

import 'huami_crypto.dart';

/// Эндпоинты, подтверждённые по исходникам Gadgetbridge (Huami2021Service).
const int endpointAuth = 0x0082;

class ChunkedEncoder {
  int mtu;
  int _handle = 0;
  int _seq = 0;
  Uint8List? _key;

  ChunkedEncoder({this.mtu = 23});

  void setEncryption(int sequence, Uint8List sessionKey) {
    _seq = sequence;
    _key = sessionKey;
  }

  /// Разбивает сообщение на пакеты для записи в характеристику 0016.
  List<Uint8List> encode(int type, Uint8List data,
      {bool extended = true, bool encrypt = false}) {
    if (encrypt && _key == null)
      throw StateError('Нет ключа сессии для шифрования');
    _handle = (_handle + 1) & 0xFF;
    final handle = _handle;
    final length = data.length;
    var payload = data;
    if (extended && encrypt) {
      final messageKey = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        messageKey[i] = _key![i] ^ handle;
      }
      var encLen = length + 8;
      if (encLen % 16 > 0) encLen += 16 - encLen % 16;
      final buf = Uint8List(encLen)..setRange(0, length, data);
      final bd = ByteData.sublistView(buf);
      bd.setUint32(length, _seq & 0xFFFFFFFF, Endian.little);
      _seq++;
      bd.setUint32(length + 4, crc32(buf, 0, length + 4), Endian.little);
      payload = aesEcbEncrypt(buf, messageKey);
    }

    final chunks = <Uint8List>[];
    var remaining = payload.length;
    var count = 0;
    var headerSize = extended ? 11 : 10;
    while (remaining > 0) {
      final maxChunk = mtu - 3 - headerSize;
      final copy = remaining < maxChunk ? remaining : maxChunk;
      final chunk = Uint8List(copy + headerSize);
      var flags = 0;
      if (encrypt) flags |= 0x08;
      if (count == 0) {
        flags |= 0x01;
        var i = extended ? 5 : 4;
        chunk[i++] = length & 0xFF;
        chunk[i++] = (length >> 8) & 0xFF;
        chunk[i++] = (length >> 16) & 0xFF;
        chunk[i++] = (length >> 24) & 0xFF;
        chunk[i++] = type & 0xFF;
        chunk[i] = (type >> 8) & 0xFF;
      }
      if (remaining <= maxChunk) flags |= 0x06;
      chunk[0] = 0x03;
      chunk[1] = flags;
      if (extended) {
        chunk[2] = 0;
        chunk[3] = handle;
        chunk[4] = count;
      } else {
        chunk[2] = handle;
        chunk[3] = count;
      }
      chunk.setRange(
          headerSize, headerSize + copy, payload, payload.length - remaining);
      chunks.add(chunk);
      remaining -= copy;
      headerSize = extended ? 5 : 4;
      count++;
    }
    return chunks;
  }
}

typedef PayloadHandler = void Function(int type, Uint8List payload);

class ChunkedDecoder {
  final PayloadHandler onPayload;
  final bool extended;
  Uint8List? _key;
  int? _currentHandle;
  int _type = 0;
  int _length = 0;
  BytesBuilder _buffer = BytesBuilder();
  int lastHandle = 0;
  int lastCount = 0;

  ChunkedDecoder(this.onPayload, {this.extended = true});

  void setKey(Uint8List sessionKey) => _key = sessionKey;

  /// Возвращает true, если часы ждут подтверждения этого пакета.
  bool decode(Uint8List data) {
    var i = 0;
    if (data[i++] != 0x03) return false;
    final flags = data[i++];
    final encrypted = (flags & 0x08) != 0;
    final first = (flags & 0x01) != 0;
    final last = (flags & 0x02) != 0;
    final needsAck = (flags & 0x04) != 0;
    if (extended) i++;
    final handle = data[i++];
    if (_currentHandle != null && _currentHandle != handle) return false;
    lastHandle = handle;
    lastCount = data[i++];
    if (first) {
      _length =
          ByteData.sublistView(data, i, i + 4).getUint32(0, Endian.little);
      i += 4;
      _type = data[i] | (data[i + 1] << 8);
      i += 2;
      _currentHandle = handle;
      _buffer = BytesBuilder();
    }
    _buffer.add(data.sublist(i));
    if (last) {
      var buf = _buffer.toBytes();
      final type = _type;
      _currentHandle = null;
      _type = 0;
      if (encrypted) {
        final key = _key;
        if (key == null) return false;
        final messageKey = Uint8List(16);
        for (var j = 0; j < 16; j++) {
          messageKey[j] = key[j] ^ handle;
        }
        try {
          buf = aesEcbDecrypt(buf, messageKey);
        } catch (_) {
          return false;
        }
        buf = Uint8List.sublistView(buf, 0, _length);
      }
      onPayload(type, buf);
    }
    return needsAck;
  }
}
