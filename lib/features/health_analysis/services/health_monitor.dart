import '../../../database/database.dart';
import '../data/health_repository.dart';
import 'health_notification_engine.dart';

typedef ShowNotification = Future<void> Function(
    int id, String title, String body, bool urgent);

/// Проверка после синхронизации, при запуске и при возврате в приложение. Фоновых задач
/// (WorkManager/BGTask) нет: при закрытом приложении анализ не выполняется.
/// Возвращает число отправленных уведомлений.
Future<int> runHealthMonitor(AppDatabase db, ShowNotification show,
    {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final snap = await loadHealth(db, at);
  final picks = selectForDelivery(snap.insights, snap.history, snap.prefs, at);
  if (picks.isEmpty) return 0;
  final history = [...snap.history];
  for (final i in picks) {
    final t = notificationText(i, privacy: snap.prefs.privacy);
    await show(
        i.key.hashCode & 0x3fffffff, t.title, t.body, i.severity.index >= 3);
    history.add(NotifyEntry(i, at));
  }
  await db.setSetting(kHmHist, encodeNotifyHistory(history));
  return picks.length;
}
