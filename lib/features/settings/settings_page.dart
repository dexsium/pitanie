import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import 'backup_service.dart';
import 'notification_service.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    final dynamicMode = s['calorie_mode'] == 'dynamic';
    final backup = BackupService(db);

    Future<void> reschedule() async =>
        ref.read(notificationsProvider).reschedule(await db.allSettings());

    Future<void> shareText(String name, String text) async {
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, name));
      await f.writeAsString(text);
      await Share.shareXFiles([XFile(f.path)]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Тема', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('Системная')),
                ButtonSegment(value: 'light', label: Text('Светлая')),
                ButtonSegment(value: 'dark', label: Text('Тёмная')),
              ],
              selected: {s['theme'] ?? 'system'},
              onSelectionChanged: (v) => db.setSetting('theme', v.first),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Расчёт калорий с учётом активности',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fixed', label: Text('Фиксированная')),
                ButtonSegment(value: 'dynamic', label: Text('Динамическая')),
              ],
              selected: {dynamicMode ? 'dynamic' : 'fixed'},
              onSelectionChanged: (v) => db.setSetting('calorie_mode', v.first),
            ),
            const SizedBox(height: 8),
            Text(
                dynamicMode
                    ? 'К цели добавляются активные калории сверх уже учтённых в норме. '
                        'Активные калории — это не весь суточный расход.'
                    : 'Цель не зависит от активности. Активность показывается отдельно.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if (dynamicMode)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Активность, уже учтённая в норме'),
                subtitle: const Text('Эти ккал не добавляются повторно'),
                trailing: Text('${fmt0(double.tryParse(s['included_active_kcal'] ?? '') ?? 0)} ккал'),
                onTap: () async {
                  final v = await promptNumber(context, 'Уже учтённая активность',
                      initial: double.tryParse(s['included_active_kcal'] ?? '') ?? 0,
                      suffix: 'ккал',
                      max: 5000);
                  if (v != null) await db.setSetting('included_active_kcal', '$v');
                },
              ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Уведомления', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            for (final r in reminders)
              _ReminderTile(r, s[r.key] ?? '0|${r.defaultTime}', (v) async {
                await db.setSetting(r.key, v);
                if (v.startsWith('1')) await ref.read(notificationsProvider).requestPermission();
                await reschedule();
              }),
            if (!NotificationService.supported)
              const Text('Уведомления доступны на Android и iOS.', style: TextStyle(fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Данные и резервные копии',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.upload_file),
              title: const Text('Экспорт резервной копии'),
              subtitle: const Text('Полный файл JSON с контрольной суммой'),
              onTap: () async {
                try {
                  final text = await backup.exportJson();
                  await shareText('pitanie_backup_${dayKey(DateTime.now())}.json', text);
                } catch (e) {
                  if (context.mounted) toast(context, 'Ошибка экспорта: $e');
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Экспорт статистики в CSV'),
              onTap: () async {
                try {
                  await shareText('pitanie_stats_${dayKey(DateTime.now())}.csv', await backup.exportCsv());
                } catch (e) {
                  if (context.mounted) toast(context, 'Ошибка экспорта: $e');
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download),
              title: const Text('Восстановить из копии'),
              subtitle: const Text('Текущие данные будут заменены'),
              onTap: () async {
                final res = await FilePicker.pickFiles();
                final path = res.isEmpty ? null : res.first.path;
                if (path == null) return;
                final text = await File(path).readAsString();
                final check = BackupService.verify(text);
                if (!context.mounted) return;
                if (!check.ok) {
                  toast(context, check.message);
                  return;
                }
                final ok = await confirmDialog(context, 'Восстановить данные?',
                    'Файл корректен. Все текущие данные будут заменены данными из копии.',
                    ok: 'Восстановить');
                if (!ok) return;
                try {
                  await backup.restore(text);
                  if (context.mounted) toast(context, 'Данные восстановлены');
                } catch (e) {
                  if (context.mounted) toast(context, 'Ошибка восстановления: $e');
                }
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Text(
            'Все данные хранятся только на этом устройстве. Данные о здоровье не отправляются на сторонние серверы. '
            'Единственный сетевой запрос — поиск штрихкода в Open Food Facts, и только с вашего согласия. '
            'Расчётные нормы ориентировочные и не заменяют консультацию специалиста.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final Reminder r;
  final String value;
  final ValueChanged<String> onChanged;
  const _ReminderTile(this.r, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final parts = value.split('|');
    final on = parts[0] == '1';
    final time = parts.length > 1 ? parts[1] : r.defaultTime;
    final step = parts.length > 2 ? parts[2] : '2';
    final isWater = r.key == 'rem_water';
    String join(bool o, String t, String st) => '${o ? 1 : 0}|$t${isWater ? '|$st' : ''}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(r.title),
      subtitle: Text(isWater ? 'с $time каждые $step ч до 21:00' : time),
      trailing: Switch(value: on, onChanged: (v) => onChanged(join(v, time, step))),
      onTap: () async {
        final hm = time.split(':');
        final t = await showTimePicker(
            context: context, initialTime: TimeOfDay(hour: int.parse(hm[0]), minute: int.parse(hm[1])));
        if (t == null) return;
        final tt = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        onChanged(join(on, tt, step));
      },
    );
  }
}
