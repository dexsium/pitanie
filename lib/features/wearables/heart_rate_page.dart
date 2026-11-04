import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../dashboard/day_data.dart' show kBleSource, sourceLabel;

/// Суточный график пульса. Точки берутся из локальной базы приложения, поэтому
/// график строится и за прошлые дни, даже если часы столько не хранят.
class HeartRatePage extends ConsumerStatefulWidget {
  const HeartRatePage({super.key});
  @override
  ConsumerState<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends ConsumerState<HeartRatePage> {
  late DateTime _day = dayStart(DateTime.now());

  Future<List<ActivityRecord>> _load() async {
    final db = ref.read(dbProvider);
    final recs = await db.activityBetween(_day, dayEnd(_day));
    final hr = recs.where((r) => r.type == 'heartRate').toList();
    // Как в остальном приложении: один источник, данные часов приоритетнее.
    final ble = hr.where((r) => r.source == kBleSource).toList();
    return ble.isNotEmpty ? ble : hr;
  }

  @override
  Widget build(BuildContext context) {
    // Перерисовка при поступлении новых записей.
    ref.watch(dayDataProvider(dayKey(_day)));
    final cs = Theme.of(context).colorScheme;
    final isToday = dayStart(DateTime.now()) == _day;
    return Scaffold(
      appBar: AppBar(title: const Text('Пульс')),
      body: FutureBuilder<List<ActivityRecord>>(
        future: _load(),
        builder: (context, snap) {
          final recs = snap.data ?? const <ActivityRecord>[];
          // Только точки выбранных суток и не из будущего: иначе запись соседнего дня
          // (в графике группируется по времени суток) тянет линию к краю графика.
          final nextDay = _day.add(const Duration(days: 1));
          final now = DateTime.now();
          final pts = recs
              .map((r) => (r.startTime.toLocal(), r.value))
              .where((p) =>
                  p.$2 >= 30 &&
                  p.$2 <= 230 &&
                  !p.$1.isBefore(_day) &&
                  p.$1.isBefore(nextDay) &&
                  !p.$1.isAfter(now))
              .toList()
            ..sort((a, b) => a.$1.compareTo(b.$1));
          // Сглаживание: средние по 5 минутам, если точек много.
          final bins = <int, List<double>>{};
          for (final p in pts) {
            final m = p.$1.hour * 60 + p.$1.minute;
            bins.putIfAbsent(m ~/ 5 * 5, () => []).add(p.$2);
          }
          final spots = [
            for (final e in (bins.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
              FlSpot(e.key.toDouble(), e.value.reduce((a, b) => a + b) / e.value.length)
          ];
          final values = pts.map((p) => p.$2).toList();
          final min = values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
          final max = values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
          final avg = values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
          final src = recs.isEmpty ? null : sourceLabel(recs.first.source == kBleSource
              ? kBleSource
              : recs.first.sourceName);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              IconButton(
                  onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Column(children: [
                  Text(dayTitle(_day),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(dayDateLine(_day), style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
              IconButton(
                  onPressed: isToday
                      ? null
                      : () => setState(() => _day = _day.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right)),
            ]),
            const SizedBox(height: 12),
            AppCard(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _stat('Мин.', min),
                _stat('Средний', avg),
                _stat('Макс.', max),
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: spots.length < 2
                  ? const SizedBox(
                      height: 200,
                      child: Center(
                          child: Text('Нет данных о пульсе за этот день',
                              textAlign: TextAlign.center)))
                  : SizedBox(
                      height: 240,
                      child: LineChart(LineChartData(
                        minX: 0,
                        maxX: 1440,
                        minY: ((min ?? 50) - 10).floorToDouble().clamp(30, 200),
                        maxY: ((max ?? 120) + 10).ceilToDouble().clamp(60, 230),
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 34,
                                  getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                                      style: const TextStyle(fontSize: 11)))),
                          bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 360,
                                  getTitlesWidget: (v, _) => Text(
                                      '${(v / 60).round().toString().padLeft(2, '0')}:00',
                                      style: const TextStyle(fontSize: 11)))),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            curveSmoothness: 0.15,
                            color: kRed,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            belowBarData:
                                BarAreaData(show: true, color: kRed.withOpacity(0.12)),
                          ),
                        ],
                      )),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
                src == null
                    ? 'Данные накапливаются в приложении при подключении часов.'
                    : 'Источник: $src. Точек: ${pts.length}. История хранится в приложении.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]);
        },
      ),
    );
  }

  Widget _stat(String l, double? v) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Text(v == null ? '—' : fmt0(v),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const Text('уд/мин', style: TextStyle(fontSize: 11)),
      ]);
}
