import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import '../health_integration/devices_page.dart';
import 'package:drift/drift.dart' show Value;

import '../../database/database.dart';
import '../dashboard/day_data.dart' show kBleSource, sourceLabel;
import 'huami_auth.dart';
import 'huami_fetch.dart';

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
  bool _hasKey = false, _authBusy = false;
  String? _authMsg;
  bool? _authOk;
  HuamiAuthenticator? _session;
  bool _charging = false;
  int? _bleSteps;
  DateTime? _bleStepsAt;
  final _log = <String>[];
  String? _syncMsg;
  bool _syncBusy = false;
  int? _spo2;
  DateTime? _spo2At;
  String? _savedId;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(FlutterBluePlus.adapterState.listen((s) => setState(() => _adapter = s)));
    _subs.add(FlutterBluePlus.scanResults.listen((r) => setState(() => _results = r)));
    _subs.add(FlutterBluePlus.isScanning.listen((s) => setState(() => _scanning = s)));
    AuthKeyStore.exists().then((v) {
      if (mounted) setState(() => _hasKey = v);
    });
    ref.read(dbProvider).allSettings().then((m) async {
      if (!mounted) return;
      setState(() => _savedId = m['wearable_id']);
      await _loadSpo2();
      await _auto();
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hrSub?.cancel();
    _hrTimer?.cancel();
    _session?.close();
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

  Future<void> _enterKey() async {
    final c = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Ключ авторизации Zepp'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('32 символа (0-9, a-f), можно с префиксом 0x. '
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
    if (ok == true && mounted) {
      setState(() {
        _hasKey = true;
        _authOk = null;
        _authMsg = null;
      });
    }
  }

  Future<void> _deleteKey() async {
    await AuthKeyStore.delete();
    setState(() {
      _hasKey = false;
      _authOk = null;
      _authMsg = null;
    });
  }

  Future<void> _authorize() async {
    final secret = await AuthKeyStore.load();
    if (secret == null) {
      setState(() => _authMsg = 'Сначала введите ключ.');
      return;
    }
    BluetoothCharacteristic? w, r;
    for (final sv in _services) {
      for (final ch in sv.characteristics) {
        final u = ch.uuid.str.toLowerCase();
        if (u == '00000016-0000-3512-2118-0009af100700') w = ch;
        if (u == '00000017-0000-3512-2118-0009af100700') r = ch;
      }
    }
    if (w == null || r == null) {
      setState(() => _authMsg = 'У часов нет chunked-каналов 0016/0017.');
      return;
    }
    setState(() {
      _authBusy = true;
      _authMsg = 'Авторизация… (до 30 секунд)';
      _authOk = null;
    });
    try {
      try {
        await _device!.requestMtu(247);
      } catch (_) {}
      final auth = HuamiAuthenticator(
          write: w, read: r, secret: secret, mtu: _device!.mtuNow);
      final res = await auth.authenticate();
      if (mounted) {
        setState(() {
          _authOk = res.ok;
          _authMsg = res.message;
        });
      }
      if (res.ok) {
        _session = auth;
        auth.onPayload = _onZepp;
        await _afterAuth();
      }
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Widget _authCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Авторизация', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(_hasKey ? 'Ключ сохранён в защищённом хранилище.' : 'Ключ не введён.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        if (_authMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_authMsg!,
                style: TextStyle(
                    color: _authOk == true ? kGreen : (_authOk == false ? cs.error : null),
                    fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
                onPressed: _authBusy ? null : _enterKey,
                child: Text(_hasKey ? 'Заменить ключ' : 'Ввести ключ')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
                onPressed: _authBusy || !_hasKey ? null : _authorize,
                child: Text(_authBusy ? 'Подождите…' : 'Авторизоваться')),
          ),
        ]),
        if (_hasKey)
          TextButton(onPressed: _authBusy ? null : _deleteKey, child: const Text('Удалить ключ')),
      ]),
    );
  }

  String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

  void _addLog(String line) {
    _log.insert(0, '${_hhmm(DateTime.now())} $line');
    if (_log.length > 60) _log.removeLast();
  }

  /// Запрашивает список сервисов, заряд, шаги и включает пульс/шаги в реальном времени.
  Future<void> _afterAuth() async {
    final s = _session;
    if (s == null) return;
    try {
      final listed = await s.requestServices();
      _addLog(listed
          ? 'сервисы получены, шифруются: ${s.encryptedEndpoints.map((e) => e.toRadixString(16)).join(', ')}'
          : 'список сервисов не получен');
      await s.send(0x0029, [0x03]); // заряд
      await s.send(0x0016, [0x03]); // шаги (запрос)
      await s.send(0x0016, [0x05, 0x01]); // шаги в реальном времени
      await s.send(0x001d, [0x04, 0x01]); // пульс в реальном времени
      if (!_hrOn) await _toggleHr();
      await _syncHistory();
    } catch (e) {
      _addLog('ошибка запроса данных: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final s = _session;
    if (s == null) {
      toast(context, 'Сначала пройдите авторизацию.');
      return;
    }
    try {
      await s.send(0x0029, [0x03]);
      await s.send(0x0016, [0x03]);
      await s.send(0x001d, [0x04, 0x02]);
    } catch (e) {
      _addLog('ошибка обновления: $e');
    }
    await _syncHistory();
    if (mounted) setState(() {});
  }

  void _onZepp(int type, Uint8List p) {
    if (!mounted || p.isEmpty) return;
    setState(() {
      _addLog('0x${type.toRadixString(16).padLeft(4, '0')}: ${_hex(p)}');
      if (type == 0x0029 && p[0] == 0x04 && p.length >= 4) {
        _stdBattery = p[2];
        _charging = p[3] == 1;
        _lastRead = DateTime.now();
      } else if (type == 0x0016) {
        if (p[0] == 0x04 && p.length == 15) {
          _bleSteps = p[3] | (p[4] << 8);
          _bleStepsAt = DateTime.now();
        } else if (p[0] == 0x07 && p.length == 14) {
          _bleSteps = p[2] | (p[3] << 8);
          _bleStepsAt = DateTime.now();
        }
      }
    });
  }

  /// При открытии раздела: подключиться к сохранённым часам и авторизоваться,
  /// если ключ уже введён. Без нажатия кнопок.
  Future<void> _auto() async {
    final id = _savedId;
    if (id == null || id.isEmpty || _device != null || _busy) return;
    if (!await AuthKeyStore.exists()) return;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || _adapter != BluetoothAdapterState.on && _adapter != BluetoothAdapterState.unknown) return;
    await _connect(BluetoothDevice.fromId(id));
    if (_device != null && mounted) await _authorize();
  }

  Future<void> _loadSpo2() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final recs = await db.activityBetween(now.subtract(const Duration(days: 7)), now);
    final list = recs.where((r) => r.type == 'spo2' && r.source == kBleSource).toList();
    if (list.isEmpty) return;
    list.sort((a, b) => a.startTime.compareTo(b.startTime));
    if (mounted) {
      setState(() {
        _spo2 = list.last.value.round();
        _spo2At = list.last.startTime;
      });
    }
  }

  /// Загружает историю: минутную активность (шаги, пульс) и SpO2. Данные на часах не удаляются.
  Future<void> _syncHistory() async {
    final s = _session;
    if (s == null || _syncBusy) return;
    BluetoothCharacteristic? c4, c5;
    for (final sv in _services) {
      for (final ch in sv.characteristics) {
        final u = ch.uuid.str.toLowerCase();
        if (u == '00000004-0000-3512-2118-0009af100700') c4 = ch;
        if (u == '00000005-0000-3512-2118-0009af100700') c5 = ch;
      }
    }
    if (c4 == null || c5 == null) {
      setState(() => _syncMsg = 'У часов нет каналов 0004/0005 для истории.');
      return;
    }
    setState(() {
      _syncBusy = true;
      _syncMsg = 'Загрузка истории…';
    });
    final db = ref.read(dbProvider);
    final settings = await db.allSettings();
    final fetcher = HuamiFetcher(c4, c5);
    final now = DateTime.now();
    final tzMin = now.timeZoneOffset.inMinutes;
    var steps = 0, hr = 0, spo = 0;
    String? err;
    try {
      // Активность
      var since = DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(settings['ble_last_activity'] ?? '') ??
              now.subtract(const Duration(days: 3)).millisecondsSinceEpoch);
      for (var round = 0; round < 5; round++) {
        final res = await fetcher.fetch(fetchTypeActivity, since);
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
            steps++;
            recs.add(ActivityRecordsCompanion.insert(
                type: 'steps',
                startTime: x.time,
                endTime: end,
                value: x.steps.toDouble(),
                unit: 'count',
                source: kBleSource,
                externalRecordId: 'ble-steps-$minute',
                tzOffsetMin: Value(tzMin),
                sourceName: const Value('Amazfit GTR 4 (Bluetooth)')));
          }
          if (x.hasHeartRate) {
            hr++;
            recs.add(ActivityRecordsCompanion.insert(
                type: 'heartRate',
                startTime: x.time,
                endTime: end,
                value: x.heartRate.toDouble(),
                unit: 'bpm',
                source: kBleSource,
                externalRecordId: 'ble-hr-$minute',
                tzOffsetMin: Value(tzMin),
                sourceName: const Value('Amazfit GTR 4 (Bluetooth)')));
          }
        }
        await db.upsertActivity(recs);
        final last = samples.last.time.add(const Duration(minutes: 1));
        await db.setSetting('ble_last_activity', '${last.millisecondsSinceEpoch}');
        if (!last.isBefore(now) || samples.length < 2) break;
        since = last.toLocal();
      }
      // SpO2
      if (err == null) {
        final sSince = DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(settings['ble_last_spo2'] ?? '') ??
                now.subtract(const Duration(days: 7)).millisecondsSinceEpoch);
        final res = await fetcher.fetch(fetchTypeSpo2Normal, sSince);
        if (!res.ok) {
          err = res.error;
        } else if (res.data.isNotEmpty) {
          final list = parseSpo2(res.data);
          if (list == null) {
            err = 'Неожиданный формат SpO₂ (${res.data.length} байт).';
          } else {
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
                    sourceName: const Value('Amazfit GTR 4 (Bluetooth)'))
            ]);
            spo = list.length;
            if (list.isNotEmpty) {
              final last = list.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
              await db.setSetting(
                  'ble_last_spo2', '${last.add(const Duration(minutes: 1)).millisecondsSinceEpoch}');
            }
          }
        }
      }
    } catch (e) {
      err = 'Ошибка: $e';
    }
    await _loadSpo2();
    if (mounted) {
      setState(() {
        _syncBusy = false;
        _syncMsg = err != null
            ? 'История загружена частично: $err (минут с шагами: $steps, с пульсом: $hr, SpO₂: $spo)'
            : 'История загружена: минут с шагами $steps, с пульсом $hr, измерений SpO₂ $spo.';
      });
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
    await _session?.close();
    _session = null;
    _bleSteps = null;
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
          _authCard(context),
          const SizedBox(height: 12),
          ..._metrics(context),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                  onPressed: _refresh,
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
          if (_syncMsg != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_syncMsg!,
                    style: TextStyle(
                        fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
                if (_log.isNotEmpty)
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Журнал обмена', style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final l in _log)
                        Text(l,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
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
            if (_charging) const Text('Заряжается', style: TextStyle(fontSize: 12.5)),
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
    final health = src == null ? 'Health' : sourceLabel(src);
    String hm(double min) => '${min ~/ 60} ч ${(min % 60).round()} мин';

    final pulse = _hr != null
        ? _Metric('Пульс', Icons.favorite, kRed, '$_hr', 'уд/мин',
            'Bluetooth · ${_hhmm(_hrAt!)}')
        : (act?.avgHr != null
            ? _Metric('Пульс', Icons.favorite, kRed, fmt0(act!.avgHr!), 'уд/мин',
                'среднее за день · $health')
            : const _Metric('Пульс', Icons.favorite, kRed, null, '', 'Недоступно'));
    final steps = _bleSteps != null
        ? _Metric('Шаги', Icons.directions_walk, kBlue, fmt0(_bleSteps!), '',
            'Bluetooth · ${_hhmm(_bleStepsAt!)}')
        : (act != null && act.steps > 0)
        ? _Metric('Шаги', Icons.directions_walk, kBlue, fmt0(act.steps), '', 'сегодня · $health')
        : const _Metric('Шаги', Icons.directions_walk, kBlue, null, '', 'Недоступно');
    final kcal = (act != null && act.activeKcal > 0)
        ? _Metric('Активные калории', Icons.local_fire_department, kOrange,
            fmt0(act.activeKcal), 'ккал', 'без базового обмена · $health')
        : const _Metric('Активные калории', Icons.local_fire_department, kOrange, null, '', 'Недоступно');
    final sleep = (act != null && act.sleepMinutes > 0)
        ? _Metric('Сон', Icons.bedtime_outlined, kViolet, hm(act.sleepMinutes), '', 'за ночь · $health')
        : const _Metric('Сон', Icons.bedtime_outlined, kViolet, null, '', 'Недоступно');
    final spo2 = _spo2 != null
        ? _Metric('SpO₂', Icons.bloodtype_outlined, kBlue, '$_spo2', '%',
            'измерение ${_hhmm(_spo2At!.toLocal())} · Bluetooth')
        : const _Metric('SpO₂', Icons.bloodtype_outlined, kBlue, null, '',
            'Недоступно (нет измерений с часов)');
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
