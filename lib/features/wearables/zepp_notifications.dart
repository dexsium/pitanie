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

/// Сервис 0x001f: список приложений iPhone, о которых знают часы (идентификаторы ANCS) и флаг
/// «разрешено». Формат ответа на запрос `03` разобран по реальному ответу GTR 4 (прошивка
/// 7.6.0.2): `04`, число приложений (u16, little-endian), затем пары `идентификатор\0 флаг`.
/// Значение флага (1 = разрешено) подтверждено сопоставлением со списком в Zepp не полностью.
const appFilterEndpoint = 0x001f;

class WatchApp {
  final String id;
  final bool enabled;

  /// Сырые байты идентификатора (для записей с непечатными символами).
  final List<int> idBytes;
  const WatchApp(this.id, this.enabled, [this.idBytes = const []]);

  /// Идентификатор состоит только из печатных ASCII-символов.
  bool get printable =>
      id.isNotEmpty && id.codeUnits.every((c) => c >= 0x20 && c < 0x7f);

  String get idHex =>
      idBytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
}

class WatchAppList {
  final List<WatchApp> apps;
  final int declared;
  final bool consistent;
  const WatchAppList(this.apps, this.declared, this.consistent);
}

/// null, если это не ответ списка. `consistent` = число разобранных записей совпало с
/// заявленным и в конце нет лишних байт.
WatchAppList? parseWatchApps(Uint8List p) {
  if (p.length < 3 || p[0] != 0x04) return null;
  final declared = p[1] | (p[2] << 8);
  final apps = <WatchApp>[];
  var o = 3;
  var clean = true;
  while (o < p.length) {
    final e = p.indexOf(0, o);
    if (e < 0 || e + 1 >= p.length) {
      clean = false;
      break;
    }
    final bytes = p.sublist(o, e);
    apps.add(WatchApp(utf8.decode(bytes, allowMalformed: true), p[e + 1] != 0, bytes));
    o = e + 2;
  }
  return WatchAppList(apps, declared, clean && apps.length == declared);
}

/// Гипотеза A записи (источника нет): `05 идентификатор\0 флаг`.
Uint8List buildAppSetA(String id, bool on) =>
    Uint8List.fromList([0x05, ...utf8.encode(id), 0, on ? 1 : 0]);

/// Гипотеза B записи (источника нет): `05 число(u16) идентификатор\0 флаг`.
Uint8List buildAppSetB(String id, bool on) =>
    Uint8List.fromList([0x05, 1, 0, ...utf8.encode(id), 0, on ? 1 : 0]);

/// Гипотеза C записи (источника нет): тот же формат, что у ответа `04`, но с командой `05`:
/// `05 число(u16)` и весь список с изменённым флагом одного приложения.
Uint8List buildAppSetAll(List<WatchApp> apps, String id, bool on) {
  final b = <int>[0x05, apps.length & 0xff, (apps.length >> 8) & 0xff];
  for (final a in apps) {
    b
      ..addAll(utf8.encode(a.id))
      ..add(0)
      ..add((a.id == id ? on : a.enabled) ? 1 : 0);
  }
  return Uint8List.fromList(b);
}

/// Названия известных идентификаторов; для остальных показывается сам идентификатор.
String appDisplayName(String id) => switch (id) {
      'ru.oneme.app' => 'MAX',
      'ru.app.gift.mate.prod' => 'GiftMate',
      'com.apple.mobilemail' => 'Почта',
      'ph.telegra.Telegraph' => 'Telegram',
      'net.whatsapp.WhatsApp' => 'WhatsApp',
      'com.apple.MobileSMS' => 'Сообщения',
      _ => id,
    };
