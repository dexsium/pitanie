// Уведомления на часы по протоколу Zepp OS (сервис 0x001e).
//
// Формат взят из открытой реализации Gadgetbridge (ZeppOsNotificationService, AGPLv3) и сверён с
// тем, что приложение Zepp содержит классы уведомлений и тест уведомлений. На прошивке часов
// 7.6.0.2 формат не проверялся: результат подтверждается только тем, что уведомление появилось
// на экране часов. Часы на команду «показать» подтверждения не отправляют.
import 'dart:convert';
import 'dart:typed_data';

const notifEndpoint = 0x001e;

const _cmdCapsRequest = 0x01;
const _cmdCapsResponse = 0x02;
const _cmdSend = 0x03;
const _typeNormal = 0xfa;
const _typeSms = 0x05;

class NotifCaps {
  final int version;
  final bool supportsPictures, supportsKey;
  const NotifCaps(this.version, this.supportsPictures, this.supportsKey);
}

Uint8List buildNotifCapsRequest() => Uint8List.fromList([_cmdCapsRequest]);

/// Разбор ответа «возможности»: 02, версия, для версии ≥4 служебный блок, для ≥5 флаги.
/// null, если это не ответ возможностей или данные оборваны.
NotifCaps? parseNotifCaps(Uint8List p) {
  if (p.length < 2 || p[0] != _cmdCapsResponse) return null;
  final version = p[1];
  var o = 2;
  if (version >= 4) {
    if (p.length < o + 6) return null;
    final n = ByteData.sublistView(p).getUint16(o + 4, Endian.little);
    o += 6 + n;
  }
  var pictures = false, key = false;
  if (version >= 5) {
    if (p.length < o + 2) return null;
    pictures = p[o] != 0;
    key = p[o + 1] != 0;
  }
  return NotifCaps(version, pictures, key);
}

List<int> _cstr(String s, {int maxBytes = 512}) {
  var b = utf8.encode(s);
  if (b.length > maxBytes) {
    // Обрезаем по границе символа, чтобы не получить битую UTF-8.
    var n = maxBytes;
    while (n > 0 && (b[n] & 0xC0) == 0x80) {
      n--;
    }
    b = b.sublist(0, n);
  }
  return [...b.where((x) => x != 0), 0];
}

/// Команда «показать уведомление» (подкоманда 0). [id] — номер уведомления, [appId] — пакет
/// приложения (часы по нему выбирают значок).
Uint8List buildNotification({
  required int id,
  required String appId,
  required String title,
  required String body,
  required String appName,
  required NotifCaps caps,
  bool sms = false,
}) {
  final b = BytesBuilder();
  b.addByte(_cmdSend);
  final idb = ByteData(4)..setUint32(0, id, Endian.little);
  b.add(idb.buffer.asUint8List());
  b.addByte(sms ? _typeSms : _typeNormal);
  b.addByte(0); // показать
  b.add(_cstr(appId, maxBytes: 128));
  b.add(_cstr(title, maxBytes: 128));
  b.add(_cstr(body));
  b.add(_cstr(appName, maxBytes: 128));
  b.addByte(0); // ответить с часов: нет
  if (caps.version >= 5) b.addByte(0); // не беззвучное
  if (caps.supportsPictures) b.addByte(0); // без картинки
  if (caps.supportsKey) b.addByte(0); // пустой ключ
  return b.toBytes();
}
