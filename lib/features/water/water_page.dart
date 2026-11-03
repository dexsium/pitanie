import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

class WaterPage extends ConsumerStatefulWidget {
  const WaterPage({super.key});
  @override
  ConsumerState<WaterPage> createState() => _WaterPageState();
}

class _WaterPageState extends ConsumerState<WaterPage> {
  String _type = 'water';

  @override
  Widget build(BuildContext context) {
    final db = ref.read(dbProvider);
    final day = ref.watch(selectedDayProvider);
    final key = dayKey(day);
    final data = ref.watch(dayDataProvider(key)).valueOrNull;
    final to = dayKey(day);
    final from = dayKey(day.subtract(const Duration(days: 6)));
    final week = ref.watch(rangeStatsProvider((from: from, to: to))).valueOrNull;

    Future<void> add(double ml) async {
      if (!await guardPast(context, key)) return;
      await db.addWater(key, ml, type: _type);
    }

    final goal = data?.goal.waterMl ?? GoalValues.fallback.waterMl;
    final ml = data?.plainWaterMl ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Вода'), actions: [
        IconButton(
          tooltip: 'Дневная норма',
          icon: const Icon(Icons.flag_outlined),
          onPressed: () async {
            final v = await promptNumber(context, 'Норма воды', initial: goal, suffix: 'мл', allowZero: false, max: 10000);
            if (v == null || data == null) return;
            final g = data.goal;
            await db.setGoal(dayKey(DateTime.now()), GoalValues(g.calories, g.proteins, g.fats, g.carbs, v));
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        const DayBar(),
        const SizedBox(height: 16),
        AppCard(
          child: Column(children: [
            CalorieRing(
              progress: goal > 0 ? ml / goal : 0,
              size: 160,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fmt0(ml), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                Text('из ${fmt0(goal)} мл'),
              ]),
            ),
            if ((data?.otherDrinksMl ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Другие напитки: ${fmt0(data!.otherDrinksMl)} мл (не входят в норму воды)'),
              ),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _type,
              isExpanded: true,
              items: [for (final e in beverageTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in [100, 200, 250, 500])
                ActionChip(label: Text('+$v мл'), onPressed: () => add(v.toDouble())),
              ActionChip(
                avatar: const Icon(Icons.edit, size: 18),
                label: const Text('Другое'),
                onPressed: () async {
                  final v = await promptNumber(context, 'Объём', suffix: 'мл', allowZero: false, max: 5000);
                  if (v != null) await add(v);
                },
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Калорийные напитки (сок, молоко) добавляйте через «Питание» с галочкой «Учесть объём в напитках» — калории не задвоятся.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Последние 7 дней', icon: Icons.bar_chart, color: kBlue),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
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
                            getTitlesWidget: (v, _) {
                              final d = day.subtract(Duration(days: 6 - v.toInt()));
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('${d.day}', style: const TextStyle(fontSize: 11)),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < 7; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                                toY: week[dayKey(day.subtract(Duration(days: 6 - i)))]?.waterMl ?? 0,
                                color: kBlue,
                                width: 18,
                                borderRadius: BorderRadius.circular(6)),
                          ]),
                      ],
                    )),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionTitle('История за день', icon: Icons.history),
        if (data == null || data.water.isEmpty)
          const EmptyHint('Записей нет'),
        if (data != null)
          for (final w in data.water) _WaterTile(w, key),
      ]),
    );
  }
}

class _WaterTile extends ConsumerWidget {
  final WaterEntry w;
  final String dayKeyStr;
  const _WaterTile(this.w, this.dayKeyStr);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final linked = w.foodEntryId != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.water_drop, color: kBlue),
      title: Text('${fmt0(w.volumeMl)} мл · ${beverageTypes[w.beverageType] ?? w.beverageType}'),
      subtitle: Text(fmtTime(w.loggedAt) + (linked ? ' · из дневника питания' : '')),
      trailing: linked
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  if (!await guardPast(context, dayKeyStr)) return;
                  final v = await promptNumber(context, 'Объём', initial: w.volumeMl, suffix: 'мл', allowZero: false, max: 5000);
                  if (v != null) await db.updateWater(w.id, v, w.beverageType);
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await guardPast(context, dayKeyStr)) return;
                  await db.deleteWater(w.id);
                },
              ),
            ]),
    );
  }
}
