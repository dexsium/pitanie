import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets.dart';
import 'watch_settings.dart';
import 'wearable_controller.dart';

/// Настройки самих часов: мониторинг, время, «найти часы». Открывается шестерёнкой
/// на странице «Умные часы». Значения читаются с часов и после записи проверяются чтением.
class WatchSettingsPage extends ConsumerStatefulWidget {
  const WatchSettingsPage({super.key});

  @override
  ConsumerState<WatchSettingsPage> createState() => _WatchSettingsPageState();
}

class _WatchSettingsPageState extends ConsumerState<WatchSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = ref.read(wearableProvider);
      if (c.session != null && c.watchCfg == null) c.readWatchSettings();
    });
  }

  void _say(String? err, String ok) {
    if (!mounted) return;
    toast(context, err ?? ok);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(wearableProvider);
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final cfg = c.watchCfg;
    final ready = c.session != null && !c.cfgBusy;
    final canEdit = ready && cfg != null;

    Widget sw(String title, String sub, bool? value, int key) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(sub, style: TextStyle(fontSize: 12, color: muted)),
          value: value ?? false,
          onChanged: canEdit && value != null
              ? (v) async => _say(
                  await c.writeWatchSettings({key: v}), 'Настройка применена')
              : null,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки часов')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (c.session == null)
          AppCard(
            child: Text(
                'Часы не подключены или не авторизованы. Подключите часы на странице «Умные часы» '
                'и вернитесь сюда: настройки читаются и записываются по Bluetooth.',
                style: TextStyle(color: muted)),
          ),
        if (c.session != null && cfg == null && !c.cfgBusy)
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.cfgMsg ?? 'Настройки с часов ещё не прочитаны.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: c.readWatchSettings,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Прочитать с часов')),
            ]),
          ),
        if (c.cfgBusy)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: 4),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Мониторинг',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                'Чем чаще измерения, тем точнее «Анализ здоровья», но быстрее садится батарея часов.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 10),
            Row(children: [
              const Expanded(child: Text('Измерение пульса в течение дня')),
              DropdownButton<int>(
                value: cfg?.hrInterval != null &&
                        hrIntervals.contains(cfg!.hrInterval)
                    ? cfg.hrInterval
                    : null,
                hint: const Text('—'),
                items: [
                  for (final v in hrIntervals)
                    DropdownMenuItem(value: v, child: Text(hrIntervalLabel(v)))
                ],
                onChanged: canEdit
                    ? (v) async {
                        if (v == null) return;
                        _say(await c.writeWatchSettings({keyHrInterval: v}),
                            'Интервал изменён');
                      }
                    : null,
              ),
            ]),
            const Divider(),
            sw(
                'SpO₂ в течение суток',
                'Автоматические измерения кислорода в крови',
                cfg?.spo2AllDay,
                keySpo2AllDay),
            sw(
                'Точный мониторинг сна (пульс во сне)',
                'Часы используют пульс для определения сна',
                cfg?.sleepHr,
                keySleepHr),
            sw('Дыхание во сне', 'Качество дыхания ночью', cfg?.sleepBreathing,
                keySleepBreathing),
            sw(
                'Мониторинг стресса',
                'Автоматическая оценка стресса в течение дня',
                cfg?.stress,
                keyStress),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: ready ? c.readWatchSettings : null,
                    child: const Text('Обновить с часов')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                    onPressed: canEdit
                        ? () async => _say(
                            await c.restoreOriginalWatchSettings(),
                            'Возвращены исходные значения')
                        : null,
                    child: const Text('Вернуть исходные')),
              ),
            ]),
            if (c.cfgMsg != null && cfg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.cfgMsg!,
                    style: TextStyle(fontSize: 12, color: cs.error)),
              ),
            const SizedBox(height: 6),
            Text(
                '«Исходные» — значения, которые были на часах, когда приложение прочитало их '
                'в первый раз.',
                style: TextStyle(fontSize: 11.5, color: muted)),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Время',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                'Устанавливает на часах текущее время и часовой пояс телефона.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: const Text('Синхронизировать время'),
              onPressed: c.session == null
                  ? null
                  : () async =>
                      _say(await c.syncWatchTime(), 'Время на часах обновлено'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Найти часы',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                'Часы будут вибрировать и подавать сигнал, пока вы не остановите поиск.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: Icon(c.finding ? Icons.stop : Icons.vibration),
              label: Text(c.finding ? 'Остановить' : 'Найти часы'),
              onPressed: c.session == null
                  ? null
                  : () async => _say(await c.findWatch(!c.finding),
                      c.finding ? 'Часы ищут…' : 'Поиск остановлен'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Text(
            'Команды сверены по открытому проекту Gadgetbridge и могут вести себя по-разному на '
            'разных моделях и прошивках. Если часы не приняли изменение, приложение сообщит об этом '
            'и в «Диагностике» страницы «Умные часы» останется журнал обмена.',
            style: TextStyle(fontSize: 12, color: muted)),
      ]),
    );
  }
}
