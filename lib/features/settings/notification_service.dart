import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Reminder {
  final String key, title, body;
  final int id;
  final String defaultTime;
  const Reminder(this.key, this.id, this.title, this.body, this.defaultTime);
}

const reminders = [
  Reminder('rem_breakfast', 1, 'Завтрак', 'Запишите завтрак в дневник', '08:30'),
  Reminder('rem_lunch', 2, 'Обед', 'Запишите обед в дневник', '13:00'),
  Reminder('rem_dinner', 3, 'Ужин', 'Запишите ужин в дневник', '19:00'),
  Reminder('rem_water', 4, 'Вода', 'Пора выпить воды', '10:00'),
  Reminder('rem_weight', 5, 'Вес', 'Внесите текущий вес', '07:30'),
  Reminder('rem_diary', 6, 'Дневник', 'Заполните дневник питания за сегодня', '21:30'),
];

/// Значение настройки: "1|08:30" (включено|время). Для воды: "1|10:00|2"
/// (с какого времени, интервал в часах; до 21:00).
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    if (!supported || _ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {}
    await _plugin.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false),
    ));
    _ready = true;
  }

  Future<bool> requestPermission() async {
    if (!supported) return false;
    await init();
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (a != null) return (await a.requestNotificationsPermission()) ?? false;
    final i = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return (await i?.requestPermissions(alert: true, badge: true, sound: true)) ??
        false;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'Напоминания',
            importance: Importance.defaultImportance),
        iOS: DarwinNotificationDetails(),
      );

  tz.TZDateTime _next(int h, int m) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// Пересоздаёт все уведомления по сохранённым настройкам.
  Future<void> reschedule(Map<String, String> settings) async {
    if (!supported) return;
    await init();
    await _plugin.cancelAll();
    for (final r in reminders) {
      final parts = (settings[r.key] ?? '0|${r.defaultTime}').split('|');
      if (parts[0] != '1') continue;
      final hm = parts[1].split(':');
      final h = int.parse(hm[0]), m = int.parse(hm[1]);
      if (r.key == 'rem_water') {
        final step = parts.length > 2 ? int.tryParse(parts[2]) ?? 2 : 2;
        var i = 0;
        for (var hh = h; hh <= 21; hh += step) {
          await _schedule(r.id * 100 + i++, r.title, r.body, hh, m);
        }
      } else {
        await _schedule(r.id, r.title, r.body, h, m);
      }
    }
  }

  Future<void> _schedule(int id, String title, String body, int h, int m) =>
      _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: _next(h, m),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time);
}
