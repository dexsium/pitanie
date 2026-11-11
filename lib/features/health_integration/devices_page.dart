import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import '../dashboard/day_data.dart' show kMainSourceKey;
import '../scale/scale_controller.dart';
import '../scale/scale_setup_page.dart';
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
      'ok' => 'Синхронизировано: записей ${r.records}, тренировок ${r.workouts}'
          '${r.weights > 0 ? ', взвешиваний ${r.weights}' : ''}',
      'no_data' =>
        'Новых данных нет. Проверьте, что приложение часов (Huawei Health, Zepp) записывает данные в хранилище здоровья.',
      'no_access' => 'Нет доступа к данным здоровья. Проверьте разрешения.',
      'unavailable' => 'Health Connect не установлен или недоступен',
      'not_connected' => 'Сначала подключите источник',
      'unsupported' => 'Платформа не поддерживает источник здоровья',
      'error' => 'Ошибка: ${r.error}',
      _ => r.status,
    };

/// Экран «Источники здоровья»: Apple Health / Health Connect, категории данных, источник по
/// умолчанию, весы и отключение. Приложение не подключается к часам напрямую по Bluetooth.
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(healthServiceProvider);
    final src = ref.watch(sourceProvider).valueOrNull;
    final busy = ref.watch(syncBusyProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? const <String, String>{};
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

    final per = (report?['perType'] as Map?)?.cast<String, dynamic>() ?? const {};
    final errors = (report?['errors'] as Map?)?.cast<String, dynamic>() ?? const {};
    final found = (report?['sources'] as Map?)?.cast<String, dynamic>() ?? const {};
    final supported = svc.types.map((t) => t.name).toSet();
    final choice = settings[kMainSourceKey] ?? 'auto';
    final options = <String, String>{
      'auto': 'Автоматически (источник с большим объёмом данных)',
      for (final e in found.entries) e.key: '${e.value}',
      if (choice != 'auto' && !found.containsKey(choice)) choice: choice,
    };
    final dups = ((report?['duplicates'] ?? 0) as num).toInt();
    final deleted = ((report?['deleted'] ?? 0) as num).toInt();

    Widget title(String t, IconData i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(i, color: kPrimary, size: 26),
            const SizedBox(width: 10),
            Expanded(
                child: Text(t,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Источники здоровья')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Платформа
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title(svc.sourceLabel, Icons.favorite_outline),
            _row('Статус', statusLabel(src?.syncStatus ?? 'not_connected')),
            _row('Последняя синхронизация',
                src?.lastSync == null ? '—' : '${shortDate(src!.lastSync!)} ${fmtTime(src.lastSync!)}'),
            if (report?['error'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Ошибка: ${report!['error']}',
                    style: const TextStyle(color: kRed, fontSize: 12.5)),
              ),
            if (dups > 0 || deleted > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Совпавших взвешиваний пропущено: $dups; '
                    'удалённых в источнике записей убрано: $deleted',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
            const SizedBox(height: 12),
            if (src == null)
              FilledButton.icon(
                  onPressed: busy ? null : connect,
                  icon: const Icon(Icons.link),
                  label: const Text('Подключить'))
            else ...[
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async => syncMessage(await svc.sync(full: true))),
                icon: const Icon(Icons.sync),
                label: const Text('Синхронизировать'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
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
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text('OK'))
                                    ],
                                  ));
                        } else {
                          await connect();
                        }
                      },
                child: const Text('Настроить разрешения'),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),

        // Категории данных
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title('Какие данные читаются', Icons.fact_check_outlined),
            for (final c in kHealthCategories.entries)
              if (c.value.any(supported.contains))
                _category(c.key, [for (final t in c.value) if (supported.contains(t)) t], per,
                    errors, report != null),
            const SizedBox(height: 6),
            Text(
                Platform.isIOS
                    ? 'Apple Health не сообщает приложению, выдан ли доступ на чтение: «нет данных» '
                        'означает, что записей не пришло. Доступ меняется в Настройки → Здоровье.'
                    : 'Категории, к которым нет доступа, помечены. Доступ меняется в Health Connect.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 12),

        // Предпочтительный источник
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            title('Предпочтительный источник', Icons.compare_arrows),
            Text(
                'Если одни и те же данные пишут два приложения (например, часы и телефон), '
                'учитывается только один источник, суммирования нет.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: options.containsKey(choice) ? choice : 'auto',
              isExpanded: true,
              items: [
                for (final e in options.entries)
                  DropdownMenuItem(
                      value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) async {
                if (v == null) return;
                await ref.read(dbProvider).setSetting(kMainSourceKey, v);
              },
            ),
            if (found.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Список источников появится после синхронизации.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
          ]),
        ),
        const SizedBox(height: 12),

        // Весы
        AppCard(child: _ScaleBlock(title('Умные весы', Icons.monitor_weight_outlined))),
        const SizedBox(height: 12),

        AppCard(
          child: Text(
            'Приложение не подключается к часам напрямую по Bluetooth. '
            'Часы (Huawei Watch Fit 4, Amazfit и другие) синхронизируются со своим приложением '
            '(Huawei Health, Zepp), а оно передаёт данные в ${svc.sourceLabel}, откуда их читает '
            'это приложение. Данные появляются с задержкой и только те, которые приложение часов '
            'реально записывает. Для Huawei Health включите запись в Apple Health в его настройках.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        if (src != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: kRed),
            onPressed: busy
                ? null
                : () async {
                    if (await confirmDialog(context, 'Отключить источник?',
                        'Ранее полученные данные останутся в приложении. Доступ можно снова выдать кнопкой «Подключить».',
                        ok: 'Отключить')) {
                      await svc.disconnect();
                    }
                  },
            child: const Text('Отключить источник'),
          ),
        ],
      ]),
    );
  }

  Widget _category(String name, List<String> typeNames, Map<String, dynamic> per,
      Map<String, dynamic> errors, bool hasReport) {
    var count = 0;
    var errs = 0;
    for (final t in typeNames) {
      count += ((per[t] ?? 0) as num).toInt();
      if (errors.containsKey(t)) errs++;
    }
    final denied = errs == typeNames.length;
    final (IconData icon, Color color, String text) = !hasReport
        ? (Icons.help_outline, Colors.grey, 'ещё не читалось')
        : count > 0
            ? (Icons.check_circle, kGreen, '$count зап.')
            : denied
                ? (Icons.block, kRed, 'нет доступа')
                : (Icons.remove_circle_outline, Colors.grey, 'нет данных');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(name)),
        Text(text, style: TextStyle(color: color == kGreen ? null : color)),
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

/// Состояние Bluetooth-весов: последнее взвешивание и подсказка, если измерений не было.
class _ScaleBlock extends ConsumerWidget {
  final Widget header;
  const _ScaleBlock(this.header);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(scaleProvider);
    final cs = Theme.of(context).colorScheme;
    final at = scale.lastAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      header,
      Text('Mi Body Composition Scale 2', style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      Text(
          at == null
              ? 'Взвешиваний за этот запуск не было. Встаньте на весы при открытом приложении.'
              : 'Последнее взвешивание: ${shortDate(at)} ${fmtTime(at)}',
          style: const TextStyle(fontSize: 13.5)),
      if (scale.gattId != null && scale.gattId!.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('Дополнительные весы: ${scale.gattName ?? scale.gattId}',
            style: const TextStyle(fontSize: 13.5)),
      ],
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ScaleSetupPage())),
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Другие весы (стандартный Bluetooth)'),
      ),
      const SizedBox(height: 8),
      Text(
          'Вес также можно получить из Здоровья, если фирменное приложение весов записывает '
          'его туда: совпавшие по времени и массе измерения не дублируются.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]);
  }
}
