import 'dart:async';
import 'dart:convert';
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
import 'watch_archive.dart';
import 'watch_workouts.dart';
import 'zepp_notifications.dart';
import 'watch_settings.dart';

enum WearStatus { off, connecting, connected, authorizing, ready }

const _bleName = 'Amazfit GTR 4 (Bluetooth)';
const _uChunkWrite = '00000016-0000-3512-2118-0009af100700';
const _uChunkRead = '00000017-0000-3512-2118-0009af100700';
const _uFetchCtl = '00000004-0000-3512-2118-0009af100700';
const _uFetchData = '00000005-0000-3512-2118-0009af100700';

final wearableProvider = ChangeNotifierProvider<WearableController>(
    (ref) => WearableController(ref.watch(dbProvider)));

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
  WatchHealthSettings? watchCfg;
  String? cfgMsg;
  bool cfgBusy = false;
  bool finding = false;
  Completer<Uint8List>? _cfgWait;
  NotifCaps? notifCaps;
  Completer<NotifCaps>? _capsWait;
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

  bool get isConnected =>
      status == WearStatus.connected ||
      status == WearStatus.authorizing ||
      status == WearStatus.ready;

  void _set(void Function() f) {
    f();
    notifyListeners();
  }

  void addLog(String line) {
    final t = DateTime.now();
    log.insert(0,
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $line');
    if (log.length > 400) log.removeLast();
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
    addLog(
        'запуск: часы ${savedId ?? 'не сохранены'}, ключ ${hasKey ? 'есть' : 'нет'}, '
        'состояние ${isConnected ? 'подключено' : 'нет связи'}');
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
    // Сразу после запуска состояние адаптера ещё «неизвестно»: ждём, пока оно определится.
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      _set(() => message = 'Bluetooth выключен');
      return;
    }
    addLog('автоподключение к $id (попытка ${_retries + 1})');
    final ok = await connect(BluetoothDevice.fromId(id));
    if (!ok) addLog('автоподключение не удалось: ${message ?? ''}');
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
      await d.connect(
          license: License.free, timeout: const Duration(seconds: 20));
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
        if (s == BluetoothConnectionState.disconnected && device != null)
          _onLost();
      });
      return true;
    } catch (e) {
      _set(() {
        status = WearStatus.off;
        message =
            'Не удалось подключиться: $e. Закройте Zepp: часы держат одно соединение.';
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
      final auth =
          HuamiAuthenticator(write: w, read: r, secret: secret, mtu: d.mtuNow);
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
    if (type == 0x0001) {
      // Часы просят телефон сходить за погодой: в запросе токен аккаунта Zepp и координаты,
      // поэтому содержимое не пишем в журнал и запрос не исполняем.
      addLog('запрос погоды от часов (${p.length} байт, проигнорирован)');
      return;
    }
    if (type == notifEndpoint) {
      addLog('уведомления, ответ часов: '
          '${p.take(40).map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}');
      final caps = parseNotifCaps(p);
      if (caps != null) {
        notifCaps = caps;
        addLog('уведомления: версия сервиса ${caps.version}, '
            'картинки ${caps.supportsPictures}, ключ ${caps.supportsKey}');
        final w = _capsWait;
        if (w != null && !w.isCompleted) w.complete(caps);
        notifyListeners();
      }
      return;
    }
    if (type == cfgEndpoint) {
      _onCfg(p);
      return;
    }
    if (type == findEndpoint) {
      addLog(
          'найти часы: ${p.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}');
      if (p[0] == findStopFromBand && finding) {
        finding = false;
        notifyListeners();
      }
      return;
    }
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
    if (bpm >= 30 &&
        bpm <= 230 &&
        now.difference(_lastHrStore).inSeconds >= 10) {
      _lastHrStore = now;
      db.upsertActivity([
        ActivityRecordsCompanion.insert(
            type: 'heartRate',
            startTime: now,
            endTime: now.add(const Duration(seconds: 10)),
            value: bpm.toDouble(),
            unit: 'bpm',
            source: kBleSource,
            externalRecordId:
                'ble-hrlive-${now.millisecondsSinceEpoch ~/ 1000}',
            tzOffsetMin: Value(now.timeZoneOffset.inMinutes),
            sourceName: const Value(_bleName))
      ]);
    }
  }

  Future<void> loadSpo2() async {
    final now = DateTime.now();
    final recs =
        await db.activityBetween(now.subtract(const Duration(days: 7)), now);
    final list =
        recs.where((r) => r.type == 'spo2' && r.source == kBleSource).toList();
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
    var vitals = '';
    String? err;
    try {
      // Версия 2 разбора истории добавила сон: один раз перечитываем последние 3 дня.
      final threeDays =
          now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
      var since = DateTime.fromMillisecondsSinceEpoch(
          settings['ble_hist_v'] == '2'
              ? int.tryParse(settings['ble_last_activity'] ?? '') ?? threeDays
              : threeDays);
      for (var round = 0; round < 5; round++) {
        final res =
            await fetcher.fetch(fetchTypeActivity, since, onStage: addLog);
        if (!res.ok) {
          err = res.error;
          break;
        }
        if (res.data.isEmpty) break;
        final samples = parseActivity(res.data, res.start!);
        if (samples == null) {
          err =
              'Неожиданный формат данных активности (${res.data.length} байт).';
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
            for (final t in [
              'sleep',
              switch (x.stage) {
                SleepStage.deep => 'sleepDeep',
                SleepStage.rem => 'sleepRem',
                SleepStage.light => 'sleepLight',
              }
            ]) {
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
        await db.setSetting(
            'ble_last_activity', '${last.millisecondsSinceEpoch}');
        await db.setSetting('ble_hist_v', '2');
        if (!last.isBefore(now) || samples.length < 2) break;
        since = last.toLocal();
      }
      if (err == null) {
        final sSince = DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(settings['ble_last_spo2'] ?? '') ??
                now.subtract(const Duration(days: 7)).millisecondsSinceEpoch);
        final res =
            await fetcher.fetch(fetchTypeSpo2Normal, sSince, onStage: addLog);
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
                    externalRecordId:
                        'ble-spo2-${x.time.millisecondsSinceEpoch ~/ 1000}',
                    tzOffsetMin: Value(tzMin),
                    sourceName: const Value(_bleName))
            ]);
            spoN = list.length;
            final last =
                list.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
            await db.setSetting('ble_last_spo2',
                '${last.add(const Duration(minutes: 1)).millisecondsSinceEpoch}');
          }
        }
      }
      if (err == null) {
        vitals = await _syncVitals(fetcher, settings, now, tzMin);
      }
      if (err == null) await _archiveStreams(fetcher, now);
    } catch (e) {
      err = 'Ошибка: $e';
    }
    await loadSpo2();
    _set(() {
      syncBusy = false;
      syncMsg = err != null
          ? 'История загружена частично: $err (шаги: $stepMin мин, пульс: $hrN мин, сон: $sleepMin мин, SpO₂: $spoN)$vitals'
          : 'История загружена: минут с шагами $stepMin, с пульсом $hrN, сна $sleepMin мин, измерений SpO₂ $spoN.$vitals';
    });
  }

  /// Пульс покоя, максимальный пульс, стресс и дыхание во сне. Это необязательные данные:
  /// если часы не поддерживают тип или отклоняют запрос, история не считается неудачной.
  Future<String> _syncVitals(HuamiFetcher f, Map<String, String> settings,
      DateTime now, int tzMin) async {
    var rest = 0, max = 0, stress = 0, resp = 0;
    DateTime sinceOf(String key,
        {required int days, Duration back = Duration.zero}) {
      final ms = int.tryParse(settings[key] ?? '');
      final t = ms == null
          ? now.subtract(Duration(days: days))
          : DateTime.fromMillisecondsSinceEpoch(ms).subtract(back);
      return t;
    }

    ActivityRecordsCompanion rec(
            String type, DateTime t, double v, String unit, String id) =>
        ActivityRecordsCompanion.insert(
            type: type,
            startTime: t,
            endTime: t.add(const Duration(minutes: 1)),
            value: v,
            unit: unit,
            source: kBleSource,
            externalRecordId: id,
            tzOffsetMin: Value(tzMin),
            sourceName: const Value(_bleName));

    Future<void> dayHeart(
        int type, String key, String recType, String tag, bool isRest) async {
      final r = await f.fetch(
          type, sinceOf(key, days: 30, back: const Duration(days: 2)),
          onStage: addLog);
      if (!r.ok) {
        addLog('0x${type.toRadixString(16)}: ${r.error}');
        return;
      }
      if (r.data.isEmpty) return;
      final list = parseDayHeart(r.data);
      if (list == null) {
        addLog(
            '0x${type.toRadixString(16)}: неожиданный формат (${r.data.length} байт)');
        return;
      }
      final ok = [
        for (final x in list)
          if (x.bpm >= 30 && x.bpm <= 230) x
      ];
      await db.upsertActivity([
        for (final x in ok)
          rec(recType, x.time, x.bpm.toDouble(), 'bpm',
              'ble-$tag-${x.time.millisecondsSinceEpoch ~/ 1000}')
      ]);
      if (ok.isNotEmpty) {
        final last =
            ok.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
        await db.setSetting(key, '${last.millisecondsSinceEpoch}');
        if (isRest) {
          rest += ok.length;
        } else {
          max += ok.length;
        }
      }
    }

    try {
      await dayHeart(
          fetchTypeRestingHr, 'ble_last_rhr', 'restingHeartRate', 'rhr', true);
      await dayHeart(
          fetchTypeMaxHr, 'ble_last_maxhr', 'maxHeartRate', 'maxhr', false);

      final s1 = await f.fetch(
          fetchTypeStressAuto, sinceOf('ble_last_stress', days: 7),
          onStage: addLog);
      if (!s1.ok) {
        addLog('стресс: ${s1.error}');
      } else if (s1.data.isNotEmpty && s1.start != null) {
        final list = parseStress(s1.data, s1.start!);
        await db.upsertActivity([
          for (final x in list)
            rec('stress', x.time, x.value.toDouble(), 'score',
                'ble-stress-${x.time.millisecondsSinceEpoch ~/ 60000}')
        ]);
        if (list.isNotEmpty) {
          stress = list.length;
          await db.setSetting('ble_last_stress',
              '${list.last.time.add(const Duration(minutes: 1)).millisecondsSinceEpoch}');
        }
      }

      final s2 = await f.fetch(
          fetchTypeSleepResp, sinceOf('ble_last_resp', days: 14),
          onStage: addLog);
      if (!s2.ok) {
        addLog('дыхание: ${s2.error}');
      } else if (s2.data.isNotEmpty) {
        final list = parseSleepResp(s2.data);
        if (list == null) {
          addLog('дыхание: неожиданный формат (${s2.data.length} байт)');
        } else {
          final ok = [
            for (final x in list)
              if (x.value >= 4 && x.value <= 60) x
          ];
          await db.upsertActivity([
            for (final x in ok)
              rec('respiration', x.time, x.value.toDouble(), 'br/min',
                  'ble-resp-${x.time.millisecondsSinceEpoch ~/ 1000}')
          ]);
          if (ok.isNotEmpty) {
            resp = ok.length;
            await db.setSetting('ble_last_resp',
                '${ok.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(seconds: 1)).millisecondsSinceEpoch}');
          }
        }
      }
    } catch (e) {
      addLog('показатели покоя/стресса: $e');
    }
    return ' Пульс покоя: $rest, макс.: $max, стресс: $stress, дыхание: $resp.';
  }

  // ---------- настройки часов ----------

  void _onCfg(Uint8List p) {
    addLog(
        'настройки: ${p.take(40).map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}');
    if (p[0] == cmdResponse) {
      final parsed = parseHealthResponse(p);
      if (parsed != null) {
        watchCfg = (watchCfg ?? const WatchHealthSettings()).merge(parsed);
        unawaited(_rememberOriginalCfg());
      }
    }
    final w = _cfgWait;
    if (w != null && !w.isCompleted && (p[0] == cmdResponse || p[0] == cmdAck))
      w.complete(p);
    notifyListeners();
  }

  Future<void> _rememberOriginalCfg() async {
    final c = watchCfg;
    if (c == null || c.isEmpty) return;
    final saved = (await db.allSettings())['watch_cfg_orig'];
    if (saved == null)
      await db.setSetting('watch_cfg_orig', jsonEncode(c.toJson()));
  }

  Future<Uint8List?> _cfgExchange(Uint8List payload) async {
    final s = session;
    if (s == null) return null;
    _cfgWait = Completer<Uint8List>();
    try {
      await s.send(cfgEndpoint, payload);
      return await _cfgWait!.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      return null;
    } finally {
      _cfgWait = null;
    }
  }

  /// Читает текущие настройки мониторинга с часов.
  Future<bool> readWatchSettings() async {
    if (session == null || cfgBusy) return false;
    cfgBusy = true;
    cfgMsg = null;
    notifyListeners();
    final r = await _cfgExchange(encodeHealthRequest());
    final ok =
        r != null && r[0] == cmdResponse && parseHealthResponse(r) != null;
    cfgBusy = false;
    cfgMsg = ok
        ? null
        : 'Часы не вернули настройки мониторинга (не поддерживается или нет ответа).';
    notifyListeners();
    return ok;
  }

  /// Записывает значения и проверяет чтением обратно. Возвращает текст ошибки или null.
  Future<String?> writeWatchSettings(Map<int, Object> values) async {
    if (session == null) return 'Часы не подключены.';
    if (cfgBusy) return 'Дождитесь завершения предыдущей операции.';
    if (watchCfg == null)
      return 'Сначала прочитайте текущие настройки с часов.';
    cfgBusy = true;
    cfgMsg = null;
    notifyListeners();
    String? err;
    try {
      final ack = await _cfgExchange(encodeHealthSet(values));
      if (ack == null) {
        err = 'Часы не подтвердили запись.';
      } else {
        addLog(
            'настройки: подтверждение ${ack.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}');
        final back =
            await _cfgExchange(encodeHealthRequest(values.keys.toList()));
        final parsed = back == null ? null : parseHealthResponse(back);
        if (parsed == null) {
          err = 'Не удалось проверить результат чтением обратно.';
        } else {
          final j = parsed.toJson();
          final want = WatchHealthSettings(
                  hrInterval: values[keyHrInterval] as int?,
                  sleepHr: values[keySleepHr] as bool?,
                  sleepBreathing: values[keySleepBreathing] as bool?,
                  stress: values[keyStress] as bool?,
                  spo2AllDay: values[keySpo2AllDay] as bool?)
              .toJson();
          for (final e in want.entries) {
            if (j[e.key] != e.value) {
              err =
                  'Часы не приняли изменение (после записи значение прежнее).';
            }
          }
        }
      }
    } catch (e) {
      err = 'Ошибка записи: $e';
    }
    cfgBusy = false;
    cfgMsg = err;
    notifyListeners();
    return err;
  }

  /// Возвращает значения, которые были на часах при первом чтении приложением.
  Future<String?> restoreOriginalWatchSettings() async {
    final raw = (await db.allSettings())['watch_cfg_orig'];
    if (raw == null) return 'Исходные значения ещё не сохранены.';
    final o = WatchHealthSettings.fromJson(jsonDecode(raw) as Map);
    return writeWatchSettings({
      if (o.hrInterval != null) keyHrInterval: o.hrInterval!,
      if (o.sleepHr != null) keySleepHr: o.sleepHr!,
      if (o.sleepBreathing != null) keySleepBreathing: o.sleepBreathing!,
      if (o.stress != null) keyStress: o.stress!,
      if (o.spo2AllDay != null) keySpo2AllDay: o.spo2AllDay!,
    });
  }

  /// Синхронизация времени через характеристику Current Time (2A2B).
  Future<String?> syncWatchTime() async {
    for (final sv in services) {
      for (final ch in sv.characteristics) {
        final u = ch.uuid.str128.toLowerCase();
        if (u.startsWith('00002a2b')) {
          try {
            await ch.write(currentTimeBytes(DateTime.now()),
                withoutResponse:
                    ch.properties.writeWithoutResponse && !ch.properties.write);
            addLog('время часов синхронизировано');
            return null;
          } catch (e) {
            addLog('время: $e');
            return 'Часы отклонили установку времени: $e';
          }
        }
      }
    }
    return 'У часов не найдена характеристика времени.';
  }

  /// Заявили ли часы сервис уведомлений Zepp OS: null, если список сервисов ещё не получен.
  bool? get notifServiceListed {
    final s = session;
    if (s == null || s.endpoints.isEmpty) return null;
    return s.endpoints.contains(notifEndpoint);
  }

  /// Тестовое уведомление, отправленное приложением по протоколу Zepp OS. Часы не подтверждают
  /// показ: считать успехом можно только появление уведомления на экране часов.
  Future<String?> sendWatchTestNotification() async {
    final s = session;
    if (s == null) return 'Часы не подключены или не авторизованы.';
    if (notifServiceListed == false) {
      return 'Часы не заявили сервис уведомлений (0x001e).';
    }
    try {
      var caps = notifCaps;
      var guessed = false;
      addLog('уведомления: сервис 0x001e '
          '${s.encryptedEndpoints.contains(notifEndpoint) ? 'шифруется' : 'без шифрования'}, '
          'сервисов у часов: ${s.endpoints.length}');
      if (caps == null) {
        _capsWait = Completer<NotifCaps>();
        await s.send(notifEndpoint, buildNotifCapsRequest());
        try {
          caps = await _capsWait!.future.timeout(const Duration(seconds: 6));
        } on TimeoutException {
          // Часы промолчали: отправляем в формате версии 5 (самый новый из известных) и
          // честно сообщаем, что это предположение. Для проверки это безвредно.
          caps = const NotifCaps(5, false, false);
          guessed = true;
        } finally {
          _capsWait = null;
        }
      }
      await s.send(
          notifEndpoint,
          buildNotification(
              id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
              appId: 'com.pitanie.pitanie',
              title: 'Питание',
              body: 'Проверка: уведомление отправлено приложением.',
              appName: 'Питание',
              caps: caps));
      addLog('уведомления: тестовое отправлено (версия ${caps.version}'
          '${guessed ? ', предположение: часы не ответили на запрос возможностей' : ''})');
      return guessed
          ? 'Часы не ответили на запрос возможностей. Отправлено в формате версии 5 '
              '(предположение), проверьте экран часов.'
          : null;
    } catch (e) {
      return 'Не удалось отправить: $e';
    }
  }

  /// «Найти часы»: вибрация и сигнал на часах, пока не остановите.
  Future<String?> findWatch(bool start) async {
    final s = session;
    if (s == null) return 'Часы не подключены.';
    try {
      await s.send(findEndpoint, [start ? findStart : findStopFromPhone]);
      finding = start;
      notifyListeners();
      return null;
    } catch (e) {
      return 'Не удалось отправить команду: $e';
    }
  }

  /// Типы, которые часы отдают один раз: читаем целиком и сразу кладём в архив.
  // 0x05 и 0x06 — сводки и подробности тренировок: сохраняем сырыми, чтобы по ним
  // написать разбор тренировок с часов (формат на GTR 4 ещё не проверен).
  static const _archiveTypes = {0x02, 0x05, 0x06, 0x0d, 0x12, 0x2c, 0x3b};

  /// Сохраняет блок в архив и пишет в журнал его описание. Ничего не теряется,
  /// даже если разбор в приложении ещё не написан.
  Future<void> _keepRaw(int t, Uint8List data, String? note) async {
    // Типы 0x05/0x06 отдаются при каждой синхронизации: одинаковый блок второй раз не пишем.
    if (t == 0x05 || t == 0x06) {
      if (!await WatchArchive.addIfNew(t, data, note: note)) {
        addLog(
            'ТИП 0x${t.toRadixString(16)}: без изменений (${data.length} байт)');
        if (t == 0x05) await _importWorkout(data);
        return;
      }
    }
    addLog(
        'ТИП 0x${t.toRadixString(16)}: ${data.length} байт${note == null ? '' : ' ($note)'}');
    for (final l in describeRaw(t, data)) {
      addLog('  $l');
    }
    try {
      if (t != 0x05 && t != 0x06) await WatchArchive.add(t, data, note: note);
    } catch (e) {
      addLog('архив: $e');
    }
    if (t == 0x05) await _importWorkout(data);
  }

  /// Тренировка с часов: сводка (0x05) превращается в запись о тренировке. Повторная
  /// синхронизация обновляет ту же запись по идентификатору, дубликатов не создаёт.
  Future<void> _importWorkout(Uint8List data) async {
    final w = parseWatchWorkout(data);
    if (w == null) {
      addLog(
          'тренировка с часов: формат не распознан, данные оставлены в архиве');
      return;
    }
    await db.upsertWorkouts([
      WorkoutsCompanion.insert(
        source: kBleSource,
        sourceName: const Value(_bleName),
        externalRecordId: w.externalId,
        workoutType: watchWorkoutType(w.typeCode),
        startTime: w.start,
        endTime: w.end,
        avgHr: Value(w.avgHr.toDouble()),
        maxHr: Value(w.maxHr.toDouble()),
      )
    ]);
    addLog(
        'тренировка с часов: ${w.start.toLocal()} · ${w.durationSec ~/ 60} мин · пульс ${w.avgHr}/${w.maxHr}');
  }

  /// Читает «одноразовые» потоки при каждой синхронизации, чтобы они не пропадали.
  Future<void> _archiveStreams(HuamiFetcher f, DateTime now) async {
    for (final t in _archiveTypes) {
      try {
        final r = await f.fetch(t, now.subtract(const Duration(days: 7)),
            timeout: const Duration(seconds: 40),
            maxBytes: 300000,
            lenient: true);
        if (r.ok && r.data.isNotEmpty) await _keepRaw(t, r.data, r.note);
      } catch (e) {
        addLog('архив 0x${t.toRadixString(16)}: $e');
      }
    }
  }

  Future<String> archiveReport() => WatchArchive.report();

  Future<String> archivePath() async => (await WatchArchive.file()).path;

  /// Диагностика: какие типы истории отвечают часы (для поиска HRV и других данных).
  /// Только чтение. Для каждого типа в журнал пишется объявленный размер и начало данных.
  Future<void> probeFetchTypes() async {
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
      syncMsg = 'Поиск типов данных…';
    });
    final f = HuamiFetcher(c4, c5);
    addLog(
        'ПОИСК ТИПОВ: старт (0x01–0x40); всё прочитанное сохраняется в архив');
    final since = DateTime.now().subtract(const Duration(days: 7));
    var answered = 0;
    for (var t = 0x01; t <= 0x40; t++) {
      if (t == 0x07) continue; // журналы отладки: объёмные и не нужны
      final big = _archiveTypes.contains(t);
      try {
        final r = await f.fetch(t, since,
            timeout: Duration(seconds: big ? 40 : 8),
            maxBytes: big ? 300000 : 20000,
            lenient: true);
        if (r.ok && r.data.isNotEmpty) {
          answered++;
          await _keepRaw(t, r.data, r.note);
        } else {
          addLog('ТИП 0x${t.toRadixString(16)}: ${r.error ?? 'пусто'}');
        }
      } catch (e) {
        addLog('ТИП 0x${t.toRadixString(16)}: ошибка $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    addLog('ПОИСК ТИПОВ: готово, с данными: $answered');
    _set(() {
      syncBusy = false;
      syncMsg = 'Поиск типов завершён: с данными $answered. Скопируйте журнал.';
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
