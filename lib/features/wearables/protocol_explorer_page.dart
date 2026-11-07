// «Исследование протокола»: безопасный осмотр того, что часы сообщают о себе.
//
// Ничего не перебирается. Выполняются только: перечисление GATT-сервисов, чтение стандартных
// (SIG) характеристик, разбор списка сервисов Zepp OS, полученного при авторизации, один
// документированный запрос возможностей `01` в сервис 0x001e и проверка доступа ANCS.
// Все операции идут по очереди, по одной.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/widgets.dart';
import 'watch_ancs.dart';
import 'watch_settings.dart';
import 'wearable_controller.dart';
import 'zepp_notifications.dart';

enum ProbeStatus { supported, unsupported, unknown, timeout, error }

String probeStatusName(ProbeStatus s) => switch (s) {
      ProbeStatus.supported => 'SUPPORTED',
      ProbeStatus.unsupported => 'UNSUPPORTED',
      ProbeStatus.unknown => 'UNKNOWN',
      ProbeStatus.timeout => 'TIMEOUT',
      ProbeStatus.error => 'ERROR',
    };

class ProbeResult {
  final DateTime at;
  final String op;
  final String target;
  final ProbeStatus status;
  final String hex;
  final String note;
  final int ms;
  ProbeResult(this.op, this.target, this.status,
      {this.hex = '', this.note = '', this.ms = 0})
      : at = DateTime.now();

  String get line {
    final t = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}:'
        '${at.second.toString().padLeft(2, '0')}';
    return '[$t] $op | $target | ${probeStatusName(status)} | $ms мс'
        '${hex.isEmpty ? '' : ' | $hex'}${note.isEmpty ? '' : ' | $note'}';
  }
}

String hexOf(List<int> b, {int max = 64}) {
  final s = b
      .take(max)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  return b.length > max ? '$s …(${b.length} байт)' : s;
}

/// Сервисы стандарта Bluetooth SIG: UUID вида 0000xxxx-0000-1000-8000-00805f9b34fb.
bool isSigUuid(String uuid128) => RegExp(
        r'^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$',
        caseSensitive: false)
    .hasMatch(uuid128);

/// Разбор известной части ответа возможностей 0x001e и выделение неизвестных полей.
/// Источник структуры: Gadgetbridge, ZeppOsNotificationService (AGPLv3).
List<String> explainCaps(List<int> p) {
  final out = <String>[];
  if (p.length < 2) return ['слишком короткий ответ'];
  out.add('команда 0x${p[0].toRadixString(16).padLeft(2, '0')} '
      '(0x02 = ответ возможностей), версия протокола ${p[1]}');
  var o = 2;
  if (p[1] >= 4) {
    if (p.length < o + 6) return [...out, 'служебный блок оборван'];
    final n = p[o + 4] | (p[o + 5] << 8);
    out.add('НЕИЗВЕСТНО: поле u16 = ${p[o] | (p[o + 1] << 8)}, '
        'u8 = ${p[o + 2]}, u8 = ${p[o + 3]} (назначение в документации не найдено)');
    final end = (o + 6 + n).clamp(0, p.length);
    out.add('НЕИЗВЕСТНО: список из $n байт: ${hexOf(p.sublist(o + 6, end))}');
    o = end;
  }
  if (p[1] >= 5 && p.length >= o + 2) {
    out.add('значки приложений: ${p[o] != 0 ? 'поддерживаются' : 'нет'}, '
        'ключ: ${p[o + 1] != 0 ? 'поддерживается' : 'нет'}');
    o += 2;
  }
  if (o < p.length) {
    out.add('НЕИЗВЕСТНО: хвост ответа ${hexOf(p.sublist(o))}');
  }
  return out;
}

class ProtocolExplorerPage extends ConsumerStatefulWidget {
  const ProtocolExplorerPage({super.key});

  @override
  ConsumerState<ProtocolExplorerPage> createState() =>
      _ProtocolExplorerPageState();
}

