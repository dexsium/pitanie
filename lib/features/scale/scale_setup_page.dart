import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/widgets.dart';
import 'gatt_scale.dart';
import 'scale_controller.dart';
import 'scale_driver.dart';

/// Поиск весов со стандартными сервисами Bluetooth. Mi Body Composition Scale 2 находится сама
/// и здесь не показывается: ей подключение не нужно.
class ScaleSetupPage extends ConsumerStatefulWidget {
  const ScaleSetupPage({super.key});

  @override
  ConsumerState<ScaleSetupPage> createState() => _ScaleSetupPageState();
}

class _ScaleSetupPageState extends ConsumerState<ScaleSetupPage> {
  final _found = <String, ({String name, int rssi})>{};
  StreamSubscription<List<ScanResult>>? _sub;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _found.clear();
    });
    try {
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        throw 'Bluetooth выключен';
      }
      await _sub?.cancel();
      _sub = FlutterBluePlus.scanResults.listen((list) {
        for (final r in list) {
          final d = driverFor(advertOf(r));
          if (d == null || d.transport != ScaleTransport.gatt) continue;
          final a = advertOf(r);
          _found[r.device.remoteId.str] =
              (name: a.name.isEmpty ? 'Весы без названия' : a.name, rssi: r.rssi);
        }
        if (mounted) setState(() {});
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = ref.watch(scaleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Другие весы')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Text(
              'Подходят весы со стандартными сервисами Bluetooth (Weight Scale 0x181D или Body '
              'Composition 0x181B). Встаньте на весы или включите их, чтобы они появились в списке. '
              'Совместимость с конкретными моделями не подтверждена: драйвер написан по '
              'спецификации Bluetooth и на реальных весах ещё не проверялся. Показатели состава '
              'тела записываются только если весы их передают.',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        const SizedBox(height: 12),
        if (scale.gattId != null && scale.gattId!.isNotEmpty)
          AppCard(
            child: Row(children: [
              const Icon(Icons.check_circle, color: kGreen),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Выбраны: ${scale.gattName ?? scale.gattId}',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(
                  onPressed: () => ref.read(scaleProvider).forgetGattScale(),
                  child: const Text('Забыть')),
            ]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(
              child: Text('Найденные весы',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          if (_scanning)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            TextButton.icon(
                onPressed: _scan, icon: const Icon(Icons.refresh), label: const Text('Искать')),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: kRed)),
          ),
        if (_found.isEmpty && !_scanning && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Весы не найдены. Включите весы и нажмите «Искать».',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final e in _found.entries)
          AppCard(
            onTap: () async {
              await ref.read(scaleProvider).setGattScale(e.key, e.value.name);
              if (context.mounted) {
                toast(context, 'Весы выбраны. Встаньте на них при открытом приложении.');
                Navigator.pop(context);
              }
            },
            child: Row(children: [
              const Icon(Icons.monitor_weight_outlined, color: kPrimary),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Сигнал ${e.value.rssi} дБм · стандартный Bluetooth, не проверено',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ])),
              const Icon(Icons.chevron_right),
            ]),
          ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Драйверы приложения',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final d in kScaleDrivers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(d.verified ? Icons.check_circle : Icons.help_outline,
                      size: 18, color: d.verified ? kGreen : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d.title)),
                  Text(d.verified ? 'проверен' : 'не проверен',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
