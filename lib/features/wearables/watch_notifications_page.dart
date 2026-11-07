// «Уведомления на часах»: что приложение реально может и чего не может на iPhone.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../shared/widgets.dart';
import 'app_meta.dart';
import 'watch_ancs.dart';
import 'zepp_notifications.dart';
import 'wearable_controller.dart';

/// Настройки, которыми приложение управляет само: слать ли свои уведомления.
const kNotifGoalsKey = 'notif_goals';
const kNotifWorkoutsKey = 'notif_workouts';
const kNotifHealthKey = 'notif_health';
const kNotifLinkKey = 'notif_link';

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
  bool _metaBusy = false;
  String? _metaRaw;
  Map<String, AppMeta> _meta = {};

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

  Widget _appIcon(String id, Color muted) {
    final url = _meta[id]?.iconUrl;
    final fallback = CircleAvatar(
        radius: 18,
        backgroundColor: muted.withValues(alpha: 0.15),
        child: Text(appName(id, _meta).characters.first.toUpperCase(),
            style: TextStyle(color: muted, fontWeight: FontWeight.w700)));
    if (url == null) return fallback;
    return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url,
            width: 36, height: 36, errorBuilder: (_, __, ___) => fallback));
  }

  /// Названия и значки из публичного поиска App Store. Наружу уходят только идентификаторы
  /// приложений из списка часов, результат сохраняется локально.
  Future<void> _loadMeta(WatchAppList list) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Загрузить из App Store?'),
              content: const Text(
                  'Приложение отправит идентификаторы приложений из списка часов '
                  '(например, ph.telegra.Telegraph) в публичный поиск App Store компании Apple, '
                  'чтобы получить названия и значки. Содержимое уведомлений и ваши данные не '
                  'отправляются. Системные приложения Apple определяются без сети.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Загрузить')),
              ],
            ));
    if (ok != true || !mounted) return;
    setState(() => _metaBusy = true);
    final next = Map<String, AppMeta>.of(_meta);
    final todo = [
      for (final a in list.apps)
        if (!builtinAppNames.containsKey(a.id) && next[a.id]?.iconUrl == null)
          a.id
    ];
    var found = 0;
    for (var i = 0; i < todo.length; i += 4) {
      final batch = todo.skip(i).take(4).toList();
      final res = await Future.wait(batch.map(lookupAppStore));
      for (var k = 0; k < batch.length; k++) {
        final m = res[k];
        if (m != null) {
          next[batch[k]] = m;
          found++;
        }
      }
      if (!mounted) return;
    }
    await ref.read(dbProvider).setSetting('app_meta', encodeAppMeta(next));
    if (!mounted) return;
    setState(() => _metaBusy = false);
    toast(context, 'Найдено в App Store: $found из ${todo.length}');
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
    if (s['app_meta'] != _metaRaw) {
      _metaRaw = s['app_meta'];
      _meta = decodeAppMeta(_metaRaw);
    }
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
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Техническая информация',
                      style: TextStyle(fontSize: 12.5, color: muted)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(a!.detail!,
                          style: TextStyle(fontSize: 11.5, color: muted)),
                    ),
                  ],
                ),
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
            const Text('Диагностика уведомлений',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            row('Часы подключены по BLE', c.isConnected ? 'да' : 'нет'),
            row(
                'Авторизация часов',
                c.session != null
                    ? 'выполнена'
                    : (c.isConnected ? 'не выполнена' : 'не удалось проверить')),
            row(
                'Доступ часов к уведомлениям iOS',
                switch (a?.state) {
                  AncsState.authorized => 'разрешён',
                  AncsState.denied => 'запрещён',
                  null => 'не удалось проверить',
                  _ => 'не удалось проверить',
                }),
            row(
                'Сервис уведомлений часов (0x001e)',
                switch (c.notifServiceListed) {
                  true => 'подтверждён',
                  false => 'не заявлен',
                  null => 'не удалось проверить',
                }),
            row('Ответ часов на запрос возможностей',
                c.notifCaps != null ? 'получен' : 'не получен'),
            row('Фильтр приложений на часах',
                'не поддерживается: команда неизвестна'),
            row('Подтверждение показа часами', 'недоступно: доставку нельзя проверить программно'),
            if (c.message != null) row('Последняя ошибка', c.message!),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Разговор по часам (Bluetooth-гарнитура)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Разговор через часы'),
              subtitle: Text(
                  c.phoneEnabled == null
                      ? 'Состояние неизвестно: нажмите «Прочитать состояние»'
                      : (c.phoneEnabled! ? 'Включено на часах' : 'Выключено на часах'),
                  style: TextStyle(fontSize: 12, color: muted)),
              value: c.phoneEnabled ?? false,
              onChanged: c.session != null && c.phoneEnabled != null
                  ? (v) async {
                      final err = await c.setPhoneEnabled(v);
                      if (context.mounted) {
                        toast(context, err ?? 'Настройка применена');
                      }
                    }
                  : null,
            ),
            Text(
                'Это функция «говорить по часам» (микрофон и динамик часов как гарнитура), '
                'а не оповещение о входящем звонке. Состояние переключается и подтверждается чтением, '
                'но проверка показала: включение само по себе звонок на часы не приводит. '
                'Оповещение о звонке часы получают от iPhone по ANCS, а сопряжение для разговора '
                'выполняется в «Настройки → Bluetooth» iPhone.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: () async {
                  final err = await c.readPhoneState();
                  if (context.mounted) toast(context, err ?? 'Состояние прочитано');
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Прочитать состояние')),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Приложения на часах',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                'Список читается с самих часов (сервис 0x001f): это приложения iPhone, '
                'уведомления которых часы уже видели. Чтение подтверждено на вашей прошивке. '
                'Запись переключателя экспериментальная: команда записи неизвестна, '
                'приложение пробует две гипотезы и проверяет результат чтением обратно.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: () async {
                  final err = await c.readWatchApps();
                  if (context.mounted) {
                    toast(context, err ?? 'Список прочитан: ${c.watchApps?.apps.length}');
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Прочитать список с часов')),
            if (c.watchApps != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: _metaBusy ? null : () => _loadMeta(c.watchApps!),
                  icon: const Icon(Icons.image_search),
                  label: Text(_metaBusy
                      ? 'Загрузка названий и значков…'
                      : 'Загрузить названия и значки (App Store)')),
            ],
            if (c.watchApps != null) ...[
              const SizedBox(height: 4),
              Text(
                  'Заявлено часами: ${c.watchApps!.declared}, разобрано: ${c.watchApps!.apps.length}'
                  '${c.watchApps!.consistent ? '' : ' (структура не сошлась)'}',
                  style: TextStyle(fontSize: 12, color: muted)),
              for (final a in c.watchApps!.apps)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: _appIcon(a.id, muted),
                  title: Text(appName(a.id, _meta)),
                  subtitle:
                      Text(a.id, style: TextStyle(fontSize: 11, color: muted)),
                  value: a.enabled,
                  onChanged: (v) async {
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                              title: const Text('Экспериментальная запись'),
                              content: Text(
                                  'Команда записи для «${appName(a.id, _meta)}» неизвестна. '
                                  'Приложение сохранит копию списка и попробует две гипотезы, '
                                  'проверяя результат. Есть риск, что часы изменят список. '
                                  'Продолжить?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Отмена')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Продолжить')),
                              ],
                            ));
                    if (ok != true || !context.mounted) return;
                    final r = await c.trySetWatchApp(a.id, v);
                    if (context.mounted) toast(context, r);
                  },
                ),
            ],
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
            const Text('Прямая отправка на часы (экспериментально)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            row(
                'Сервис уведомлений Zepp OS',
                switch (c.notifServiceListed) {
                  true => 'заявлен часами',
                  false => 'не заявлен',
                  null => 'неизвестно',
                }),
            if (c.notifCaps != null)
              row('Версия протокола', '${c.notifCaps!.version}'),
            const SizedBox(height: 6),
            Text(
                'Приложение может отправить уведомление на часы само, по их собственному протоколу, '
                'в обход списка приложений Zepp. Формат взят из открытого проекта Gadgetbridge и на '
                'вашей прошивке не проверен. Часы не подтверждают показ: успех это только появление '
                'уведомления на экране часов.',
                style: TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: () async {
                  final err = await c.sendWatchTestNotification();
                  if (context.mounted) {
                    toast(context,
                        err ?? 'Отправлено. Посмотрите на экран часов.');
                  }
                },
                icon: const Icon(Icons.watch_outlined),
                label: const Text('Отправить тест на часы')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: () async {
                  // Только строки про уведомления и сервис 0x001e, без остальных данных часов.
                  final lines = c.log
                      .where((l) =>
                          l.contains('уведомлен') ||
                          l.contains('0x001e') ||
                          l.contains('приложения на часах') ||
                          l.contains('запись приложения'))
                      .toList();
                  final text = 'Версия приложения: $_ver\n'
                      'Прошивка часов: ${c.fw ?? '—'}\n'
                      'Сервис 0x001e: ${switch (c.notifServiceListed) {
                    true => 'заявлен',
                    false => 'не заявлен',
                    null => 'неизвестно',
                  }}\n'
                      '${lines.isEmpty ? '(в журнале нет строк про уведомления: сначала нажмите «Отправить тест на часы»)' : lines.join('\n')}';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    toast(context,
                        'Скопировано (${lines.length} строк). Вставьте в чат.');
                  }
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Скопировать журнал уведомлений')),
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
            sw('Предупреждение о связи с часами',
                'При сворачивании: не закрывайте приложение, иначе связь оборвётся',
                kNotifLinkKey),
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
