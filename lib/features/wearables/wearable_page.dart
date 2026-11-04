import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import '../dashboard/day_data.dart' show sourceLabel;
import '../health_integration/devices_page.dart';
import 'heart_rate_page.dart';
import 'huami_auth.dart';
import 'wearable_controller.dart';

/// Раздел «Умные часы». Вся логика связи живёт в [WearableController] и работает
/// независимо от этой страницы; здесь только отображение и поиск новых часов.
class WearablePage extends ConsumerStatefulWidget {
  const WearablePage({super.key});
  @override
  ConsumerState<WearablePage> createState() => _WearablePageState();
}

class _WearablePageState extends ConsumerState<WearablePage> {
  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  List<ScanResult> _results = [];
  bool _scanning = false, _showAll = false;
  String? _scanError;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(FlutterBluePlus.adapterState.listen((s) => setState(() => _adapter = s)));
    _subs.add(FlutterBluePlus.scanResults.listen((r) => setState(() => _results = r)));
    _subs.add(FlutterBluePlus.isScanning.listen((s) => setState(() => _scanning = s)));
    ref.read(wearableProvider).start();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  String _name(ScanResult r) => r.advertisementData.advName.isNotEmpty
      ? r.advertisementData.advName
      : r.device.platformName;

  bool _isCandidate(ScanResult r) {
    final n = _name(r).toLowerCase();
    if (n.contains('amazfit') || n.contains('gtr') || n.contains('zepp')) return true;
    return r.advertisementData.serviceUuids.any((u) {
      final x = u.str.toLowerCase();
      return x.startsWith('0000fee0') || x.startsWith('0000fee1') || x == 'fee0' || x == 'fee1';
    });
  }

  String _details(ScanResult r) {
    final ad = r.advertisementData;
    return [
      if (ad.serviceUuids.isNotEmpty) 'службы: ${ad.serviceUuids.map((u) => u.str).join(', ')}',
      if (ad.manufacturerData.isNotEmpty)
        'производитель: ${ad.manufacturerData.keys.map((k) => '0x${k.toRadixString(16)}').join(', ')}',
      ad.connectable ? 'подключаемое' : 'не подключаемое',
    ].join(' • ');
  }

  Future<void> _scan() async {
    setState(() => _scanError = null);
    try {
      if (_adapter != BluetoothAdapterState.on) {
        setState(() => _scanError = 'Bluetooth выключен. Включите его и повторите поиск.');
        return;
      }
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      setState(() => _scanError = 'Не удалось начать поиск: $e');
    }
  }

  Future<void> _connectNew(BluetoothDevice d) async {
    final c = ref.read(wearableProvider);
    if (await c.connect(d)) {
      await c.refreshKeyState();
      if (c.hasKey) await c.authorize();
    }
  }

