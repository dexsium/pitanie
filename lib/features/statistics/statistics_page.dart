import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import '../calendar/calendar_page.dart';

enum _Period { day, week, month }

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});
  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  _Period _p = _Period.week;

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedDayProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      const Text('Статистика', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SegmentedButton<_Period>(
        segments: const [
          ButtonSegment(value: _Period.day, label: Text('День')),
          ButtonSegment(value: _Period.week, label: Text('Неделя')),
          ButtonSegment(value: _Period.month, label: Text('Месяц')),
        ],
        selected: {_p},
        onSelectionChanged: (s) => setState(() => _p = s.first),
      ),
      const SizedBox(height: 12),
      const DayBar(),
      const SizedBox(height: 12),
      switch (_p) {
        _Period.day => DayDetail(dayKeyStr: dayKey(sel)),
        _Period.week => _Week(sel),
        _Period.month => _Month(sel),
      },
    ]);
  }
}

class _Series extends StatelessWidget {
  final String title, unit;
  final Color color;
  final List<double> values;
  final List<String> labels;
  final double? goal;
  final int decimals;
  const _Series(this.title, this.unit, this.color, this.values, this.labels,
      {this.goal, this.decimals = 0});

  @override
  Widget build(BuildContext context) {
    final withData = values.where((v) => v > 0).toList();
    final avg = withData.isEmpty ? 0.0 : withData.reduce((a, b) => a + b) / withData.length;
    final maxV = [...values, goal ?? 0].reduce((a, b) => a > b ? a : b);
    String f(double v) => decimals == 0 ? fmt0(v) : fmt1(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            Text('среднее: ${f(avg)} $unit', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: BarChart(BarChartData(
              maxY: maxV <= 0 ? 1 : maxV * 1.15,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) =>
                      BarTooltipItem('${f(r.toY)} $unit', const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(labels[v.toInt()], style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              ),
              extraLinesData: goal == null
                  ? null
                  : ExtraLinesData(horizontalLines: [
                      HorizontalLine(y: goal!, color: color.withOpacity(0.6), dashArray: [5, 4], strokeWidth: 1.5)
                    ]),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                        toY: values[i],
                        color: color,
                        width: values.length > 10 ? 6 : 18,
                        borderRadius: BorderRadius.circular(5)),
                  ]),
              ],
            )),
          ),
        ]),
      ),
    );
  }
}

class _Week extends ConsumerWidget {
  final DateTime end;
  const _Week(this.end);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = end.subtract(const Duration(days: 6));
    final stats = ref.watch(rangeStatsProvider((from: dayKey(start), to: dayKey(end)))).valueOrNull;
    if (stats == null) return const Center(child: CircularProgressIndicator());
    final list = [for (var i = 0; i < 7; i++) stats[dayKey(start.add(Duration(days: i)))]!];
    final labels = [for (final s in list) DateFormat('E', 'ru').format(parseDayKey(s.key))];
    final g = list.last.goal;
    return Column(children: [
      _Series('Калории', 'ккал', kOrange, [for (final s in list) s.n.calories], labels, goal: g.calories),
      _Series('Белки', 'г', kBlue, [for (final s in list) s.n.proteins], labels, goal: g.proteins),
      _Series('Жиры', 'г', kOrange, [for (final s in list) s.n.fats], labels, goal: g.fats),
      _Series('Углеводы', 'г', kViolet, [for (final s in list) s.n.carbs], labels, goal: g.carbs),
      _Series('Вода', 'мл', kBlue, [for (final s in list) s.waterMl], labels, goal: g.waterMl),
      _Series('Шаги', '', kPrimary, [for (final s in list) s.act.steps], labels),
      _Series('Активные калории', 'ккал', kGreen, [for (final s in list) s.act.activeKcal], labels),
    ]);
  }
}

class _Month extends ConsumerWidget {
  final DateTime sel;
  const _Month(this.sel);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = DateTime(sel.year, sel.month, 1);
    final last = DateTime(sel.year, sel.month + 1, 0);
    final stats = ref.watch(rangeStatsProvider((from: dayKey(first), to: dayKey(last)))).valueOrNull;
    if (stats == null) return const Center(child: CircularProgressIndicator());
    final days = stats.values.toList();
    final withFood = days.where((s) => s.hasFood).toList();
    double avg(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    final stepsDays = days.where((s) => s.act.steps > 0).toList();
    final weights = days.where((s) => s.weight != null).toList();
    final met = withFood.where((s) => s.met).length;
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [Expanded(child: Text(l)), Text(v, style: const TextStyle(fontWeight: FontWeight.w800))]),
        );
    return Column(children: [
      AppCard(
        child: Column(children: [
          MonthGrid(
            month: first,
            stats: stats,
            selected: sel,
            onSelect: (d) => ref.read(selectedDayProvider.notifier).state = d,
          ),
        ]),
      ),
      const SizedBox(height: 14),
      AppCard(
        child: Column(children: [
          row('Дней с записями', '${withFood.length} из ${days.length}'),
          row('Среднесуточная калорийность', '${fmt0(avg(withFood.map((s) => s.n.calories)))} ккал'),
          row('Среднее количество белка', '${fmt0(avg(withFood.map((s) => s.n.proteins)))} г'),
          row('Среднее количество шагов', fmt0(avg(stepsDays.map((s) => s.act.steps)))),
          row('Изменение веса',
              weights.length < 2 ? '—' : '${(weights.last.weight! - weights.first.weight!) >= 0 ? '+' : ''}${fmt1(weights.last.weight! - weights.first.weight!)} кг'),
          row('Дней с выполненной нормой',
              withFood.isEmpty ? '—' : '${(met * 100 / withFood.length).round()}% ($met)'),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Норма выполнена, если калории в пределах 90–110% цели дня.',
                style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      _Series('Калории по дням', 'ккал', kOrange, [for (final s in days) s.n.calories],
          [for (final s in days) '${parseDayKey(s.key).day}'], goal: days.last.goal.calories),
      DayDetail(dayKeyStr: dayKey(sel)),
    ]);
  }
}
