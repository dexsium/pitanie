import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../database/database.dart';
import '../dashboard/day_data.dart' show kBleSource;
import 'huami_auth.dart';
import 'huami_fetch.dart';

enum WearStatus { off, connecting, connected, authorizing, ready }

const _bleName = 'Amazfit GTR 4 (Bluetooth)';
const _uChunkWrite = '00000016-0000-3512-2118-0009af100700';
const _uChunkRead = '00000017-0000-3512-2118-0009af100700';
const _uFetchCtl = '00000004-0000-3512-2118-0009af100700';
const _uFetchData = '00000005-0000-3512-2118-0009af100700';

final wearableProvider =
    ChangeNotifierProvider<WearableController>((ref) => WearableController(ref.watch(dbProvider)));

/// Общий сервис связи с часами: живёт, пока работает приложение, и не зависит от открытой страницы.
class WearableController extends ChangeNotifier {
  final AppDatabase db;
  WearableController(this.db);

  WearStatus status = WearStatus.off;
  String? message;
  BluetoothDevice? device;
  List<BluetoothService> services = [];
  HuamiAuthenticator? session;
  int? battery;
  bool charging = false;
  String? fw, hw;
  int? hr, steps, spo2;
  DateTime? hrAt, stepsAt, spo2At, lastRead;
  String? syncMsg;
  bool syncBusy = false;
  bool hrOn = false;
  String? savedId;
  bool hasKey = false;
  final log = <String>[];

  bool _userOff = false, _started = false, _busy = false;
  int _retries = 0;
  Timer? _retryTimer, _tick;
  DateTime _lastHrStore = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _hrSub;

  bool get isConnected => status == WearStatus.connected ||
      status == WearStatus.authorizing ||
      status == WearStatus.ready;

  void _set(void Function() f) {
    f();
    notifyListeners();
  }

