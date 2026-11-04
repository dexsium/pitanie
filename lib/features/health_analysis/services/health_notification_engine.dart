import 'dart:convert';

import '../domain/models/health_models.dart';

class NotifyEntry {
  final Insight insight;
  final DateTime sentAt;
  const NotifyEntry(this.insight, this.sentAt);
}

List<NotifyEntry> parseNotifyHistory(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final l = jsonDecode(raw);
    if (l is! List) return const [];
    final out = <NotifyEntry>[];
    for (final e in l) {
      if (e is! Map) continue;
      final i = Insight.fromJson(e['i']);
      final at = DateTime.tryParse('${e['s']}');
      if (i != null && at != null) out.add(NotifyEntry(i, at));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String encodeNotifyHistory(List<NotifyEntry> h) {
  final cut = h.length > 100 ? h.sublist(h.length - 100) : h;
  return jsonEncode([
    for (final e in cut)
      {'i': e.insight.toJson(), 's': e.sentAt.toIso8601String()}
  ]);
}

/// Какие выводы показывать пользователю прямо сейчас.
///  * категория выключена → нет;
///  * то же событие (ключ) уже отправлялось → нет (подавление повторов);
///  * тихие часы → откладывается (не записывается, отправится позже), кроме срочных;
///  * информационные — не чаще одного за [HealthPrefs.infoEveryDays];
///  * рекомендации и «требует внимания» одной категории — не чаще раза в сутки.
List<Insight> selectForDelivery(List<Insight> candidates,
    List<NotifyEntry> history, HealthPrefs prefs, DateTime now) {
  if (!prefs.auto) return const [];
  final sent = {for (final h in history) h.insight.key};
  final out = <Insight>[];
  var infoSent = history.any((h) =>
      h.insight.severity == Severity.info &&
      now.difference(h.sentAt).inHours < prefs.infoEveryDays * 24);
  final ordered = [...candidates]
    ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
  for (final c in ordered) {
    if (!prefs.enabled(c.category)) continue;
    if (sent.contains(c.key)) continue;
    if (prefs.inQuiet(now) && c.severity != Severity.urgent) continue;
    if (c.severity == Severity.info) {
      if (infoSent) continue;
      infoSent = true;
    } else if (c.severity != Severity.urgent) {
      final recent = history.any((h) =>
          h.insight.category == c.category &&
          h.insight.severity != Severity.info &&
          now.difference(h.sentAt).inHours < 24);
      if (recent ||
          out.any(
              (o) => o.category == c.category && o.severity != Severity.info)) {
        continue;
      }
    }
    out.add(c);
  }
  return out;
}

/// Текст уведомления. В режиме приватности подробности не показываются на экране блокировки.
({String title, String body}) notificationText(Insight i,
    {required bool privacy}) {
  if (privacy) {
    return (
      title: 'Анализ здоровья',
      body: 'Есть новое наблюдение. Откройте приложение.'
    );
  }
  final firstSentence = i.body.split(RegExp(r'(?<=[.!?])\s')).first;
  return (title: i.title, body: firstSentence);
}