class _ProtocolExplorerPageState extends ConsumerState<ProtocolExplorerPage> {
  final List<ProbeResult> _res = [];
  final List<String> _unknown = [];
  bool _running = false;
  bool _cancel = false;
  bool _done = false;
  int _checked = 0;
  int _total = 0;

  void _add(ProbeResult r) {
    if (!mounted) return;
    setState(() => _res.add(r));
    ref
        .read(wearableProvider)
        .addLog('исследование: ${r.op} ${r.target} ${probeStatusName(r.status)}');
  }

  Future<void> _scan() async {
    if (_running) return;
    final c = ref.read(wearableProvider);
    setState(() {
      _running = true;
      _cancel = false;
      _done = false;
      _res.clear();
      _unknown.clear();
      _checked = 0;
      _total = 0;
    });
    try {
      // 1. Подключение и авторизация.
      if (!c.isConnected) {
        _add(ProbeResult('Подключение', 'BLE', ProbeStatus.error,
            note: 'часы не подключены: подключите их на странице «Умные часы»'));
        return;
      }
      _add(ProbeResult('Подключение', 'BLE', ProbeStatus.supported));
      final s = c.session;
      if (s == null) {
        _add(ProbeResult('Авторизация', 'Huami 2021', ProbeStatus.error,
            note: 'авторизация не выполнена: дальше доступны только стандартные сервисы'));
      } else {
        _add(ProbeResult('Авторизация', 'Huami 2021', ProbeStatus.supported));
      }

      // 2–3. GATT-сервисы и характеристики.
      final svcs = List<BluetoothService>.of(c.services);
      var chars = 0;
      for (final sv in svcs) {
        chars += sv.characteristics.length;
      }
      setState(() => _total = svcs.length + chars);
      for (final sv in svcs) {
        if (_cancel) break;
        final sid = sv.uuid.str128.toLowerCase();
        _add(ProbeResult('GATT-сервис', sid, ProbeStatus.supported,
            note: '${sv.characteristics.length} характеристик'
                '${isSigUuid(sid) ? ', стандарт SIG' : ', собственный (не читается автоматически)'}'));
        setState(() => _checked++);
        for (final ch in sv.characteristics) {
          if (_cancel) break;
          final cid = ch.uuid.str128.toLowerCase();
          final p = ch.properties;
          final props = [
            if (p.read) 'read',
            if (p.write) 'write',
            if (p.writeWithoutResponse) 'writeNoResp',
            if (p.notify) 'notify',
            if (p.indicate) 'indicate',
          ].join(',');
          // 4. Читаем только стандартные характеристики: собственные могут быть служебными.
          if (p.read && isSigUuid(sid)) {
            final sw = Stopwatch()..start();
            try {
              final v = await ch.read().timeout(const Duration(seconds: 4));
              _add(ProbeResult('Чтение', cid, ProbeStatus.supported,
                  hex: hexOf(v),
                  ms: sw.elapsedMilliseconds,
                  note: 'свойства: $props'));
            } catch (e) {
              _add(ProbeResult('Чтение', cid, ProbeStatus.error,
                  ms: sw.elapsedMilliseconds, note: '$e'));
            }
          } else {
            _add(ProbeResult('Характеристика', cid, ProbeStatus.unknown,
                note: 'свойства: $props; значение не читалось'));
          }
          setState(() => _checked++);
        }
      }

      // Сервисы Zepp OS из ответа при авторизации.
      if (s != null && !_cancel) {
        final eps = s.endpoints.toList()..sort();
        _add(ProbeResult('Сервисы Zepp OS', 'эндпоинт 0x0000', ProbeStatus.supported,
            note: '${eps.length} сервисов, шифруется ${s.encryptedEndpoints.length}'));
        for (final e in eps) {
          final name = switch (e) {
            notifEndpoint => 'уведомления (Gadgetbridge: ZeppOsNotificationService)',
            cfgEndpoint => 'настройки часов (используется приложением)',
            findEndpoint => 'найти часы (используется приложением)',
            _ => 'назначение в проекте неизвестно',
          };
          _add(ProbeResult('Сервис', '0x${e.toRadixString(16).padLeft(4, '0')}',
              ProbeStatus.supported,
              note: '${s.encryptedEndpoints.contains(e) ? 'шифруется' : 'без шифрования'}; $name'));
          if (!const {notifEndpoint, cfgEndpoint, findEndpoint}.contains(e)) {
            _unknown.add('сервис 0x${e.toRadixString(16).padLeft(4, '0')}');
          }
        }
      }

      // 6–7. Документированный запрос возможностей `01` в сервис 0x001e.
      if (!_cancel) {
        if (s == null) {
          _add(ProbeResult('Возможности уведомлений', '0x001e', ProbeStatus.unknown,
              note: 'нет авторизации'));
        } else if (!s.endpoints.contains(notifEndpoint)) {
          _add(ProbeResult('Возможности уведомлений', '0x001e',
              ProbeStatus.unsupported,
              note: 'часы не заявили сервис в списке сервисов'));
        } else {
          final sw = Stopwatch()..start();
          final caps = await c.probeNotifCaps();
          if (caps == null) {
            _add(ProbeResult('Запрос возможностей 01', '0x001e', ProbeStatus.timeout,
                ms: sw.elapsedMilliseconds,
                note: 'ответ не получен; это не доказывает отсутствие поддержки'));
          } else {
            final List<int> raw = c.notifCapsRaw ?? const <int>[];
            _add(ProbeResult('Запрос возможностей 01', '0x001e',
                ProbeStatus.supported,
                hex: hexOf(raw),
                ms: sw.elapsedMilliseconds,
                note: 'версия ${caps.version}, значки ${caps.supportsPictures}, '
                    'ключ ${caps.supportsKey}'));
            for (final l in explainCaps(raw)) {
              _add(ProbeResult('Расшифровка', '0x001e', ProbeStatus.unknown,
                  note: l));
              if (l.startsWith('НЕИЗВЕСТНО')) _unknown.add('0x001e: $l');
            }
          }
        }
      }

      // 8. ANCS: публичный флаг iOS.
      if (!_cancel) {
        final sw = Stopwatch()..start();
        final a = await WatchAncs.status(c.savedId);
        final st = switch (a.state) {
          AncsState.authorized => ProbeStatus.supported,
          AncsState.denied => ProbeStatus.unsupported,
          _ => ProbeStatus.unknown,
        };
        _add(ProbeResult('Доступ часов к ANCS (iOS)', 'ancsAuthorized', st,
            ms: sw.elapsedMilliseconds,
            note: '${a.title}. Это разрешение iOS, а не признак поддержки '
                'фильтров на часах'));
      }

      _add(ProbeResult('Фильтр приложений на часах', 'не найден', ProbeStatus.unknown,
          note: 'команда не обнаружена ни в одном из доступных источников'));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _done = true;
        });
      }
    }
  }

  /// Сервисы, назначение которых известно из Gadgetbridge: их не трогаем.
  static const _knownEndpoints = {
    0x0000, 0x0001, 0x0003, 0x0006, 0x0007, 0x0009, 0x000a, 0x000b, 0x000d,
    0x000f, 0x0011, 0x0013, 0x0014, 0x0015, 0x001a, 0x001b, 0x001e, 0x0023,
    0x0026, 0x0038, 0x003a, 0x003c, 0x003f, 0x0042, 0x00a0,
  };

  bool _probing = false;

  /// Опрос неизвестных сервисов: в каждый отправляется один байт 0x01 («запрос»), как в
  /// большинстве сервисов Zepp OS. Выполняется по очереди с разрешения владельца часов.
  /// Ответ любого размера и содержимое пишутся в журнал; сервис 0x0001 маскируется.
  Future<void> _probeUnknown({List<int>? only, int cmd = 0x01}) async {
    final c = ref.read(wearableProvider);
    final s = c.session;
    final cmdHex = cmd.toRadixString(16).padLeft(2, '0');
    if (s == null) {
      toast(context, 'Часы не подключены или не авторизованы.');
      return;
    }
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(only == null ? 'Опросить неизвестные сервисы?' : 'Отправить $cmdHex в сервисы-кандидаты?'),
              content: Text(
                  'В ${only == null ? 'каждый неопознанный сервис' : 'выбранные сервисы'} часов будет отправлен один байт $cmdHex '
                  '(запрос). Команды перебора и записи настроек не отправляются, но '
                  'назначение сервисов неизвестно, поэтому полной гарантии, что часы '
                  'не отреагируют на запрос, нет. Продолжить?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Отмена')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Опросить')),
              ],
            ));
    if (ok != true || !mounted) return;
    final targets = (only ??
            s.endpoints.where((e) => !_knownEndpoints.contains(e)).toList())
        .where(s.endpoints.contains)
        .toList()
      ..sort();
    setState(() {
      _probing = true;
      _cancel = false;
      _checked = 0;
      _total = targets.length;
    });
    final got = <int, List<Uint8List>>{};
    c.probeListener = (t, p) => got.putIfAbsent(t, () => []).add(p);
    try {
      for (final e in targets) {
        if (_cancel || !c.isConnected || c.session == null) break;
        final name = '0x${e.toRadixString(16).padLeft(4, '0')}';
        got.remove(e);
        final sw = Stopwatch()..start();
        try {
          await c.session!.send(e, [cmd]);
        } catch (err) {
          _add(ProbeResult('Запрос $cmdHex', name, ProbeStatus.error,
              ms: sw.elapsedMilliseconds, note: '$err'));
          setState(() => _checked++);
          continue;
        }
        await Future.delayed(const Duration(milliseconds: 1500));
        final r = got[e];
        if (r == null || r.isEmpty) {
          _add(ProbeResult('Запрос $cmdHex', name, ProbeStatus.timeout,
              ms: sw.elapsedMilliseconds,
              note: 'ответа нет: сервис не отреагировал или команда ему не знакома'));
        } else {
          for (final p in r) {
            _add(ProbeResult('Запрос $cmdHex', name, ProbeStatus.supported,
                hex: e == 0x0001 ? '(скрыто)' : hexOf(p),
                ms: sw.elapsedMilliseconds,
                note: 'ответ ${p.length} байт'));
          }
          _unknown.add('сервис $name ответил на $cmdHex: '
              '${e == 0x0001 ? '(скрыто)' : hexOf(r.first, max: 24)}');
        }
        setState(() => _checked++);
      }
    } finally {
      c.probeListener = null;
      if (mounted) {
        setState(() {
          _probing = false;
          _done = true;
        });
      }
    }
  }

  String _report() {
    final c = ref.read(wearableProvider);
    final b = StringBuffer()
      ..writeln('ОТЧЁТ: исследование протокола уведомлений Amazfit GTR 4')
      ..writeln('Прошивка: ${c.fw ?? '—'}')
      ..writeln('Проверено элементов: $_checked из $_total')
      ..writeln('')
      ..writeln('— Журнал операций —');
    for (final r in _res) {
      b.writeln(r.line);
    }
    b
      ..writeln('')
      ..writeln('— Неизвестные поля и сервисы (нужны дальнейшие исследования) —');
    if (_unknown.isEmpty) b.writeln('нет');
    for (final u in _unknown) {
      b.writeln(u);
    }
    b
      ..writeln('')
      ..writeln('— Выводы —')
      ..writeln('Подтверждено только то, что получено ответом часов или указано в списке '
          'сервисов. Фильтр приложений на часах: источник не найден, значение UNKNOWN.')
      ..writeln('Следующий шаг: запись обмена Zepp с часами (Bluetooth logging profile '
          'на iPhone) при переключении приложения в списке уведомлений.');
    return b.toString();
  }

  Future<void> _export() async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/protocol_report.txt');
      await f.writeAsString(_report());
      await Share.shareXFiles([XFile(f.path)]);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось экспортировать: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Color col(ProbeStatus s) => switch (s) {
          ProbeStatus.supported => Colors.green.shade700,
          ProbeStatus.unsupported => Colors.red.shade700,
          ProbeStatus.error => Colors.red.shade700,
          ProbeStatus.timeout => Colors.orange.shade800,
          ProbeStatus.unknown => muted,
        };

    Widget hyp(String svc, String cmd, String payload, String answer,
            String source, String effects, String risk) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
              'Сервис: $svc\nКоманда: $cmd\nДанные: $payload\nОжидаемый ответ: $answer\n'
              'Источник: $source\nПобочные эффекты: $effects\nРиск: $risk',
              style: TextStyle(fontSize: 12, color: muted, height: 1.35)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Исследование протокола')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Осмотр часов без перебора команд: сервисы, стандартные характеристики, '
                'список сервисов Zepp OS и один документированный запрос возможностей. '
                'Настройки часов не меняются.',
                style: TextStyle(fontSize: 12.5, color: muted)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                    onPressed: _running ? null : _scan,
                    icon: const Icon(Icons.search),
                    label: const Text('Начать сканирование')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: (_running || _probing)
                      ? () => setState(() => _cancel = true)
                      : null,
                  child: const Text('Остановить')),
            ]),
            if (_running || _done) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value: _running
                      ? (_total == 0 ? null : (_checked / _total).clamp(0.0, 1.0))
                      : 1),
              const SizedBox(height: 4),
              Text('Проверено: $_checked из $_total, операций: ${_res.length}',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: (_running || _probing) ? null : _probeUnknown,
                icon: const Icon(Icons.network_check),
                label: Text(_probing
                    ? 'Опрос: $_checked из $_total'
                    : 'Опросить неизвестные сервисы (01)')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: (_running || _probing)
                    ? null
                    : () => _probeUnknown(
                        only: const [0x001f, 0x001c, 0x000c, 0x0046, 0x0012],
                        cmd: 0x03),
                icon: const Icon(Icons.manage_search),
                label: const Text('Запрос 03 в сервисы-кандидаты')),
          ]),
        ),
        const SizedBox(height: 12),
        if (_res.isNotEmpty)
          AppCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Результаты',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  for (final r in _res)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${r.op} · ${r.target}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(probeStatusName(r.status),
                                style: TextStyle(
                                    color: col(r.status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            if (r.hex.isNotEmpty)
                              SelectableText(r.hex,
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      color: muted)),
                            if (r.note.isNotEmpty)
                              Text(r.note,
                                  style: TextStyle(fontSize: 12, color: muted)),
                          ]),
                    ),
                ]),
          ),
        if (_done) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Неизвестные поля и сервисы',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  if (_unknown.isEmpty)
                    Text('Нет', style: TextStyle(color: muted))
                  else
                    for (final u in _unknown)
                      Text('• $u',
                          style: TextStyle(fontSize: 12, color: muted)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: _report()));
                            if (context.mounted) {
                              toast(context, 'Журнал скопирован');
                            }
                          },
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Скопировать журнал')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                          onPressed: _export,
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Экспортировать')),
                    ),
                  ]),
                ]),
          ),
        ],
        const SizedBox(height: 12),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Экспериментальные гипотезы',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Здесь только команды с конкретным источником. Автоматически они не '
                'выполняются.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            hyp(
                '0x001e (уведомления)',
                '0x01 «запрос возможностей»',
                'один байт 0x01',
                '0x02, версия, служебный блок, флаги',
                'Gadgetbridge, ZeppOsNotificationService; подтверждено ответом GTR 4',
                'нет',
                'низкий (выполняется при сканировании)'),
            hyp(
                '0x001e (уведомления)',
                '0x10 «запрос значка» (приходит от часов)',
                'часы → телефон: <пакет>\\0, формат, размер',
                'ответ 0x11 с файлом значка',
                'Gadgetbridge; на GTR 4 запрос приходит, ответ приложением не реализован',
                'часы могут показать значок приложения',
                'низкий; не выполняется'),
            hyp(
                'неизвестен',
                'фильтр приложений ANCS',
                'неизвестно',
                'неизвестно',
                'источника нет: нужен перехват обмена Zepp с часами',
                'неизвестны, возможна запись в настройки часов',
                'ВЫСОКИЙ; не выполняется, пока нет подтверждённого формата'),
          ]),
        ),
      ]),
    );
  }
}
