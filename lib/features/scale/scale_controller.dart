import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../database/database.dart';
import 'mi_scale.dart';

final scaleProvider =
    ChangeNotifierProvider<ScaleController>((ref) => ScaleController(ref.watch(dbProvider)));

final _uScale2 = Guid('181b');

/// Слушает рекламные пакеты Mi Body Composition Scale 2 и сохраняет завершённые взвешивания.
/// Работает, пока приложение открыто: iOS не отдаёт такие пакеты свёрнутому приложению.
class ScaleController extends ChangeNotifier {
  final AppDatabase db;
  ScaleController(this.db);

  bool enabled = true;
  double? lastKg;
  DateTime? lastAt;
  String? lastStamp;
  bool scanning = false;
  final log = <String>[];

  bool _loaded = false;
  StreamSubscription<List<ScanResult>>? _sub;
  Timer? _timer;

  void _addLog(String s) {
    final t = DateTime.now();
    log.insert(0, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $s');
    if (log.length > 40) log.removeLast();
  }

  Future<void> start() async {
    if (!_loaded) {
      _loaded = true;
      final m = await db.allSettings();
      enabled = m['scale_enabled'] != '0';
      lastStamp = m['scale_last_stamp'];
      final kg = double.tryParse(m['scale_last_kg'] ?? '');
      final at = int.tryParse(m['scale_last_at'] ?? '');
      if (kg != null && at != null) {
        lastKg = kg;
        lastAt = DateTime.fromMillisecondsSinceEpoch(at);
      }
      notifyListeners();
    }
    if (!enabled) return;
    _sub ??= FlutterBluePlus.scanResults.listen(_onResults);
    _timer ??= Timer.periodic(const Duration(seconds: 25), (_) => _ensureScan());
    await _ensureScan();
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    await db.setSetting('scale_enabled', v ? '1' : '0');
    if (v) {
      await start();
    } else {
      _timer?.cancel();
      _timer = null;
      await _sub?.cancel();
      _sub = null;
      scanning = false;
    }
    notifyListeners();
  }

  /// Сканирование прерывается при подключении к часам и поиске устройств: перезапускаем.
  Future<void> _ensureScan() async {
    if (!enabled || FlutterBluePlus.isScanningNow) return;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    try {
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 24), continuousUpdates: true);
      if (!scanning) {
        scanning = true;
        notifyListeners();
      }
    } catch (e) {
      _addLog('сканирование не запущено: $e');
    }
  }

  Future<void> _onResults(List<ScanResult> list) async {
    for (final r in list) {
      final data = r.advertisementData.serviceData[_uScale2];
      if (data == null) continue;
      final reading = parseMiScale2(data);
      if (reading == null) {
        _addLog('пакет 0x181B не распознан (${data.length} байт)');
        continue;
      }
      if (!reading.isFinal || reading.stamp == lastStamp) continue;
      lastStamp = reading.stamp;
      final now = DateTime.now();
      await db.addWeight(now, reading.weightKg);
      await db.setSetting('scale_last_stamp', reading.stamp);
      await db.setSetting('scale_last_kg', '${reading.weightKg}');
      await db.setSetting('scale_last_at', '${now.millisecondsSinceEpoch}');
      lastKg = reading.weightKg;
      lastAt = now;
      _addLog('вес ${reading.weightKg} кг сохранён'
          '${reading.impedance == null ? '' : ' (импеданс ${reading.impedance} Ом, не используется)'}');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
