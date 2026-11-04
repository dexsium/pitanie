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

/// Этап измерения для окна «Измерение веса».
enum ScalePhase { idle, measuring, saving, done }

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

  // Состояние текущего взвешивания (для окна измерения)
  ScalePhase phase = ScalePhase.idle;
  double? liveKg;
  WeightEntry? savedEntry;

  /// Пользователь закрыл окно измерения: до конца этого взвешивания его не открываем снова.
  bool dismissed = false;
  DateTime? _lastPacketAt;
  Timer? _watchdog;

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

  MiScaleReading? _pending;
  Timer? _pendingTimer;

  Future<void> _onResults(List<ScanResult> list) async {
    for (final r in list) {
      final data = r.advertisementData.serviceData[_uScale2];
      if (data == null) continue;
      final reading = parseMiScale2(data);
      if (reading == null) {
        _addLog('пакет 0x181B не распознан (${data.length} байт)');
        continue;
      }
      await onReading(reading);
    }
  }

  void _setPhase(ScalePhase p) {
    phase = p;
    if (p == ScalePhase.idle) {
      dismissed = false;
      liveKg = null;
      savedEntry = null;
    }
    notifyListeners();
  }

  /// Обработка одного распознанного пакета весов.
  @visibleForTesting
  Future<void> onReading(MiScaleReading reading, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    _lastPacketAt = t;
    // Пакет уже сохранённого взвешивания или «нагрузка снята»: человек сошёл с весов.
    if (reading.stamp == lastStamp || reading.loadRemoved) {
      if (phase == ScalePhase.measuring) {
        _pending = null;
        _pendingTimer?.cancel();
        _addLog('измерение прервано: человек сошёл с весов');
        _setPhase(ScalePhase.idle);
      } else if (phase == ScalePhase.done) {
        _setPhase(ScalePhase.idle);
      }
      return;
    }
    if (phase == ScalePhase.done || phase == ScalePhase.saving) {
      if (reading.stamp != lastStamp) _setPhase(ScalePhase.idle);
    }
    _watchdog ??= Timer.periodic(const Duration(seconds: 2), (_) => checkStale());
    if (phase == ScalePhase.idle) {
      phase = ScalePhase.measuring;
      _addLog('весы: начато измерение');
    }
    liveKg = reading.weightKg;
    notifyListeners();
    if (!reading.isFinal) return;

    final p = _pending;
    if (p != null && p.stamp != reading.stamp) {
      // Пришло другое взвешивание: удержанное сохраняем как есть.
      await _flush();
    }
    if (reading.impedance != null) {
      _pendingTimer?.cancel();
      _pending = reading;
      await _flush();
    } else if (_pending == null) {
      // Вес стабилен, а импеданс ещё не измерен: ждём пакет с импедансом, но не дольше 15 секунд.
      _pending = reading;
      _pendingTimer?.cancel();
      _pendingTimer = Timer(const Duration(seconds: 15), _flush);
    }
  }

  /// Если пакеты перестали приходить во время измерения, измерение считается прерванным.
  @visibleForTesting
  void checkStale({DateTime? now}) {
    final t = now ?? DateTime.now();
    final last = _lastPacketAt;
    if (phase == ScalePhase.measuring && last != null && t.difference(last).inSeconds > 25) {
      _pending = null;
      _pendingTimer?.cancel();
      _addLog('измерение прервано: весы перестали передавать данные');
      _setPhase(ScalePhase.idle);
    }
  }

  Future<void> _flush() async {
    final reading = _pending;
    _pending = null;
    _pendingTimer?.cancel();
    if (reading == null || reading.stamp == lastStamp) return;
    lastStamp = reading.stamp;
    _setPhase(ScalePhase.saving);
    final now = DateTime.now();
    final id = await db.addWeight(now, reading.weightKg, impedance: reading.impedance?.toDouble());
    await db.setSetting('scale_last_stamp', reading.stamp);
    await db.setSetting('scale_last_kg', '${reading.weightKg}');
    await db.setSetting('scale_last_at', '${now.millisecondsSinceEpoch}');
    lastKg = reading.weightKg;
    lastAt = now;
    liveKg = reading.weightKg;
    savedEntry = await db.weightById(id);
    _addLog('вес ${reading.weightKg} кг сохранён'
        '${reading.impedance == null ? ' (без импеданса)' : ' (импеданс ${reading.impedance} Ом)'}');
    _setPhase(ScalePhase.done);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _pendingTimer?.cancel();
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
