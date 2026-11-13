import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/perf_log.dart';
import '../../database/database.dart';
import 'gatt_scale.dart';
import 'mi_scale.dart';
import 'scale_driver.dart';

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

  /// Подпись последнего пакета (метка, вес, флаги) и время, когда она последний раз менялась.
  /// Весы после того, как человек сошёл, могут долго повторять один и тот же пакет: такие
  /// повторы не считаются признаком идущего измерения.
  String? _lastSig;
  DateTime? _lastResultAt;
  DateTime? _lastChangeAt;

  /// Подпись прерванного измерения: пакеты с ней не запускают новое измерение.
  String? _abortedSig;

  /// Весы со стандартными сервисами Bluetooth (подключение): выбранное пользователем устройство.
  String? gattId;
  String? gattName;
  bool _gattBusy = false;
  DateTime? _gattCooldownUntil;
  double? _lastGattKg;
  DateTime? _lastGattAt;

  bool _loaded = false;
  StreamSubscription<List<ScanResult>>? _sub;
  StreamSubscription<bool>? _scanSub;
  Timer? _timer;

  /// Диагностика приёма: сколько запусков сканирования, результатов и пакетов весов 0x181B.
  int scanStarts = 0;
  int resultsSeen = 0;
  int scalePackets = 0;
  DateTime? lastPacketSeen;
  String? lastScanError;

  String get diagnostics {
    final p = lastPacketSeen;
    final when = p == null
        ? 'не было'
        : '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}:${p.second.toString().padLeft(2, '0')}';
    return 'Сканирование: ${FlutterBluePlus.isScanningNow ? 'идёт' : 'остановлено'}, запусков $scanStarts, '
        'устройств в эфире $resultsSeen, пакетов весов $scalePackets, последний $when'
        '${lastScanError == null ? '' : ', ошибка: $lastScanError'}';
  }

  void _addLog(String s) {
    final t = DateTime.now();
    log.insert(0, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $s');
    if (log.length > 150) log.removeLast();
  }

  Future<void> start() async {
    if (!_loaded) {
      _loaded = true;
      final m = await db.allSettings();
      enabled = m['scale_enabled'] != '0';
      lastStamp = m['scale_last_stamp'];
      gattId = m['gatt_scale_id'];
      gattName = m['gatt_scale_name'];
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
    // Сканирование останавливается при подключении к часам и поиске устройств:
    // как только оно остановилось, запускаем снова.
    _scanSub ??= FlutterBluePlus.isScanning.listen((on) {
      if (!on && enabled) {
        Future.delayed(const Duration(milliseconds: 800), _ensureScan);
      }
      notifyListeners();
    });
    // Состояние Bluetooth на старте часто «unknown»: запускаем скан сразу, как адаптер включился.
    _adapterSub ??= FlutterBluePlus.adapterState.listen((s) {
      if (s == BluetoothAdapterState.on && enabled) _ensureScan();
    });
    _timer ??= Timer.periodic(const Duration(seconds: 8), (_) => _ensureScan());
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
      await _scanSub?.cancel();
      _scanSub = null;
      await _adapterSub?.cancel();
      _adapterSub = null;
      scanning = false;
    }
    notifyListeners();
  }

  /// Запоминает весы со стандартными сервисами (найденные на экране «Источники здоровья»).
  Future<void> setGattScale(String id, String name) async {
    gattId = id;
    gattName = name;
    await db.setSetting('gatt_scale_id', id);
    await db.setSetting('gatt_scale_name', name);
    _addLog('выбраны весы: $name');
    notifyListeners();
  }

  Future<void> forgetGattScale() async {
    gattId = null;
    gattName = null;
    await db.setSetting('gatt_scale_id', '');
    await db.setSetting('gatt_scale_name', '');
    notifyListeners();
  }

  /// Подключается к выбранным весам, когда они появились в эфире. До трёх попыток с паузой;
  /// после измерения 30 секунд не подключается снова (весы продолжают рекламироваться).
  Future<void> _tryGatt(BluetoothDevice device) async {
    final until = _gattCooldownUntil;
    if (_gattBusy || (until != null && DateTime.now().isBefore(until))) return;
    _gattBusy = true;
    try {
      for (var attempt = 1; attempt <= 3; attempt++) {
        _addLog('весы ${gattName ?? ''}: подключение, попытка $attempt');
        final res = await readGattScale(device, onProgress: (kg) {
          if (phase == ScalePhase.done || phase == ScalePhase.saving) {
            phase = ScalePhase.idle;
            savedEntry = null;
          }
          phase = ScalePhase.measuring;
          liveKg = kg;
          notifyListeners();
        });
        final m = res.measurement;
        if (m?.weightKg != null) {
          await _saveGatt(m!);
          return;
        }
        _addLog('весы: ${res.error ?? 'нет данных'}');
        if (phase == ScalePhase.measuring) _setPhase(ScalePhase.idle);
        if (attempt < 3) await Future<void>.delayed(Duration(seconds: attempt == 1 ? 2 : 5));
      }
    } finally {
      _gattBusy = false;
      _gattCooldownUntil = DateTime.now().add(const Duration(seconds: 30));
    }
  }

  Future<void> _saveGatt(ScaleMeasurement m) async {
    final kg = m.weightKg!;
    final now = DateTime.now();
    final prevKg = _lastGattKg, prevAt = _lastGattAt;
    if (prevKg != null &&
        prevAt != null &&
        (prevKg - kg).abs() < 0.05 &&
        now.difference(prevAt).inSeconds < 120) {
      _addLog('весы: то же измерение повторно, пропущено');
      if (phase == ScalePhase.measuring) _setPhase(ScalePhase.idle);
      return;
    }
    _setPhase(ScalePhase.saving);
    final id = await db.saveScaleWeight(now, kg,
        impedance: m.impedanceOhm,
        bodyFatPct: m.bodyFatPct,
        fatFreeKg: m.fatFreeKg,
        muscleKg: m.muscleMassKg,
        waterKg: m.bodyWaterKg,
        bmrKcal: m.bmrKcal,
        driver: 'gatt_standard');
    _lastGattKg = kg;
    _lastGattAt = now;
    await db.setSetting('scale_last_kg', '$kg');
    await db.setSetting('scale_last_at', '${now.millisecondsSinceEpoch}');
    lastKg = kg;
    lastAt = now;
    liveKg = kg;
    savedEntry = await db.weightById(id);
    _addLog('весы: вес $kg кг сохранён'
        '${m.hasComposition ? ' (с составом тела)' : ' (только вес)'}');
    _setPhase(ScalePhase.done);
  }

  /// Сканирование прерывается при подключении к часам и поиске устройств: перезапускаем.
  Future<void> _ensureScan() async {
    if (!enabled || FlutterBluePlus.isScanningNow) return;
    final st = FlutterBluePlus.adapterStateNow;
    if (st != BluetoothAdapterState.on) {
      if (_lastAdapterMark != st) {
        _lastAdapterMark = st;
        PerfLog.mark('весы: Bluetooth ${st.name}, сканирование не запускается');
      }
      return;
    }
    try {
      await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 24), continuousUpdates: true);
      PerfLog.mark('весы: сканирование запущено (№${scanStarts + 1})');
      _lastResultAt = null;
      scanStarts++;
      lastScanError = null;
      if (!scanning) {
        scanning = true;
        notifyListeners();
      }
    } catch (e) {
      lastScanError = '$e';
      PerfLog.mark('весы: сканирование не запущено: $e');
      _addLog('сканирование не запущено: $e');
    }
  }

  BluetoothAdapterState? _lastAdapterMark;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  MiScaleReading? _pending;
  Timer? _pendingTimer;
  DateTime? _measureStartAt;
  String? _measureStamp;

  Future<void> _onResults(List<ScanResult> list) async {
    resultsSeen = list.length;
    for (final r in list) {
      final gid = gattId;
      if (gid != null && gid.isNotEmpty && r.device.remoteId.str == gid) {
        unawaited(_tryGatt(r.device));
        continue;
      }
      final data = r.advertisementData.serviceData[_uScale2];
      if (data == null) continue;
      // Поток отдаёт весь список при каждом пакете любого устройства, и данные весов в нём
      // повторяются, хотя новых пакетов нет. Обрабатываем только свежие.
      final prev = _lastResultAt;
      if (prev != null && !r.timeStamp.isAfter(prev)) continue;
      _lastResultAt = r.timeStamp;
      if (scalePackets == 0) PerfLog.mark('весы: получен первый пакет 0x181B');
      scalePackets++;
      lastPacketSeen = DateTime.now();
      final reading = parseMiScale2(data);
      if (reading == null) {
        _addLog('пакет 0x181B не распознан (${data.length} байт)');
        continue;
      }
      await onReading(reading);
    }
  }

  void _setPhase(ScalePhase p) {
    PerfLog.mark('весы: фаза ${phase.name} → ${p.name}');
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
    final sig = '${reading.stamp}|${reading.weightKg}|${reading.stabilized}|'
        '${reading.loadRemoved}|${reading.impedance}';
    if (sig != _lastSig) {
      _lastSig = sig;
      _lastChangeAt = t;
      final why = sig == _abortedSig && phase == ScalePhase.idle
          ? 'повтор прерванного'
          : reading.stamp == lastStamp
              ? 'метка уже сохранена'
              : reading.loadRemoved
                  ? 'нагрузка снята'
                  : 'принят';
      PerfLog.mark('весы: пакет, фаза ${phase.name} → $why'
          '${reading.stabilized ? ', стабилен' : ''}'
          '${reading.impedance != null ? ', с импедансом' : ''}');
      _addLog('пакет: ${reading.weightKg} кг'
          '${reading.stabilized ? ', стабилен' : ''}'
          '${reading.impedance != null ? ', имп. ${reading.impedance}' : ''}'
          ', метка ${reading.stamp}, фаза ${phase.name} → $why');
    }
    // Повтор пакета прерванного измерения (человек сошёл, весы повторяют последний пакет).
    if (sig == _abortedSig && phase == ScalePhase.idle) return;
    if (sig != _abortedSig) _abortedSig = null;
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
      _measureStartAt = t;
      _measureStamp = reading.stamp;
      _addLog('весы: начато измерение');
    } else if (phase == ScalePhase.measuring && reading.stamp != _measureStamp) {
      // Весы начали новое взвешивание (другая метка): прежнее незавершённое не должно «висеть».
      _measureStamp = reading.stamp;
      _measureStartAt = t;
      PerfLog.mark('весы: новая метка во время измерения, отсчёт начат заново');
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
    final changed = _lastChangeAt;
    if (phase != ScalePhase.measuring) return;
    // Пакетов нет вообще или приходит один и тот же пакет без изменений: измерение не идёт.
    final silent = last != null && t.difference(last).inSeconds > 25;
    final frozen = changed != null && _pending == null && t.difference(changed).inSeconds > 20;
    final started = _measureStartAt;
    final tooLong = _pending == null && started != null && t.difference(started).inSeconds > 60;
    if (silent || frozen || tooLong) {
      _pending = null;
      _pendingTimer?.cancel();
      _abortedSig = (frozen || tooLong) ? _lastSig : null;
      _addLog(silent
          ? 'измерение прервано: весы перестали передавать данные'
          : tooLong
              ? 'измерение прервано: слишком долго без результата'
              : 'измерение прервано: вес не меняется, человек сошёл');
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
    final id = await db.saveScaleWeight(now, reading.weightKg,
        impedance: reading.impedance?.toDouble(), driver: 'mi_scale2');
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
    _scanSub?.cancel();
    _adapterSub?.cancel();
    super.dispose();
  }
}
