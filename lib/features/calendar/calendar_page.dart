import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../shared/widgets.dart';
import '../dashboard/day_data.dart';

class MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, DayStat>? stats;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const MonthGrid(
      {super.key, required this.month, required this.stats, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final cs = Theme.of(context).colorScheme;
    final cells = <Widget>[
      for (final w in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
        Center(child: Text(w, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
      for (var i = 0; i < lead; i++) const SizedBox(),
      for (var d = 1; d <= days; d++) _cell(context, DateTime(month.year, month.month, d)),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.0,
      children: cells,
    );
  }

  Widget _cell(BuildContext context, DateTime d) {
    final s = stats?[dayKey(d)];
    final sel = isSameDay(d, selected);
    final today = isSameDay(d, DateTime.now());
    final Color? bg = s == null
        ? null
        : s.met
            ? kGreen.withOpacity(0.28)
            : s.hasFood
                ? kOrange.withOpacity(0.25)
                : null;
    return GestureDetector(
      onTap: () => onSelect(d),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? kPrimary : (today ? kPrimary.withOpacity(0.4) : Colors.transparent),
              width: sel ? 2.5 : 1.5),
        ),
        child: Center(
          child: Text('${d.day}',
              style: TextStyle(fontWeight: sel || today ? FontWeight.w800 : FontWeight.w500)),
        ),
      ),
    );
  }
}

class DayDetail extends ConsumerWidget {
  final String dayKeyStr;
  final VoidCallback? onOpen;
  const DayDetail({super.key, required this.dayKeyStr, this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(dayDataProvider(dayKeyStr)).valueOrNull;
    if (d == null) return const SizedBox();
    final n = d.eaten;
    final a = d.activity;
    Widget row(String l, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [Expanded(child: Text(l)), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(fullDate(parseDayKey(dayKeyStr)), icon: Icons.event_note),
        const SizedBox(height: 8),
        row('Калории', '${fmt0(n.calories)} / ${fmt0(d.calorieTarget)} ккал'),
        row('Белки', '${fmt0(n.proteins)} / ${fmt0(d.goal.proteins)} г'),
        row('Жиры', '${fmt0(n.fats)} / ${fmt0(d.goal.fats)} г'),
        row('Углеводы', '${fmt0(n.carbs)} / ${fmt0(d.goal.carbs)} г'),
        const Divider(),
        for (final m in Meal.values)
          row(m.label, '${fmt0(d.mealTotal(m.name).calories)} ккал'),
        const Divider(),
        row('Вода', '${fmt0(d.plainWaterMl)} / ${fmt0(d.goal.waterMl)} мл'),
        row('Шаги', fmt0(a.steps)),
        row('Активные калории', '${fmt0(a.activeKcal)} ккал'),
        row('Тренировки', a.workouts.isEmpty ? 'нет' : '${a.workouts.length} (${fmt0(a.workoutMinutes)} мин)'),
        if (d.weight != null) row('Вес', '${fmt1(d.weight!)} кг'),
        if (onOpen != null) ...[
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onOpen, child: const Text('Открыть день в дневнике')),
        ],
      ]),
    );
  }
}

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});
  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final d = ref.read(selectedDayProvider);
    _month = DateTime(d.year, d.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedDayProvider);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final stats = ref
        .watch(rangeStatsProvider((from: dayKey(_month), to: dayKey(last))))
        .valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь питания')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(children: [
            Row(children: [
              IconButton(
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Center(
                  child: Text(
                      toBeginningOfSentenceCase(DateFormat('LLLL yyyy', 'ru').format(_month)) ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
              IconButton(
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
                  icon: const Icon(Icons.chevron_right)),
            ]),
            MonthGrid(
              month: _month,
              stats: stats,
              selected: sel,
              onSelect: (d) => ref.read(selectedDayProvider.notifier).state = d,
            ),
            const SizedBox(height: 6),
            const Wrap(spacing: 14, children: [
              _Legend(kGreen, 'норма выполнена'),
              _Legend(kOrange, 'есть записи'),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        DayDetail(
          dayKeyStr: dayKey(sel),
          onOpen: () {
            ref.read(tabProvider.notifier).state = 1;
            Navigator.popUntil(context, (r) => r.isFirst);
          },
        ),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color c;
  final String t;
  const _Legend(this.c, this.t);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 6, backgroundColor: c.withOpacity(0.5)),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}
