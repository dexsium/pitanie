import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../wearables/wearable_page.dart';
import '../wearables/wearable_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../shared/widgets.dart';
import '../calendar/calendar_page.dart';
import '../settings/settings_page.dart';
import '../water/water_page.dart';
import '../weight/weight_page.dart';
import 'day_data.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final key = dayKey(day);
    final data = ref.watch(dayDataProvider(key));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DayBar(
          onCalendar: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const CalendarPage())),
          trailing: IconButton.filledTonal(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              icon: const Icon(Icons.settings_outlined)),
        ),
        const SizedBox(height: 10),
        const WatchStatusChip(),
        const SizedBox(height: 10),
        data.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => EmptyHint('Ошибка: $e'),
          data: (d) => _Body(d),
        ),
      ],
    );
  }
}

/// Индикатор связи с часами: подключены / подключаются / не подключены.
class WatchStatusChip extends ConsumerWidget {
  const WatchStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(wearableProvider);
    if (c.savedId == null && !c.isConnected && c.status != WearStatus.connecting) {
      return const SizedBox.shrink();
    }
    final (text, color) = switch (c.status) {
      WearStatus.ready => (
        'Часы подключены${c.hr == null ? '' : ' · ♥ ${c.hr}'}${c.battery == null ? '' : ' · ${c.battery}%'}',
        kGreen
      ),
      WearStatus.connected || WearStatus.authorizing => ('Часы подключены, авторизация…', kOrange),
      WearStatus.connecting => ('Подключаем часы…', kOrange),
      WearStatus.off => ('Часы не подключены', Colors.grey),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: c.status == WearStatus.connecting
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.watch_outlined, size: 18, color: color),
        label: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const WearablePage())),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final DayData d;
  const _Body(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eaten = d.eaten;
    final target = d.calorieTarget;
    final left = target - eaten.calories;
    final pct = target > 0 ? eaten.calories / target : 0.0;
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      AppCard(
        child: Column(children: [
          Row(children: [
            CalorieRing(
              progress: pct,
              size: 140,
              center: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${(pct * 100).round()}%',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                Text(pct > 1 ? 'превышено' : 'выполнено',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.local_fire_department, color: kOrange),
                  SizedBox(width: 4),
                  Text('Калории', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: fmt0(eaten.calories),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                    TextSpan(
                        text: ' / ${fmt0(target)} ккал',
                        style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                  ])),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: (left >= 0 ? kGreen : kRed).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                      left >= 0
                          ? 'Осталось: ${fmt0(left)} ккал'
                          : 'Превышено: ${fmt0(-left)} ккал',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: left >= 0 ? const Color(0xFF2E9E3A) : kRed)),
                ),
                if (d.mode.name == 'dynamic')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Динамическая цель (база ${fmt0(d.goal.calories)})',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
              ]),
            ),
          ]),
          const Divider(height: 28),
          Row(children: [
            Expanded(
                child: MacroBar(
                    label: 'Белки',
                    icon: Icons.fitness_center,
                    value: eaten.proteins,
                    goal: d.goal.proteins,
                    color: kBlue)),
            const SizedBox(width: 12),
            Expanded(
                child: MacroBar(
                    label: 'Жиры',
                    icon: Icons.water_drop_outlined,
                    value: eaten.fats,
                    goal: d.goal.fats,
                    color: kOrange)),
            const SizedBox(width: 12),
            Expanded(
                child: MacroBar(
                    label: 'Углеводы',
                    icon: Icons.grain,
                    value: eaten.carbs,
                    goal: d.goal.carbs,
                    color: kViolet)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      AppCard(
        onTap: () => ref.read(tabProvider.notifier).state = 1,
        child: Column(children: [
          SectionTitle('Приёмы пищи',
              icon: Icons.restaurant,
              trailing: Row(children: [
                Text('${fmt0(eaten.calories)} ккал',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Icon(Icons.chevron_right),
              ])),
          const SizedBox(height: 8),
          for (final m in Meal.values) _MealRow(m, d),
        ]),
      ),
      const SizedBox(height: 14),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _WaterCard(d)),
          const SizedBox(width: 12),
          Expanded(child: _ActivityCard(d)),
        ]),
      ),
      const SizedBox(height: 14),
      const _WeightCard(),
    ]);
  }
}