  void addLog(String line) {
    final t = DateTime.now();
    log.insert(0, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $line');
    if (log.length > 60) log.removeLast();
  }

  /// Вызывается при запуске приложения и при возврате в него.
  Future<void> start() async {
    if (!_started) {
      _started = true;
      try {
        await FlutterBluePlus.setOptions(restoreState: true);
      } catch (_) {}
      final m = await db.allSettings();
      savedId = (m['wearable_id'] ?? '').isEmpty ? null : m['wearable_id'];
      hasKey = await AuthKeyStore.exists();
      await loadSpo2();
      notifyListeners();
    }
    if (!isConnected && !_busy && savedId != null && hasKey) {
      _userOff = false;
      _retries = 0;
      unawaited(autoConnect());
    }
  }

  /// Ручное подключение к сохранённым часам (с авторизацией, если есть ключ).
  Future<void> reconnect() async {
    final id = savedId;
    if (id == null || _busy || isConnected) return;
    _userOff = false;
    _retries = 0;
    hasKey = await AuthKeyStore.exists();
    if (await connect(BluetoothDevice.fromId(id)) && hasKey) await authorize();
  }

  Future<void> refreshKeyState() async {
    hasKey = await AuthKeyStore.exists();
    notifyListeners();
  }

  /// Подключение к сохранённым часам с ограниченным числом повторов (без бесконечных циклов).
  Future<void> autoConnect() async {
    final id = savedId;
    if (id == null || !hasKey || _busy || isConnected || _userOff) return;
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _set(() => message = 'Bluetooth выключен');
      return;
    }
    final ok = await connect(BluetoothDevice.fromId(id));
    if (ok) {
      await authorize();
    } else if (_retries < 3 && !_userOff) {
      _retries++;
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: 20 * _retries), autoConnect);
    }
  }

  Future<bool> connect(BluetoothDevice d) async {
    if (_busy) return false;
    _busy = true;
    _set(() {
      status = WearStatus.connecting;
      message = null;
    });
    try {
      await FlutterBluePlus.stopScan();
      await d.connect(license: License.free, timeout: const Duration(seconds: 20));
      final svcs = await d.discoverServices();
      BluetoothCharacteristic? find(String svc, String ch) {
        for (final sv in svcs) {
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
      final f = await tryRead('180a', '2a28');
      final h = await tryRead('180a', '2a27');
      _set(() {
        device = d;
        services = svcs;
        if (b != null && b.isNotEmpty) battery = b.first;
        if (f != null) fw = String.fromCharCodes(f);
        if (h != null) hw = String.fromCharCodes(h);
        lastRead = DateTime.now();
        status = WearStatus.connected;
        savedId = d.remoteId.str;
      });
      await db.setSetting('wearable_id', d.remoteId.str);
      _connSub?.cancel();
      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && device != null) _onLost();
      });
      return true;
    } catch (e) {
      _set(() {
        status = WearStatus.off;
        message = 'Не удалось подключиться: $e. Закройте Zepp: часы держат одно соединение.';
      });
      try {
        await d.disconnect();
      } catch (_) {}
      return false;
    } finally {
      _busy = false;
    }
  }

  void _onLost() {
    _tick?.cancel();
    _hrSub?.cancel();
    session?.close();
    _set(() {
      session = null;
      device = null;
      services = [];
      hrOn = false;
      status = WearStatus.off;
      message = 'Связь с часами потеряна';
    });
    if (!_userOff && _retries < 3) {
      _retries++;
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: 20 * _retries), autoConnect);
    }
  }

  Future<void> disconnect() async {
    _userOff = true;
    _retryTimer?.cancel();
    _tick?.cancel();
    _hrSub?.cancel();
    await session?.close();
    final d = device;
    _set(() {
      session = null;
      device = null;
      services = [];
      hrOn = false;
      status = WearStatus.off;
      message = null;
    });
    try {
      await d?.disconnect();
    } catch (_) {}
  }

  Future<void> forget() async {
    await disconnect();
    await db.setSetting('wearable_id', '');
    _set(() => savedId = null);
  }

  Future<void> authorize() async {
    final d = device;
    if (d == null || status == WearStatus.authorizing) return;
    final secret = await AuthKeyStore.load();
    if (secret == null) {
      _set(() => message = 'Сначала введите ключ.');
      return;
    }
    BluetoothCharacteristic? w, r;
    for (final sv in services) {
      for (final ch in sv.characteristics) {
        final u = ch.uuid.str.toLowerCase();
        if (u == _uChunkWrite) w = ch;
        if (u == _uChunkRead) r = ch;
      }
    }
    if (w == null || r == null) {
      _set(() => message = 'У часов нет chunked-каналов 0016/0017.');
      return;
    }
    _set(() {
      status = WearStatus.authorizing;
      message = 'Авторизация…';
    });
    try {
      try {
        await d.requestMtu(247);
      } catch (_) {}
      final auth = HuamiAuthenticator(write: w, read: r, secret: secret, mtu: d.mtuNow);
      final res = await auth.authenticate();
      if (!res.ok) {
        _set(() {
          status = WearStatus.connected;
          message = res.message;
        });
        return;
      }
      auth.onPayload = _onZepp;
      _retries = 0;
      _set(() {
        session = auth;
        status = WearStatus.ready;
        message = res.message;
      });
      await _afterAuth();
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
    } catch (e) {
      _set(() {
        status = WearStatus.connected;
        message = 'Ошибка авторизации: $e';
      });
    }
  }

  Future<void> _afterAuth() async {
    final s = session;
    if (s == null) return;
    try {
      final listed = await s.requestServices();
      addLog(listed ? 'сервисы получены' : 'список сервисов не получен');
      await s.send(0x0029, [0x03]);
      await s.send(0x0016, [0x03]);
      await s.send(0x0016, [0x05, 0x01]);
      await s.send(0x001d, [0x04, 0x01]);
      if (!hrOn) await toggleHr(force: true);
    } catch (e) {
      addLog('ошибка запроса данных: $e');
    }
    unawaited(syncHistory());
  }

  Future<void> refresh() async {
    final s = session;
    if (s == null) return;
    try {
      await s.send(0x0029, [0x03]);
      await s.send(0x0016, [0x03]);
      await s.send(0x001d, [0x04, 0x02]);
    } catch (e) {
      addLog('ошибка обновления: $e');
    }
    await syncHistory();
  }

  void _onZepp(int type, Uint8List p) {
    if (p.isEmpty) return;
    addLog('0x${type.toRadixString(16).padLeft(4, '0')}: '
        '${p.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}');
    if (type == 0x0029 && p[0] == 0x04 && p.length >= 4) {
      battery = p[2];
      charging = p[3] == 1;
      lastRead = DateTime.now();
    } else if (type == 0x0016) {
      if (p[0] == 0x04 && p.length == 15) {
        steps = p[3] | (p[4] << 8);
        stepsAt = DateTime.now();
      } else if (p[0] == 0x07 && p.length == 14) {
        steps = p[2] | (p[3] << 8);
        stepsAt = DateTime.now();
      }
    }
    notifyListeners();
  }

  /// Подписка на стандартный пульс 2a37; значения сохраняются в базу (не чаще раза в 10 с).
  Future<void> toggleHr({bool force = false}) async {
    BluetoothCharacteristic? c;
    for (final sv in services) {
      if (sv.uuid.str.toLowerCase() != '180d') continue;
      for (final ch in sv.characteristics) {
        if (ch.uuid.str.toLowerCase() == '2a37') c = ch;
      }
    }
    if (c == null) return;
    try {
      if (hrOn && !force) {
        await c.setNotifyValue(false);
        _hrSub?.cancel();
        _set(() => hrOn = false);
        return;
      }
      _hrSub?.cancel();
      _hrSub = c.onValueReceived.listen(_onHr);
      await c.setNotifyValue(true);
      _set(() => hrOn = true);
    } catch (e) {
      addLog('пульс: $e');
    }
  }

  void _onHr(List<int> v) {
    if (v.length < 2) return;
    final bpm = (v[0] & 1) == 1 && v.length >= 3 ? v[1] | (v[2] << 8) : v[1];
    final now = DateTime.now();
    hr = bpm;
    hrAt = now;
    notifyListeners();
    if (bpm >= 30 && bpm <= 230 && now.difference(_lastHrStore).inSeconds >= 10) {
      _lastHrStore = now;
      db.upsertActivity([
        ActivityRecordsCompanion.insert(
            type: 'heartRate',
            startTime: now,
            endTime: now.add(const Duration(seconds: 10)),
            value: bpm.toDouble(),
            unit: 'bpm',
            source: kBleSource,
            externalRecordId: 'ble-hrlive-${now.millisecondsSinceEpoch ~/ 1000}',
            tzOffsetMin: Value(now.timeZoneOffset.inMinutes),
            sourceName: const Value(_bleName))
      ]);
    }
  }

  Future<void> loadSpo2() async {
    final now = DateTime.now();
    final recs = await db.activityBetween(now.subtract(const Duration(days: 7)), now);
    final list = recs.where((r) => r.type == 'spo2' && r.source == kBleSource).toList();
    if (list.isEmpty) return;
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    spo2 = list.last.value.round();
    spo2At = list.last.startTime;
  }

  /// История с часов: минутные шаги и пульс, SpO2. Данные на часах не удаляются.
  Future<void> syncHistory() async {
    if (session == null || syncBusy) return;
    BluetoothCharacteristic? c4, c5;
    for (final sv in services) {
      for (final ch in sv.characteristics) {
        final u = ch.uuid.str.toLowerCase();
        if (u == _uFetchCtl) c4 = ch;
        if (u == _uFetchData) c5 = ch;
      }
    }
    if (c4 == null || c5 == null) {
      _set(() => syncMsg = 'У часов нет каналов 0004/0005 для истории.');
      return;
    }
    _set(() {
      syncBusy = true;
      syncMsg = 'Загрузка истории…';
    });
    final settings = await db.allSettings();
    final fetcher = HuamiFetcher(c4, c5);
    addLog('история: старт');
    final now = DateTime.now();
    final tzMin = now.timeZoneOffset.inMinutes;
    var stepMin = 0, hrN = 0, spoN = 0, sleepMin = 0;
    String? err;
    try {
      // Версия 2 разбора истории добавила сон: один раз перечитываем последние 3 дня.
      final threeDays = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      var since = DateTime.fromMillisecondsSinceEpoch(settings['ble_hist_v'] == '2'
          ? int.tryParse(settings['ble_last_activity'] ?? '') ?? threeDays
          : threeDays);
      for (var round = 0; round < 5; round++) {
        final res = await fetcher.fetch(fetchTypeActivity, since, onStage: addLog);
        if (!res.ok) {
          err = res.error;
          break;
        }
        if (res.data.isEmpty) break;
        final samples = parseActivity(res.data, res.start!);
        if (samples == null) {
          err = 'Неожиданный формат данных активности (${res.data.length} байт).';
          break;
        }
        final recs = <ActivityRecordsCompanion>[];
        for (final x in samples) {
          final end = x.time.add(const Duration(minutes: 1));
          final minute = x.time.millisecondsSinceEpoch ~/ 60000;
          if (x.steps > 0) {
            stepMin++;
            recs.add(ActivityRecordsCompanion.insert(
                type: 'steps',
                startTime: x.time,
                endTime: end,
                value: x.steps.toDouble(),
                unit: 'count',
                source: kBleSource,
                externalRecordId: 'ble-steps-$minute',
                tzOffsetMin: Value(tzMin),
                sourceName: const Value(_bleName)));
          }
          if (x.isSleep) {
            sleepMin++;
            for (final t in ['sleep', switch (x.stage) {
              SleepStage.deep => 'sleepDeep',
              SleepStage.rem => 'sleepRem',
              SleepStage.light => 'sleepLight',
            }]) {
              recs.add(ActivityRecordsCompanion.insert(
                  type: t,
                  startTime: x.time,
                  endTime: end,
                  value: 1,
                  unit: 'min',
                  source: kBleSource,
                  externalRecordId: 'ble-$t-$minute',
                  tzOffsetMin: Value(tzMin),
                  sourceName: const Value(_bleName)));
            }
          }
          if (x.hasHeartRate) {
            hrN++;
            recs.add(ActivityRecordsCompanion.insert(
                type: 'heartRate',
                startTime: x.time,
                endTime: end,
                value: x.heartRate.toDouble(),
                unit: 'bpm',
                source: kBleSource,
                externalRecordId: 'ble-hr-$minute',
                tzOffsetMin: Value(tzMin),
                sourceName: const Value(_bleName)));
          }
        }
        await db.upsertActivity(recs);
        final last = samples.last.time.add(const Duration(minutes: 1));
        await db.setSetting('ble_last_activity', '${last.millisecondsSinceEpoch}');
        await db.setSetting('ble_hist_v', '2');
        if (!last.isBefore(now) || samples.length < 2) break;
        since = last.toLocal();
      }
      if (err == null) {
        final sSince = DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(settings['ble_last_spo2'] ?? '') ??
                now.subtract(const Duration(days: 7)).millisecondsSinceEpoch);
        final res = await fetcher.fetch(fetchTypeSpo2Normal, sSince, onStage: addLog);
        if (!res.ok) {
          err = res.error;
        } else if (res.data.isNotEmpty) {
          final list = parseSpo2(res.data);
          if (list == null) {
            err = 'Неожиданный формат SpO₂ (${res.data.length} байт).';
          } else if (list.isNotEmpty) {
            await db.upsertActivity([
              for (final x in list)
                ActivityRecordsCompanion.insert(
                    type: 'spo2',
                    startTime: x.time,
                    endTime: x.time.add(const Duration(minutes: 1)),
                    value: x.value.toDouble(),
                    unit: '%',
                    source: kBleSource,
                    externalRecordId: 'ble-spo2-${x.time.millisecondsSinceEpoch ~/ 1000}',
                    tzOffsetMin: Value(tzMin),
                    sourceName: const Value(_bleName))
            ]);
            spoN = list.length;
            final last = list.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
            await db.setSetting(
                'ble_last_spo2', '${last.add(const Duration(minutes: 1)).millisecondsSinceEpoch}');
          }
        }
      }
    } catch (e) {
      err = 'Ошибка: $e';
    }
    await loadSpo2();
    _set(() {
      syncBusy = false;
      syncMsg = err != null
          ? 'История загружена частично: $err (шаги: $stepMin мин, пульс: $hrN мин, сон: $sleepMin мин, SpO₂: $spoN)'
          : 'История загружена: минут с шагами $stepMin, с пульсом $hrN, сна $sleepMin мин, измерений SpO₂ $spoN.';
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _tick?.cancel();
    _hrSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