  Future<void> _enterKey() async {
    final c = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ключ авторизации Zepp'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                '32 символа (0-9, a-f), можно с префиксом 0x. '
                'Ключ хранится в защищённом хранилище телефона и не отправляется никуда.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
                controller: c,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: 'Ключ', errorText: err)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
                onPressed: () async {
                  if (await AuthKeyStore.save(c.text)) {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    setD(() => err = 'Нужно 32 hex-символа');
                  }
                },
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    c.clear();
    if (ok == true) await ref.read(wearableProvider).refreshKeyState();
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(wearableProvider);
    final cs = Theme.of(context).colorScheme;
    final shown = _results.where((r) => _showAll || _isCandidate(r)).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(title: const Text('Умные часы')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Text(
            'Приложение само подключается к сохранённым часам при запуске и держит связь, пока работает. '
            'На iOS система может приостановить приложение в фоне, а после принудительного закрытия связь '
            'не поддерживается. Пропущенное время подтягивается из памяти часов при следующем подключении.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        if (!c.isConnected) ..._search(context, c, shown) else ..._connected(context, c),
      ]),
    );
  }

  List<Widget> _search(BuildContext context, WearableController c, List<ScanResult> shown) {
    final cs = Theme.of(context).colorScheme;
    return [
      if (c.status == WearStatus.connecting)
        const AppCard(
            child: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 12),
          Expanded(child: Text('Подключение к часам…')),
        ])),
      if (c.savedId != null && c.status != WearStatus.connecting) ...[
        FilledButton.tonalIcon(
            onPressed: () => c.reconnect(),
            icon: const Icon(Icons.bluetooth_connected),
            label: const Text('Подключиться к сохранённым часам')),
        TextButton(onPressed: c.forget, child: const Text('Забыть сохранённые часы')),
      ],
      if (c.message != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(c.message!, style: TextStyle(color: cs.error))),
      FilledButton.icon(
          onPressed: _scanning || c.status == WearStatus.connecting ? null : _scan,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(_scanning ? 'Поиск…' : 'Найти часы')),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Показывать все устройства'),
          subtitle: const Text('Для диагностики, если часы не находятся'),
          value: _showAll,
          onChanged: (v) => setState(() => _showAll = v)),
      if (_scanError != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_scanError!, style: TextStyle(color: cs.error))),
      if (shown.isEmpty && !_scanning)
        const EmptyHint('Часы не найдены. Проверьте: на часах включён Bluetooth, Zepp закрыт '
            'и не держит соединение. Если не помогло, включите «Показывать все устройства».'),
      for (final r in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            onTap: () => _connectNew(r.device),
            child: Row(children: [
              const Icon(Icons.watch_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name(r).isEmpty ? 'Без названия' : _name(r),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(r.device.remoteId.str,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  Text(_details(r), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                ]),
              ),
              Text('${r.rssi} dBm'),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _connected(BuildContext context, WearableController c) {
    final cs = Theme.of(context).colorScheme;
    return [
      _header(context, c),
      const SizedBox(height: 12),
      _authCard(context, c),
      const SizedBox(height: 12),
      ..._metrics(context, c),
      Row(children: [
        Expanded(
          child: FilledButton.icon(
              onPressed: c.session == null || c.syncBusy ? null : c.refresh,
              icon: const Icon(Icons.sync),
              label: Text(c.syncBusy ? 'Загрузка…' : 'Синхронизировать')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
              onPressed: _openHr,
              icon: const Icon(Icons.show_chart),
              label: const Text('График пульса')),
        ),
      ]),
      if (c.syncMsg != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(c.syncMsg!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const DevicesPage())),
              icon: const Icon(Icons.tune),
              label: const Text('Источники')),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
              onPressed: c.disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Отключить')),
        ),
      ]),
      const SizedBox(height: 16),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Диагностика', style: TextStyle(fontWeight: FontWeight.w700)),
          children: [
            if (c.log.isNotEmpty)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Журнал обмена', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final l in c.log)
                    Text(l, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ]),
              ),
            for (final sv in c.services)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sv.uuid.str, style: const TextStyle(fontWeight: FontWeight.w700)),
                  for (final ch in sv.characteristics)
                    Text(
                        '  ${ch.uuid.str}  '
                        '${ch.properties.read ? 'R' : ''}${ch.properties.write ? 'W' : ''}'
                        '${ch.properties.notify ? 'N' : ''}',
                        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                ]),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _header(BuildContext context, WearableController c) {
    final cs = Theme.of(context).colorScheme;
    final bat = c.battery;
    final statusText = switch (c.status) {
      WearStatus.ready => 'Подключено и авторизовано',
      WearStatus.authorizing => 'Авторизация…',
      _ => 'Подключено (Bluetooth)',
    };
    return AppCard(
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.14), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.watch_outlined, color: kPrimary, size: 30),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Amazfit GTR 4',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Row(children: [
              Icon(Icons.circle, size: 10, color: c.status == WearStatus.ready ? kGreen : kOrange),
              const SizedBox(width: 6),
              Flexible(child: Text(statusText)),
            ]),
            if (c.charging) const Text('Заряжается', style: TextStyle(fontSize: 12.5)),
            if (c.lastRead != null)
              Text('Последнее получение данных: ${_hhmm(c.lastRead!)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if (c.fw != null)
              Text('Прошивка: ${c.fw}${c.hw == null ? '' : '  •  аппаратная: ${c.hw}'}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ]),
        ),
        Column(children: [
          Icon(
              bat == null
                  ? Icons.battery_unknown
                  : bat > 80
                      ? Icons.battery_full
                      : bat > 40
                          ? Icons.battery_5_bar
                          : bat > 15
                              ? Icons.battery_2_bar
                              : Icons.battery_alert,
              color: bat == null ? cs.onSurfaceVariant : (bat > 15 ? kGreen : kRed)),
          Text(bat == null ? '—' : '$bat%', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  Widget _authCard(BuildContext context, WearableController c) {
    final cs = Theme.of(context).colorScheme;
    final busy = c.status == WearStatus.authorizing;
    final ok = c.status == WearStatus.ready;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Авторизация', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(c.hasKey ? 'Ключ сохранён в защищённом хранилище.' : 'Ключ не введён.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        if (c.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(c.message!,
                style: TextStyle(
                    color: ok ? kGreen : (busy ? null : cs.error), fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
                onPressed: busy ? null : _enterKey,
                child: Text(c.hasKey ? 'Заменить ключ' : 'Ввести ключ')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
                onPressed: busy || !c.hasKey || ok ? null : c.authorize,
                child: Text(busy ? 'Подождите…' : (ok ? 'Готово' : 'Авторизоваться'))),
          ),
        ]),
        if (c.hasKey)
          TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await AuthKeyStore.delete();
                      await c.refreshKeyState();
                    },
              child: const Text('Удалить ключ')),
      ]),
    );
  }

  List<Widget> _metrics(BuildContext context, WearableController c) {
    final today = dayKey(DateTime.now());
    final d = ref.watch(dayDataProvider(today)).valueOrNull;
    final act = d?.activity;
    final health = act?.source == null ? 'Health' : sourceLabel(act!.source);
    String hm(double min) => '${min ~/ 60} ч ${(min % 60).round()} мин';

    final pulse = c.hr != null
        ? _Metric('Пульс', Icons.favorite, kRed, '${c.hr}', 'уд/мин',
            'Bluetooth · ${_hhmm(c.hrAt!)}',
            onTap: _openHr)
        : (act?.avgHr != null
            ? _Metric('Пульс', Icons.favorite, kRed, fmt0(act!.avgHr!), 'уд/мин',
                'среднее за день · $health',
                onTap: _openHr)
            : _Metric('Пульс', Icons.favorite, kRed, null, '', 'Недоступно', onTap: _openHr));
    final steps = c.steps != null
        ? _Metric('Шаги', Icons.directions_walk, kBlue, fmt0(c.steps!), '',
            'Bluetooth · ${_hhmm(c.stepsAt!)}')
        : (act != null && act.steps > 0)
            ? _Metric('Шаги', Icons.directions_walk, kBlue, fmt0(act.steps), '',
                'сегодня · $health')
            : _Metric('Шаги', Icons.directions_walk, kBlue, null, '', 'Недоступно');
    final kcal = (act != null && act.activeKcal > 0)
        ? _Metric('Активные калории', Icons.local_fire_department, kOrange,
            fmt0(act.activeKcal), 'ккал', 'без базового обмена · $health')
        : _Metric('Активные калории', Icons.local_fire_department, kOrange, null, '',
            'Недоступно (нет данных с часов)');
    final sleep = (act != null && act.sleepMinutes > 0)
        ? _Metric('Сон', Icons.bedtime_outlined, kViolet, hm(act.sleepMinutes), '',
            act.sleepStart == null
                ? 'за ночь · $health'
                : '${_hhmm(act.sleepStart!.toLocal())}–${_hhmm(act.sleepEnd!.toLocal())} · глубокий ${hm(act.sleepDeepMin)}, REM ${hm(act.sleepRemMin)} (оценка)')
        : _Metric('Сон', Icons.bedtime_outlined, kViolet, null, '', 'Недоступно');
    final spo2 = c.spo2 != null
        ? _Metric('SpO₂', Icons.bloodtype_outlined, kBlue, '${c.spo2}', '%',
            'измерение ${_hhmm(c.spo2At!.toLocal())} · Bluetooth')
        : _Metric('SpO₂', Icons.bloodtype_outlined, kBlue, null, '',
            'Недоступно (нет измерений с часов)');

    return [
      LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final m in [pulse, steps, kcal, sleep, spo2]) SizedBox(width: w, child: m),
        ]);
      }),
      const SizedBox(height: 12),
    ];
  }

  void _openHr() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HeartRatePage()));
}

class _Metric extends StatelessWidget {
  final String title, unit, caption;
  final IconData icon;
  final Color color;
  final String? value;
  final VoidCallback? onTap;
  const _Metric(this.title, this.icon, this.color, this.value, this.unit, this.caption,
      {this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        if (value == null)
          Text('Недоступно',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))
        else
          Text.rich(TextSpan(children: [
            TextSpan(
                text: value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            if (unit.isNotEmpty)
              TextSpan(text: ' $unit', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ])),
        const SizedBox(height: 4),
        Text(caption, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
