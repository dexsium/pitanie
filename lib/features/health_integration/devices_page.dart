import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import 'health_service.dart';

String statusLabel(String s) => switch (s) {
      'ok' => 'Подключено',
      'waiting' => 'Ожидается синхронизация',
      'no_data' => 'Подключено, данных нет',
      'no_access' => 'Нет доступа',
      'unavailable' => 'Health Connect недоступен',
      'error' => 'Ошибка синхронизации',
      _ => 'Не подключено',
    };

String syncMessage(SyncResult r) => switch (r.status) {
      'ok' => 'Синхронизировано: записей ${r.records}, тренировок ${r.workouts}',
      'no_data' => 'Новых данных нет. Проверьте, что Zepp экспортирует данные в хранилище здоровья.',
      'unavailable' => 'Health Connect не установлен или недоступен',
      'not_connected' => 'Сначала подключите источник',
      'unsupported' => 'Платформа не поддерживает источник здоровья',
      'error' => 'Ошибка: ${r.error}',
      _ => r.status,
    };

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(healthServiceProvider);
    final src = ref.watch(sourceProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    final busy = ref.watch(syncBusyProvider);
    final cs = Theme.of(context).colorScheme;

    Future<void> run(Future<String> Function() f) async {
      ref.read(syncBusyProvider.notifier).state = true;
      try {
        final msg = await f();
        if (context.mounted) toast(context, msg);
      } catch (e) {
        if (context.mounted) toast(context, 'Ошибка: $e');
      } finally {
        ref.read(syncBusyProvider.notifier).state = false;
      }
    }

    Future<void> connect() => run(() async {
          if (!HealthService.supported) return 'Доступно только на Android и iOS';
          if (!await svc.available()) {
            await svc.installHealthConnect();
            return 'Установите Health Connect и повторите';
          }
          final ok = await svc.requestPermissions();
          if (!ok) {
            return Platform.isIOS
                ? 'Доступ не выдан. Проверьте Настройки → Здоровье → Доступ к данным'
                : 'Разрешения не выданы';
          }
          return syncMessage(await svc.sync(full: true));
        });

    Map<String, dynamic>? report;
    try {
      if (src?.lastReport != null) report = jsonDecode(src!.lastReport!) as Map<String, dynamic>;
    } catch (_) {}

    return Scaffold(
      appBar: AppBar(title: const Text('Устройства')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.watch, color: kPrimary, size: 30),
              SizedBox(width: 12),
              Text('Amazfit GTR 4', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            _row('Источник данных', svc.sourceLabel),
            _row('Статус', statusLabel(src?.syncStatus ?? 'not_connected')),
            _row('Последняя синхронизация',
                src?.lastSync == null ? '—' : '${shortDate(src!.lastSync!)} ${fmtTime(src.lastSync!)}'),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: busy ? null : connect,
                icon: const Icon(Icons.link),
                label: Text(src == null ? 'Подключить' : 'Подключить заново')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || src == null
                      ? null
                      : () => run(() async => syncMessage(await svc.sync(full: true))),
                  icon: const Icon(Icons.sync),
                  label: const Text('Синхронизировать'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (Platform.isIOS) {
                            await showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                      title: const Text('Разрешения Apple Health'),
                                      content: const Text(
                                          'Откройте Настройки → Здоровье → Доступ к данным и устройства → это приложение и включите нужные категории.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(c), child: const Text('OK'))
                                      ],
                                    ));
                          } else {
                            await connect();
                          }
                        },
                  child: const Text('Настроить разрешения'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: kRed),
                  onPressed: src == null
                      ? null
                      : () async {
                          if (await confirmDialog(context, 'Отключить источник?',
                              'Ранее полученные данные останутся в приложении.',
                              ok: 'Отключить')) {
                            await svc.disconnect();
                          }
                        },
                  child: const Text('Отключить'),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Text(
            'Подключение к ${svc.sourceLabel} не означает прямого Bluetooth-соединения с часами. '
            'Часы синхронизируются с приложением Zepp, а Zepp передаёт данные в ${svc.sourceLabel}, '
            'откуда их читает это приложение. Поэтому данные появляются с задержкой и только те, '
            'которые Zepp реально экспортирует.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        _Priority(settings['preferred_source'] ?? ''),
        const SizedBox(height: 12),
        if (report != null) _Diagnostics(report),
      ]),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a)),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Priority extends ConsumerWidget {
  final String current;
  const _Priority(this.current);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return AppCard(
      child: FutureBuilder(
        future: db.activityBetween(DateTime.now().subtract(const Duration(days: 30)), DateTime.now()),
        builder: (context, snap) {
          final names = <String, String>{};
          for (final r in snap.data ?? []) {
            names[r.source] = r.sourceName.isEmpty ? r.source : r.sourceName;
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Приоритетный источник',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Чтобы шаги и калории не считались дважды, за каждый день берётся один источник.',
                style: TextStyle(fontSize: 12.5)),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: '',
              groupValue: current,
              title: const Text('Автоматически (с наибольшим объёмом)'),
              onChanged: (_) => db.removeSetting('preferred_source'),
            ),
            for (final e in names.entries)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: e.key,
                groupValue: current,
                title: Text(e.value),
                subtitle: Text(e.key, style: const TextStyle(fontSize: 11)),
                onChanged: (v) => db.setSetting('preferred_source', v!),
              ),
          ]);
        },
      ),
    );
  }
}

class _Diagnostics extends StatelessWidget {
  final Map<String, dynamic> r;
  const _Diagnostics(this.r);

  @override
  Widget build(BuildContext context) {
    final per = (r['perType'] as Map?)?.cast<String, dynamic>() ?? {};
    final sources = (r['sources'] as Map?)?.cast<String, dynamic>() ?? {};
    const all = {
      'steps': 'Шаги',
      'distance': 'Расстояние',
      'activeEnergy': 'Активные калории',
      'totalEnergy': 'Общий расход',
      'heartRate': 'Пульс',
      'sleep': 'Сон',
      'WORKOUT': 'Тренировки',
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Диагностика последней синхронизации',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Показывает, какие данные реально пришли от Zepp.',
            style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 8),
        for (final e in all.entries)
          Row(children: [
            Icon(per.containsKey(e.key) ? Icons.check_circle : Icons.remove_circle_outline,
                size: 18, color: per.containsKey(e.key) ? kGreen : Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text(e.value)),
            Text(per.containsKey(e.key) ? '${per[e.key]} зап.' : 'нет данных'),
          ]),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Источники: ${sources.values.join(', ')}', style: const TextStyle(fontSize: 12.5)),
        ],
        if (r['error'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Ошибка: ${r['error']}', style: const TextStyle(color: kRed, fontSize: 12.5)),
          ),
      ]),
    );
  }
}
