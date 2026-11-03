import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import '../health_integration/devices_page.dart';

/// Этап 1 интеграции Amazfit GTR 4 по BLE: поиск, подключение, чтение списка
/// GATT-служб. Авторизация и данные здоровья ещё не реализованы, поэтому
/// страница показывает только то, что реально сообщает устройство.
class WearablePage extends ConsumerStatefulWidget {
  const WearablePage({super.key});
  @override
  ConsumerState<WearablePage> createState() => _WearablePageState();
}

class _WearablePageState extends ConsumerState<WearablePage> {

  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  List<ScanResult> _results = [];
  bool _scanning = false, _showAll = false, _busy = false;
  String? _error;
  BluetoothDevice? _device;
  List<BluetoothService> _services = [];
  int? _stdBattery;
  String? _fw, _hw, _hrNote;
  int? _hr;
  DateTime? _hrAt;
  bool _hrOn = false;
  StreamSubscription<List<int>>? _hrSub;
  Timer? _hrTimer;
  DateTime? _lastRead;
  String? _savedId;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(FlutterBluePlus.adapterState.listen((s) => setState(() => _adapter = s)));
    _subs.add(FlutterBluePlus.scanResults.listen((r) => setState(() => _results = r)));
    _subs.add(FlutterBluePlus.isScanning.listen((s) => setState(() => _scanning = s)));
    ref.read(dbProvider).allSettings().then((m) {
      if (mounted) setState(() => _savedId = m['wearable_id']);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hrSub?.cancel();
    _hrTimer?.cancel();
    FlutterBluePlus.stopScan();
    _device?.disconnect();
    super.dispose();
  }

  String _name(ScanResult r) => r.advertisementData.advName.isNotEmpty
      ? r.advertisementData.advName
      : r.device.platformName;

  /// Кандидат в часы Amazfit: по имени или по рекламируемой службе Huami.
  /// Имя в рекламе может отсутствовать, поэтому одного имени недостаточно.
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
    final parts = <String>[
      if (ad.serviceUuids.isNotEmpty) 'службы: ${ad.serviceUuids.map((u) => u.str).join(', ')}',
      if (ad.manufacturerData.isNotEmpty)
        'производитель: ${ad.manufacturerData.keys.map((k) => '0x${k.toRadixString(16)}').join(', ')}',
      ad.connectable ? 'подключаемое' : 'не подключаемое',
    ];
    return parts.join(' • ');
  }

  Future<void> _scan() async {
    setState(() => _error = null);
    try {
      if (_adapter != BluetoothAdapterState.on) {
        setState(() => _error = 'Bluetooth выключен. Включите его и повторите поиск.');
        return;
      }
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      setState(() => _error = 'Не удалось начать поиск: $e');
    }
  }

  Future<void> _connect(BluetoothDevice d) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FlutterBluePlus.stopScan();
      await d.connect(license: License.free, timeout: const Duration(seconds: 20));
      final services = await d.discoverServices();
      int? battery;
      String? fw, hw;
      BluetoothCharacteristic? find(String svc, String ch) {
        for (final sv in services) {
          if (sv.uuid.str.toLowerCase() != svc) continue;
          for (final c in sv.characteristics) {
            if (c.uuid.str.toLowerCase() == ch) return c;
          }
        }
        return null;
      }

      Future<List<int>?> tryRead(String svc, String ch) async {
        try {
          final c = find(svc, ch);
          return c != null && c.properties.read ? await c.read() : null;
        } catch (_) {
          return null;
        }
      }

