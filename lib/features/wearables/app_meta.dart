// Названия и значки приложений iPhone по их идентификаторам (bundle id).
//
// iOS не отдаёт стороннему приложению ни названия, ни значки чужих программ. Поэтому: встроенная
// таблица системных приложений Apple, публичный поиск App Store (iTunes Lookup) по кнопке и
// запасное имя, выведенное из самого идентификатора. Результат поиска хранится локально.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AppMeta {
  final String name;
  final String? iconUrl;
  const AppMeta(this.name, [this.iconUrl]);

  Map<String, dynamic> toJson() =>
      {'n': name, if (iconUrl != null) 'i': iconUrl};
  static AppMeta fromJson(Map<String, dynamic> j) =>
      AppMeta(j['n'] as String, j['i'] as String?);
}

/// Системные и известные приложения: App Store их не находит или находит не то.
const builtinAppNames = <String, String>{
  'com.apple.mobilephone': 'Телефон',
  'com.apple.MobileSMS': 'Сообщения',
  'com.apple.mobilemail': 'Почта',
  'com.apple.facetime': 'FaceTime',
  'com.apple.mobilecal': 'Календарь',
  'com.apple.reminders': 'Напоминания',
  'com.apple.mobilenotes': 'Заметки',
  'com.apple.Health': 'Здоровье',
  'com.apple.weather': 'Погода',
  'com.apple.AppStore': 'App Store',
  'com.apple.Passbook': 'Wallet',
  'com.apple.Maps': 'Карты',
  'com.apple.Music': 'Музыка',
  'com.apple.podcasts': 'Подкасты',
  'com.apple.news': 'Новости',
  'com.apple.tv': 'TV',
  'com.apple.mobileslideshow': 'Фото',
  'com.apple.mobilesafari': 'Safari',
  'com.apple.shortcuts': 'Команды',
  'com.apple.mobileaddressbook': 'Контакты',
  'ph.telegra.Telegraph': 'Telegram',
  'net.whatsapp.WhatsApp': 'WhatsApp',
  'ru.oneme.app': 'MAX',
  'ru.app.gift.mate.prod': 'GiftMate',
};

const _noise = {
  'com', 'org', 'net', 'io', 'co', 'ru', 'in', 'app', 'apps', 'ios', 'iphone',
  'mobile', 'client', 'prod', 'release', 'the', 'my', 'go',
};

/// Запасное имя из идентификатора: самый длинный значимый сегмент с заглавной буквы.
String deriveAppName(String id) {
  final parts = id.split('.').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return id;
  final cand = parts.where((p) => !_noise.contains(p.toLowerCase())).toList();
  final best = (cand.isEmpty ? parts : cand)
      .reduce((a, b) => b.length > a.length ? b : a);
  return best[0].toUpperCase() + best.substring(1);
}

/// Имя для показа без обращения к сети.
String appName(String id, Map<String, AppMeta> cache) =>
    builtinAppNames[id] ?? cache[id]?.name ?? deriveAppName(id);

Map<String, AppMeta> decodeAppMeta(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map(
        (k, v) => MapEntry(k, AppMeta.fromJson(v as Map<String, dynamic>)));
  } catch (_) {
    return {};
  }
}

String encodeAppMeta(Map<String, AppMeta> m) =>
    jsonEncode(m.map((k, v) => MapEntry(k, v.toJson())));

/// Публичный поиск App Store по одному идентификатору. null — приложение не найдено или ошибка
/// сети. Наружу уходит только идентификатор приложения.
Future<AppMeta?> lookupAppStore(String id) async {
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final uri = Uri.https(
        'itunes.apple.com', '/lookup', {'bundleId': id, 'country': 'ru'});
    final req = await c.getUrl(uri).timeout(const Duration(seconds: 6));
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body) as Map<String, dynamic>;
    final list = (j['results'] as List?) ?? const [];
    if (list.isEmpty) return null;
    final r = list.first as Map<String, dynamic>;
    final name = r['trackName'] as String?;
    if (name == null || name.isEmpty) return null;
    return AppMeta(name, r['artworkUrl60'] as String?);
  } catch (_) {
    return null;
  } finally {
    c.close(force: true);
  }
}
