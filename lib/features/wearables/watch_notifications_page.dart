// «Уведомления на часах»: что приложение реально может и чего не может на iPhone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../shared/widgets.dart';
import 'watch_ancs.dart';
import 'wearable_controller.dart';

/// Настройки, которыми приложение управляет само: слать ли свои уведомления.
const kNotifGoalsKey = 'notif_goals';
const kNotifWorkoutsKey = 'notif_workouts';
const kNotifHealthKey = 'notif_health';

bool notifEnabled(Map<String, String> settings, String key) =>
    settings[key] != '0';

class WatchNotificationsPage extends ConsumerStatefulWidget {
  const WatchNotificationsPage({super.key});

  @override
  ConsumerState<WatchNotificationsPage> createState() =>
      _WatchNotificationsPageState();
}

class _WatchNotificationsPageState
    extends ConsumerState<WatchNotificationsPage> {
  AncsStatus? _ancs;
  String _ver = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _ver = '${i.version}+${i.buildNumber}');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final st = await WatchAncs.status(ref.read(wearableProvider).savedId);
    if (mounted) {
      setState(() {
        _ancs = st;
        _busy = false;
      });
    }
  }

  Future<void> _test() async {
    final n = ref.read(notificationsProvider);
    await n.requestPermission();
    await n.scheduleOnce(
        9099,
        'Проверка уведомлений',
        'Если вы видите это на часах, уведомления приложения доходят.',
        DateTime.now().add(const Duration(seconds: 10)));
    if (mounted) {
      toast(context,
          'Уведомление придёт через 10 секунд. Заблокируйте телефон и смотрите на часы.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(wearableProvider);
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final a = _ancs;

    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(k, style: TextStyle(color: muted))),
            const SizedBox(width: 12),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );

    Widget sw(String title, String sub, String key) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(sub, style: TextStyle(fontSize: 12, color: muted)),
          value: notifEnabled(s, key),
          onChanged: (v) => db.setSetting(key, v ? '1' : '0'),
        );

    final String ancsHint = switch (a?.state) {
      AncsState.authorized =>
        'iOS разрешил часам читать системные уведомления iPhone. Какие именно приложения '
            'показываются, решают настройки уведомлений iOS и сами часы.',
      AncsState.denied =>
        'Включите «Настройки → Bluetooth → Amazfit GTR 4 (значок i) → Делиться системными '
            'уведомлениями».',
      AncsState.watchNotFound =>
        'iOS не знает эти часы. Они должны быть сопряжены в «Настройки → Bluetooth», '
            'иначе системные уведомления на них не идут.',
      AncsState.bluetoothOff => 'Включите Bluetooth на iPhone.',
      AncsState.noBluetoothAccess =>
        'Разрешите приложению Bluetooth в «Настройки → Питание».',
      AncsState.unsupported =>
        WatchAncs.supported ? '' : 'Проверка доступна только на iPhone.',
      _ =>
        'Статус определить не удалось, это не означает, что уведомления не работают.',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления на часах')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Системные уведомления iPhone',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            row('Часы', c.savedId == null ? 'не сохранены' : 'сохранены'),
            row('Связь с приложением', c.isConnected ? 'есть' : 'нет'),
            if (c.fw != null) row('Прошивка', c.fw!),
            if (_ver.isNotEmpty) row('Версия приложения', _ver),
            row('Доступ часов к уведомлениям iOS',
                _busy ? 'проверка…' : (a?.title ?? '—')),
            if (a?.detail != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(a!.detail!,
                    style: TextStyle(fontSize: 11.5, color: muted)),
              ),
            if (a != null && ancsHint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(ancsHint, style: TextStyle(fontSize: 12.5, color: muted)),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.refresh),
                label: const Text('Проверить')),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Звонки, сообщения, Telegram, WhatsApp',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
                'Эти уведомления часы получают от самого iPhone по Bluetooth, наше приложение их не видит '
                'и выбирать приложения не может: iOS не даёт такой возможности сторонним приложениям. '
                'Переключателей здесь поэтому нет.',
                style: TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 8),
            const Text('Как настроить:',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                '1. Общий доступ: «Настройки → Bluetooth → Amazfit GTR 4 → i → Делиться системными '
                'уведомлениями».\n'
                '2. Нужное приложение: «Настройки → Уведомления → приложение», оно должно показывать '
                'уведомления.\n'
                '3. Список приложений на самих часах задаёт Zepp («Уведомления и напоминания»). Чтобы его '
                'изменить, временно разрешите Zepp Bluetooth.\n'
                '4. Режим «Фокус» на iPhone может глушить уведомления для часов.',
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Уведомления этого приложения',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            sw(
                'Цели дня и «Добор нормы»',
                'Норма белка, калорий, воды, шагов, вечерняя подсказка',
                kNotifGoalsKey),
            sw('Тренировки по пульсу', 'Похоже на тренировку, подтвердите',
                kNotifWorkoutsKey),
            sw('Анализ здоровья', 'Отклонения пульса, SpO₂, сна и другие',
                kNotifHealthKey),
            Text(
                'Напоминания о еде и воде включаются в «Настройки → Уведомления». '
                'На часах эти уведомления показываются так же, как остальные, если iOS их передаёт.',
                style: TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _test,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Тестовое уведомление через 10 с')),
          ]),
        ),
      ]),
    );
  }
}