      final b = await tryRead('180f', '2a19');
      if (b != null && b.isNotEmpty) battery = b.first;
      final f = await tryRead('180a', '2a28');
      if (f != null) fw = String.fromCharCodes(f);
      final h = await tryRead('180a', '2a27');
      if (h != null) hw = String.fromCharCodes(h);
      setState(() {
        _device = d;
        _services = services;
        _stdBattery = battery;
        _fw = fw;
        _hw = hw;
        _lastRead = DateTime.now();
      });
      await ref.read(dbProvider).setSetting('wearable_id', d.remoteId.str);
      if (mounted) setState(() => _savedId = d.remoteId.str);
    } catch (e) {
      setState(() => _error = 'Подключение не удалось: $e. Закройте приложение Zepp: '
          'часы держат только одно соединение.');
      try {
        await d.disconnect();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconnect() async {
    final id = _savedId;
    if (id == null) return;
    await _connect(BluetoothDevice.fromId(id));
  }

  Future<void> _forget() async {
    await ref.read(dbProvider).setSetting('wearable_id', '');
    setState(() => _savedId = null);
  }

  Future<void> _disconnect() async {
    _hrSub?.cancel();
    _hrTimer?.cancel();
    await _device?.disconnect();
    setState(() {
      _device = null;
      _services = [];
      _stdBattery = null;
      _fw = _hw = _hrNote = null;
      _hr = null;
      _hrOn = false;
    });
  }

  /// Стандартная характеристика пульса 2a37 (служба 180d). Формат — Bluetooth SIG:
  /// бит 0 флагов = пульс 16 бит. Приходят ли данные без авторизации, неизвестно.
  Future<void> _toggleHr() async {
    BluetoothCharacteristic? c;
    for (final sv in _services) {
      if (sv.uuid.str.toLowerCase() != '180d') continue;
      for (final ch in sv.characteristics) {
        if (ch.uuid.str.toLowerCase() == '2a37') c = ch;
      }
    }
    if (c == null) {
      setState(() => _hrNote = 'Характеристика пульса 2a37 не найдена.');
      return;
    }
    try {
      if (_hrOn) {
        await c.setNotifyValue(false);
        _hrSub?.cancel();
        _hrTimer?.cancel();
        setState(() {
          _hrOn = false;
          _hrNote = null;
        });
        return;
      }
      _hrSub = c.onValueReceived.listen((v) {
        if (v.length < 2) return;
        final bpm = (v[0] & 1) == 1 && v.length >= 3 ? v[1] | (v[2] << 8) : v[1];
        setState(() {
          _hr = bpm;
          _hrAt = DateTime.now();
          _hrNote = null;
        });
      });
      await c.setNotifyValue(true);
      setState(() {
        _hrOn = true;
        _hr = null;
        _hrNote = 'Ожидание данных пульса…';
      });
      _hrTimer?.cancel();
      _hrTimer = Timer(const Duration(seconds: 40), () {
        if (mounted && _hr == null) {
          setState(() => _hrNote = 'Часы не прислали пульс за 40 секунд. Возможно, нужна '
              'авторизация или команда запуска измерения (ещё не реализовано).');
        }
      });
    } catch (e) {
      setState(() => _hrNote = 'Не удалось подписаться на пульс: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = _results.where((r) => _showAll || _isCandidate(r)).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(title: const Text('Умные часы')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Text(
            'Прямое подключение по Bluetooth в разработке: сейчас читаются заряд, версия прошивки '
            'и (если часы отдают) пульс. Шаги, сон, калории и SpO₂ по Bluetooth требуют авторизации '
            'с ключом Zepp; пока они показываются из Health Connect / Apple Health, если Zepp их передаёт.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        if (_device == null) ...[
          if (_savedId != null && _savedId!.isNotEmpty) ...[
            FilledButton.tonalIcon(
                onPressed: _busy || _scanning ? null : _reconnect,
                icon: const Icon(Icons.bluetooth_connected),
                label: const Text('Подключиться к сохранённым часам')),
            TextButton(onPressed: _forget, child: const Text('Забыть сохранённые часы')),
          ],
          FilledButton.icon(
              onPressed: _scanning || _busy ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Поиск…' : 'Найти часы')),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Показывать все устройства'),
              subtitle: const Text('Для диагностики, если часы не находятся'),
              value: _showAll,
              onChanged: (v) => setState(() => _showAll = v)),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: TextStyle(color: cs.error))),
          if (shown.isEmpty && !_scanning)
            const EmptyHint(
                'Часы не найдены. Проверьте: на часах включён Bluetooth; часы удалены из списка '
                'Bluetooth в настройках телефона (иначе они не рекламируются); Zepp закрыт и '
                'не подключён к часам. Если не помогло, включите «Показывать все устройства» '
                'и пришлите скриншот списка.'),
          for (final r in shown)
            AppCard(
              onTap: _busy ? null : () => _connect(r.device),
              child: Row(children: [
                const Icon(Icons.watch_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name(r).isEmpty ? 'Без названия' : _name(r),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(r.device.remoteId.str,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    Text(_details(r),
                        style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ]),
                ),
                Text('${r.rssi} dBm'),
              ]),
            ),
        ] else ...[
          _header(context),
          const SizedBox(height: 12),
          ..._metrics(context),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                  onPressed: () => toast(context,
                      'Синхронизация истории по Bluetooth пока недоступна: нужна авторизация с ключом Zepp. '
                      'Данные из Health обновляются сами.'),
                  icon: const Icon(Icons.sync),
                  label: const Text('Синхронизировать')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DevicesPage())),
                  icon: const Icon(Icons.tune),
                  label: const Text('Источники')),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _toggleHr,
              icon: const Icon(Icons.favorite_border),
              label: Text(_hrOn ? 'Остановить пульс' : 'Подписаться на пульс (Bluetooth)')),
          if (_hrNote != null)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_hrNote!,
                    style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Отключить часы')),
          const SizedBox(height: 16),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('GATT-службы устройства (диагностика)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              children: [
                for (final sv in _services)
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sv.uuid.str, style: const TextStyle(fontWeight: FontWeight.w700)),
                      for (final c in sv.characteristics)
                        Text(
                            '  ${c.uuid.str}  '
                            '${c.properties.read ? 'R' : ''}${c.properties.write ? 'W' : ''}'
                            '${c.properties.notify ? 'N' : ''}',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _device!.platformName.isEmpty ? 'Amazfit GTR 4' : _device!.platformName;
    final bat = _stdBattery;
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
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.circle, size: 10, color: kGreen),
              const SizedBox(width: 6),
              const Text('Подключено (Bluetooth)'),
            ]),
            if (_lastRead != null)
              Text('Последнее получение данных: ${_hhmm(_lastRead!)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            if (_fw != null)
              Text('Прошивка: $_fw${_hw == null ? '' : '  •  аппаратная: $_hw'}',
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
          Text(bat == null ? '—' : '$bat%',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }

  List<Widget> _metrics(BuildContext context) {
    final today = dayKey(DateTime.now());
    final d = ref.watch(dayDataProvider(today)).valueOrNull;
    final act = d?.activity;
    final src = act?.source;
    final health = src == null ? 'Health' : 'Health · $src';
    String hm(double min) => '${min ~/ 60} ч ${(min % 60).round()} мин';

    final pulse = _hr != null
        ? _Metric('Пульс', Icons.favorite, kRed, '$_hr', 'уд/мин',
            'Bluetooth · ${_hhmm(_hrAt!)}')
        : (act?.avgHr != null
            ? _Metric('Пульс', Icons.favorite, kRed, fmt0(act!.avgHr!), 'уд/мин',
                'среднее за день · $health')
            : const _Metric('Пульс', Icons.favorite, kRed, null, '', 'Недоступно'));
    final steps = (act != null && act.steps > 0)
        ? _Metric('Шаги', Icons.directions_walk, kBlue, fmt0(act.steps), '', 'сегодня · $health')
        : const _Metric('Шаги', Icons.directions_walk, kBlue, null, '', 'Недоступно');
    final kcal = (act != null && act.activeKcal > 0)
        ? _Metric('Активные калории', Icons.local_fire_department, kOrange,
            fmt0(act.activeKcal), 'ккал', 'без базового обмена · $health')
        : const _Metric('Активные калории', Icons.local_fire_department, kOrange, null, '', 'Недоступно');
    final sleep = (act != null && act.sleepMinutes > 0)
        ? _Metric('Сон', Icons.bedtime_outlined, kViolet, hm(act.sleepMinutes), '', 'за ночь · $health')
        : const _Metric('Сон', Icons.bedtime_outlined, kViolet, null, '', 'Недоступно');
    const spo2 = _Metric('SpO₂', Icons.bloodtype_outlined, kBlue, null, '',
        'Недоступно (нужна авторизация по Bluetooth)');
    Widget row(_Metric a, _Metric? b) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: a),
            const SizedBox(width: 10),
            Expanded(child: b ?? const SizedBox()),
          ]),
        );
    return [row(pulse, steps), row(kcal, sleep), row(spo2, null)];
  }
}

class _Metric extends StatelessWidget {
  final String title, unit, caption;
  final IconData icon;
  final Color color;
  final String? value;
  const _Metric(this.title, this.icon, this.color, this.value, this.unit, this.caption);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))
        else
          Text.rich(TextSpan(children: [
            TextSpan(text: value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            if (unit.isNotEmpty)
              TextSpan(text: ' $unit', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ])),
        const SizedBox(height: 4),
        Text(caption, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
