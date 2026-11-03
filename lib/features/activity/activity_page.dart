import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../wearables/heart_rate_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../shared/widgets.dart';
import '../dashboard/day_data.dart';
import '../calendar/calendar_page.dart';
import '../health_integration/devices_page.dart';

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final key = dayKey(day);
    final a = ref.watch(dayDataProvider(key)).valueOrNull?.activity;
    final src = ref.watch(sourceProvider).valueOrNull;
    final busy = ref.watch(syncBusyProvider);
    final week = ref
        .watch(rangeStatsProvider((from: dayKey(day.subtract(const Duration(days: 6))), to: key)))
        .valueOrNull;
    final cs = Theme.of(context).colorScheme;

    Widget tile(IconData i, Color c, String v, String l) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, color: c),
              const SizedBox(height: 6),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      DayBar(
        onCalendar: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const CalendarPage())),
        trailing: IconButton.filledTonal(
          tooltip: 'Устройства',
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesPage())),
          icon: const Icon(Icons.watch_outlined),
        ),
      ),
      const SizedBox(height: 16),
      AppCard(
        child: Row(children: [
          Icon(src == null ? Icons.watch_off_outlined : Icons.watch, color: kPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(src == null ? 'Источник не подключён' : 'Amazfit GTR 4 · ${statusLabel(src.syncStatus)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                src?.lastSync == null
                    ? 'Подключите Health Connect / Apple Health в разделе «Устройства»'
                    : 'Последняя синхронизация: ${fmtTime(src!.lastSync!)}'
                        '${isSameDay(src.lastSync!, DateTime.now()) ? '' : ', ${shortDate(src.lastSync!)}'}',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
          IconButton(
            onPressed: busy || src == null
                ? null
                : () async {
                    ref.read(syncBusyProvider.notifier).state = true;
                    final r = await ref.read(healthServiceProvider).sync();
                    ref.read(syncBusyProvider.notifier).state = false;
                    if (context.mounted) toast(context, syncMessage(r));
                  },
            icon: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      if (a == null || !a.hasData && a.sleepMinutes == 0)
        const EmptyHint(
            'За этот день нет данных об активности.\nДанные появляются после синхронизации часов с Zepp и экспорта в систему здоровья.')
      else ...[
        Row(children: [
          tile(Icons.directions_walk, Colors.grey, fmt0(a.steps), 'шагов'),
          const SizedBox(width: 10),
          tile(Icons.place, kGreen, fmt1(a.distanceKm), 'км'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.local_fire_department, kOrange, fmt0(a.activeKcal), 'активных ккал'),
          const SizedBox(width: 10),
          tile(Icons.schedule, kBlue, fmt0(a.workoutMinutes), 'мин тренировок'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.favorite, kRed,
              a.avgHr == null ? '—' : '${fmt0(a.avgHr!)} / ${fmt0(a.maxHr!)}', 'пульс средний / макс.'),
          const SizedBox(width: 10),
          tile(Icons.bedtime, kViolet,
              a.sleepMinutes <= 0 ? '—' : '${(a.sleepMinutes ~/ 60)} ч ${(a.sleepMinutes % 60).round()} м', 'сон'),
        ]),
        if (a.sleepStart != null && a.sleepMinutes > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'Сон: ${fmtTime(a.sleepStart!)} — ${fmtTime(a.sleepEnd!)}. Фазы (приблизительно): '
                'глубокий ${fmt0(a.sleepDeepMin)} мин, REM ${fmt0(a.sleepRemMin)} мин, '
                'лёгкий ${fmt0(a.sleepLightMin)} мин. Разбивка по фазам — оценка по данным часов, '
                'а не точное измерение.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.bloodtype_outlined, kBlue, a.spo2 == null ? '—' : '${fmt0(a.spo2!)} %', 'SpO₂ (последнее)'),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const HeartRatePage())),
                icon: const Icon(Icons.show_chart),
                label: const Text('График пульса')),
          ),
        ]),
        if (a.totalKcal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Общий расход энергии: ${fmt0(a.totalKcal)} ккал (отдельно от активных калорий)',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ),
        if (a.source != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Источник за день: ${sourceLabel(a.source)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
      ],
      const SizedBox(height: 16),
      const SectionTitle('Тренировки', icon: Icons.fitness_center),
      if (a == null || a.workouts.isEmpty) const EmptyHint('Тренировок за день нет'),
      if (a != null)
        for (final w in a.workouts)
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Icon(Icons.directions_run, color: kPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(workoutLabel(w.workoutType), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${fmtTime(w.startTime)}–${fmtTime(w.endTime)} · ${fmt0(w.endTime.difference(w.startTime).inMinutes)} мин'
                    '${w.energyKcal != null ? ' · ${fmt0(w.energyKcal!)} ккал' : ''}'
                    '${w.distanceM != null ? ' · ${fmt1(w.distanceM! / 1000)} км' : ''}'
                    '${w.avgHr != null ? ' · пульс ${fmt0(w.avgHr!)}/${fmt0(w.maxHr!)}' : ''}',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
      const SizedBox(height: 16),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Шаги за 7 дней', icon: Icons.bar_chart, color: kPrimary),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: week == null
                ? const SizedBox()
                : BarChart(BarChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('${day.subtract(Duration(days: 6 - v.toInt())).day}',
                                style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < 7; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                              toY: week[dayKey(day.subtract(Duration(days: 6 - i)))]?.act.steps ?? 0,
                              color: kPrimary,
                              width: 18,
                              borderRadius: BorderRadius.circular(6)),
                        ]),
                    ],
                  )),
          ),
        ]),
      ),
    ]);
  }
}