class _MealRow extends StatelessWidget {
  final Meal m;
  final DayData d;
  const _MealRow(this.m, this.d);
  @override
  Widget build(BuildContext context) {
    final n = d.mealTotal(m.name);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: m.color.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
          child: Icon(m.icon, color: m.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text('Б: ${fmt0(n.proteins)} г   Ж: ${fmt0(n.fats)} г   У: ${fmt0(n.carbs)} г',
                style: TextStyle(
                    fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        Text('${fmt0(n.calories)} ккал',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _WaterCard extends ConsumerWidget {
  final DayData d;
  const _WaterCard(this.d);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final ml = d.plainWaterMl;
    final pct = d.goal.waterMl > 0 ? ml / d.goal.waterMl : 0.0;
    return AppCard(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const WaterPage())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Вода', icon: Icons.water_drop, color: kBlue),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: fmt0(ml),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            TextSpan(
                text: ' / ${fmt0(d.goal.waterMl)} мл',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 9,
              color: kBlue,
              backgroundColor: kBlue.withOpacity(0.18)),
        ),
        Align(
            alignment: Alignment.centerRight,
            child: Text('${(pct * 100).round()}%', style: const TextStyle(fontSize: 12))),
        const Spacer(),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in [100, 200, 250, 500])
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                if (!await guardPast(context, d.key)) return;
                await db.addWater(d.key, v.toDouble());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: kBlue.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Text('+$v',
                    style: const TextStyle(color: kBlue, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _ActivityCard extends ConsumerWidget {
  final DayData d;
  const _ActivityCard(this.d);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = d.activity;
    final src = ref.watch(sourceProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    Widget row(IconData i, Color c, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(i, color: c, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return AppCard(
      onTap: () => ref.read(tabProvider.notifier).state = 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Активность', icon: Icons.directions_run, color: kPrimary),
        const SizedBox(height: 8),
        if (!a.hasData)
          Text(src == null ? 'Часы не подключены' : 'Нет данных за день',
              style: TextStyle(color: cs.onSurfaceVariant))
        else ...[
          row(Icons.directions_walk, Colors.grey, '${fmt0(a.steps)} шагов'),
          row(Icons.place, kGreen, '${fmt1(a.distanceKm)} км'),
          row(Icons.local_fire_department, kOrange, '${fmt0(a.activeKcal)} ккал'),
          row(Icons.schedule, kBlue, '${fmt0(a.workoutMinutes)} мин'),
        ],
        const Spacer(),
        Text(
          src?.lastSync == null
              ? 'Синхронизации не было'
              : 'Синхронизировано в ${fmtTime(src!.lastSync!)}',
          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _WeightCard extends ConsumerWidget {
  const _WeightCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final user = ref.watch(userProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    final cur = ws.isEmpty ? null : ws.last.weightKg;
    final delta = ws.length < 2 ? null : ws.last.weightKg - ws.first.weightKg;
    final recent = ws.length > 12 ? ws.sublist(ws.length - 12) : ws;
    return AppCard(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const WeightPage())),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Вес', icon: Icons.monitor_weight_outlined),
            const SizedBox(height: 8),
            Text(cur == null ? '— кг' : '${fmt1(cur)} кг',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (delta != null)
              Text('${delta >= 0 ? '+' : ''}${fmt1(delta)} кг с начала',
                  style: TextStyle(
                      color: delta >= 0 ? const Color(0xFF2E9E3A) : kBlue,
                      fontWeight: FontWeight.w600)),
            if (user?.targetWeightKg != null)
              Text('Цель: ${fmt1(user!.targetWeightKg!)} кг',
                  style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
        ),
        Expanded(
          flex: 5,
          child: SizedBox(
            height: 80,
            child: recent.length < 2
                ? Center(
                    child: Text('Добавьте замеры',
                        style: TextStyle(color: cs.onSurfaceVariant)))
                : LineChart(LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < recent.length; i++)
                            FlSpot(i.toDouble(), recent[i].weightKg)
                        ],
                        isCurved: true,
                        color: kPrimary,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                            show: true, color: kPrimary.withOpacity(0.12)),
                      ),
                    ],
                  )),
          ),
        ),
      ]),
    );
  }
}
