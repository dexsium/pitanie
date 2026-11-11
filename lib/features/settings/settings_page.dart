import '../coach/goal_service.dart';
import '../reports/report_page.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pitanie_widgets/pitanie_widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../ai/ai_settings_card.dart';
import '../ai/gemini_service.dart' show writeAiKey;
import '../../app/theme.dart' show kRed;
import '../../core/dates.dart';
import '../../core/nutrition/nutrition_calculation_models.dart';
import '../../services/health/plan_service.dart';
import '../../shared/widgets.dart';
import 'backup_service.dart';
import '../widgets/widget_sync.dart';
import '../body/measurements_page.dart' show deletePhotoFiles;
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
      body: ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom), children: [
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Тема',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
        const AiSettingsCard(),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Режим расчёта норм',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            SegmentedButton<CalcMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: CalcMode.adaptive, label: Text('Адаптивный')),
                ButtonSegment(value: CalcMode.standard, label: Text('Формулы')),
                ButtonSegment(value: CalcMode.manual, label: Text('Вручную')),
              ],
              selected: {calcModeOf(s[kCalcModeKey])},
              onSelectionChanged: (v) => setCalcMode(db, v.first),
            ),
            const SizedBox(height: 8),
            Text(
                switch (calcModeOf(s[kCalcModeKey])) {
                  CalcMode.adaptive =>
                    'Нормы считаются по формуле Миффлина — Сан Жеора. При достаточных данных о весе и '
                        'питании (не менее 2–3 недель) приложение раз в две недели предлагает изменить '
                        'калорийность на 100–150 ккал; без вашего согласия нормы не меняются.',
                  CalcMode.standard =>
                    'Только стандартные формулы, без поправок по динамике веса. Нормы меняются кнопкой «Пересчитать» в профиле.',
                  CalcMode.manual =>
                    'Нормы заданы вами и автоматически не перезаписываются. Кнопка «Пересчитать» работает только по вашей команде.',
                },
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if (calcModeOf(s[kCalcModeKey]) == CalcMode.adaptive)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Применять предложения автоматически'),
                subtitle:
                    const Text('В профиле появится кнопка «Отменить» на 3 дня'),
                value: s[kCalcAutoApplyKey] == '1',
                onChanged: (v) =>
                    db.setSetting(kCalcAutoApplyKey, v ? '1' : '0'),
              ),
            if (parseHistory(s[kCalcHistoryKey]).isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('История расчётов',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              for (final h in parseHistory(s[kCalcHistoryKey]).reversed.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${shortDate(h.at)}: ${h.text}',
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurfaceVariant)),
                ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                trailing: Text(
                    '${fmt0(double.tryParse(s['included_active_kcal'] ?? '') ?? 0)} ккал'),
                onTap: () async {
                  final v = await promptNumber(
                      context, 'Уже учтённая активность',
                      initial:
                          double.tryParse(s['included_active_kcal'] ?? '') ?? 0,
                      suffix: 'ккал',
                      max: 5000);
                  if (v != null)
                    await db.setSetting('included_active_kcal', '$v');
                },
              ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Уведомления',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            for (final r in reminders)
              _ReminderTile(r, s[r.key] ?? '0|${r.defaultTime}', (v) async {
                await db.setSetting(r.key, v);
                if (v.startsWith('1'))
                  await ref.read(notificationsProvider).requestPermission();
                await reschedule();
              }),
            _ReminderTile(coachReminder,
                s[coachReminder.key] ?? '1|${coachReminder.defaultTime}',
                (v) async {
              await db.setSetting(coachReminder.key, v);
              if (v.startsWith('1')) {
                await ref.read(notificationsProvider).requestPermission();
              }
              await updateCoach(db, ref.read(notificationsProvider));
            }),
            Text(
                'Вечером приложение подсказывает, чем добрать недостающие калории и БЖУ, '
                'а при выполнении целей дня присылает уведомление. Подсказка считается по '
                'вашему дневнику на момент последнего открытия приложения.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if (!NotificationService.supported)
              const Text('Уведомления доступны на Android и iOS.',
                  style: TextStyle(fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: FutureBuilder<bool>(
            future: PitanieWidgets.isSupported(),
            builder: (context, snap) {
              final supported = snap.data ?? false;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Виджеты главного экрана',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (!supported)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        Platform.isIOS
                            ? 'Виджет для iPhone в этой сборке ещё не включён: ему нужна дополнительная '
                                'настройка подписи Apple (группа приложений). Пока на iPhone виджета нет. '
                                'Виджеты уже работают на Android.'
                            : 'Виджеты недоступны на этом устройстве.',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                  )
                else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widgetsEnabled(ref.watch(settingsProvider).valueOrNull ?? const {}),
                    title: const Text('Показывать данные в виджетах'),
                    subtitle: const Text(
                        'Калории, белки, жиры, углеводы и вода за сегодня видны на главном экране телефона '
                        'всем, кто его видит. По умолчанию выключено.'),
                    onChanged: (v) async {
                      await db.setSetting(kWidgetsEnabledKey, v ? '1' : '0');
                      await pushWidgetsNow(db);
                    },
                  ),
                  Text(
                      'Добавление виджета: долгое нажатие на пустое место главного экрана → «Виджеты» → '
                      '«Питание: калории» (малый) или «Питание: день» (средний). Нажатие на кнопки '
                      'виджета открывает приложение: вода и вес добавляются уже внутри него.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ],
              ]);
            },
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  await shareText(
                      'pitanie_backup_${dayKey(DateTime.now())}.json', text);
                } catch (e) {
                  if (context.mounted) toast(context, 'Ошибка экспорта: $e');
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF-отчёт за период'),
              subtitle: const Text('Просмотр, сохранение и отправка'),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ReportPage())),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Экспорт статистики в CSV'),
              onTap: () async {
                try {
                  await shareText('pitanie_stats_${dayKey(DateTime.now())}.csv',
                      await backup.exportCsv());
                } catch (e) {
                  if (context.mounted) toast(context, 'Ошибка экспорта: $e');
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Проверить целостность данных'),
              subtitle: const Text('Проверка файла базы на ошибки'),
              onTap: () async {
                final problems = await db.integrityProblems();
                if (!context.mounted) return;
                toast(context,
                    problems.isEmpty ? 'Ошибок в данных не найдено' : 'Найдены проблемы: ${problems.take(3).join('; ')}');
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
                  final docs = await getApplicationDocumentsDirectory();
                  await BackupService(db, snapshotDir: p.join(docs.path, 'backups'))
                      .restore(text);
                  if (context.mounted) {
                    toast(context, 'Данные восстановлены. Прежние данные сохранены в снимке.');
                  }
                } catch (e) {
                  if (context.mounted)
                    toast(context, 'Ошибка восстановления: $e');
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_forever_outlined, color: kRed),
              title: const Text('Удалить все мои данные', style: TextStyle(color: kRed)),
              subtitle: const Text('Дневник, вес, активность, цели, настройки и ключ ИИ'),
              onTap: () async {
                if (!await confirmDialog(context, 'Удалить все данные?',
                    'Будут безвозвратно удалены дневник, вода, вес, активность, тренировки, цели, блюда, шаблоны и настройки на этом устройстве. Данные в Apple Health / Health Connect не затрагиваются. Перед удалением можно сделать резервную копию.',
                    ok: 'Продолжить')) {
                  return;
                }
                if (!context.mounted) return;
                if (!await confirmDialog(context, 'Точно удалить?',
                    'Отменить это действие нельзя.',
                    ok: 'Удалить всё')) {
                  return;
                }
                final photos = [for (final x in await db.allProgressPhotos()) x.fileName];
                await db.wipeUserData();
                await deletePhotoFiles(photos);
                await pushWidgetsNow(db);
                await writeAiKey(null);
                if (context.mounted) toast(context, 'Все данные удалены');
              },
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Источники данных о продуктах',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
                'Справочник встроен в приложение и работает без интернета: USDA FoodData Central '
                '(SR Legacy и FNDDS 2021–2023), общедоступные данные (CC0), значения на 100 г '
                'съедобной части без изменений. Отметка «USDA» означает, что число взято из '
                'официального справочника, а не измерено в лаборатории для вашего продукта.\n\n'
                'Названия USDA английские; русские переводы добавлены только для части записей '
                'по проверяемому глоссарию, остальные остаются на английском.\n\n'
                'Штрихкоды: Open Food Facts (участники проекта), лицензия ODbL 1.0, '
                'https://world.openfoodfacts.org. Запрос отправляется только с вашего согласия '
                'и содержит только штрихкод; сохранённая запись — ваша личная копия.\n\n'
                'Записи с пометкой «Ориентировочные значения» — типовые оценки, сверяйте с упаковкой.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 14),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => AppCard(
            child: Text(
              snap.hasData
                  ? 'Версия ${snap.data!.version} (сборка ${snap.data!.buildNumber})'
                  : 'Версия…',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Text(
            'Все данные хранятся только на этом устройстве. Данные о здоровье не отправляются на сторонние серверы. '
            'Сетевые запросы выполняются только по вашему действию: поиск штрихкода в Open Food Facts '
            'и, если вы включили помощника, отправка фото еды или данных рациона в Google Gemini по вашему ключу. '
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
    String join(bool o, String t, String st) =>
        '${o ? 1 : 0}|$t${isWater ? '|$st' : ''}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(r.title),
      subtitle: Text(isWater ? 'с $time каждые $step ч до 21:00' : time),
      trailing:
          Switch(value: on, onChanged: (v) => onChanged(join(v, time, step))),
      onTap: () async {
        final hm = time.split(':');
        final t = await showTimePicker(
            context: context,
            initialTime:
                TimeOfDay(hour: int.parse(hm[0]), minute: int.parse(hm[1])));
        if (t == null) return;
        final tt =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        onChanged(join(on, tt, step));
      },
    );
  }
}
