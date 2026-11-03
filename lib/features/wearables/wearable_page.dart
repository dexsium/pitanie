import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../shared/widgets.dart';

/// Этап 1 интеграции Amazfit GTR 4 по BLE: поиск, подключение, чтение списка
/// GATT-служб. Авторизация и данные здоровья ещё не реализованы, поэтому
/// страница показывает только то, что реально сообщает устройство.
class WearablePage extends StatefulWidget {
  const WearablePage({super.key});
  @override
  State<WearablePage> createState() => _WearablePageState();
}

class _WearablePageState extends State<WearablePage> {
  static const _huamiService = '0000fee0';
  static const _huamiService2 = '0000fee1';
  static const _huamiAuth = '00000009-0000-3512-2118-0009af100700';

  BluetoothAdapterState _adapter = BluetoothAdapterState.unknown;
  List<ScanResult> _results = [];
  bool _scanning = false, _showAll = false, _busy = false;
  String? _error;
  BluetoothDevice? _device;
  List<BluetoothService> _services = [];
  int? _stdBattery;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(FlutterBluePlus.adapterState.listen((s) => setState(() => _adapter = s)));
    _subs.add(FlutterBluePlus.scanResults.listen((r) => setState(() => _results = r)));
    _subs.add(FlutterBluePlus.isScanning.listen((s) => setState(() => _scanning = s)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    FlutterBluePlus.stopScan();
    _device?.disconnect();
    super.dispose();
  }

  bool _isGtr4(ScanResult r) {
    final n = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName;
    return n.toLowerCase().contains('amazfit gtr 4');
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
      for (final s in services) {
        if (s.uuid.str.toLowerCase().contains('180f')) {
          for (final c in s.characteristics) {
            if (c.properties.read) {
              final v = await c.read();
              if (v.isNotEmpty) battery = v.first;
            }
          }
        }
      }
      setState(() {
        _device = d;
        _services = services;
        _stdBattery = battery;
      });
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

  Future<void> _disconnect() async {
    await _device?.disconnect();
    setState(() {
      _device = null;
      _services = [];
      _stdBattery = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = _results.where((r) => _showAll || _isGtr4(r)).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(title: const Text('Умные часы')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Text(
            'Прямое подключение по Bluetooth находится в разработке (этап 1: поиск и подключение). '
            'Показатели здоровья пока не читаются: для этого нужна авторизация с ключом из Zepp. '
            'Данные Amazfit в приложение сейчас попадают через Health Connect / Apple Health.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        if (_device == null) ...[
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
            const EmptyHint('Часы не найдены. Поднесите их ближе и закройте Zepp.'),
          for (final r in shown)
            AppCard(
              onTap: _busy ? null : () => _connect(r.device),
              child: Row(children: [
                const Icon(Icons.watch_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        r.advertisementData.advName.isNotEmpty
                            ? r.advertisementData.advName
                            : (r.device.platformName.isEmpty
                                ? 'Без имени'
                                : r.device.platformName),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(r.device.remoteId.str,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                ),
                Text('${r.rssi} dBm'),
              ]),
            ),
        ] else ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  _device!.platformName.isEmpty ? 'Устройство' : _device!.platformName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Статус: подключено (BLE)'),
              Text(_stdBattery == null
                  ? 'Заряд: недоступно (нужна авторизация)'
                  : 'Заряд: $_stdBattery%'),
              const SizedBox(height: 8),
              Text(
                  _services.any((s) => s.uuid.str.toLowerCase().startsWith(_huamiService) ||
                          s.uuid.str.toLowerCase().startsWith(_huamiService2))
                      ? 'Найдены службы Huami (fee0/fee1).'
                      : 'Службы Huami не найдены: возможно, это не Amazfit.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              Text(
                  _services.any((s) => s.characteristics
                          .any((c) => c.uuid.str.toLowerCase() == _huamiAuth))
                      ? 'Характеристика авторизации 0009 присутствует.'
                      : 'Характеристика авторизации 0009 не найдена.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _disconnect, child: const Text('Отключить')),
            ]),
          ),
          const SizedBox(height: 12),
          const SectionTitle('GATT-службы устройства'),
          const SizedBox(height: 8),
          for (final s in _services)
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.uuid.str, style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final c in s.characteristics)
                  Text(
                      '  ${c.uuid.str}  '
                      '${c.properties.read ? 'R' : ''}${c.properties.write ? 'W' : ''}'
                      '${c.properties.notify ? 'N' : ''}',
                      style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ]),
            ),
        ],
      ]),
    );
  }
}
