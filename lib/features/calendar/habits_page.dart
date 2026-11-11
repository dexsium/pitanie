import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import 'habits.dart';

/// Календарь привычек и достижения. Цветные точки показывают, что было в день: питание,
/// вода в норме, тренировка, взвешивание. Пропуски ничего не отнимают.
class HabitsPage extends ConsumerStatefulWidget {
  const HabitsPage({super.key});

  @override
  ConsumerState<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends ConsumerState<HabitsPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<HabitSummary> _future = loadHabits(ref.read(dbProvider));

  static const _legend = [
    (kGreen, 'Питание'),
    (kBlue, 'Вода в норме'),
    (kOrange, 'Тренировка'),
    (kViolet, 'Взвешивание'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь привычек')),
      body: FutureBuilder<HabitSummary>(
        future: _future,
        builder: (context, snap) {
          final s = snap.data;
          if (s == null) return const Center(child: CircularProgressIndicator());
          final first = DateTime(_month.year, _month.month, 1);
          final days = DateTime(_month.year, _month.month + 1, 0).day;
          final lead = first.weekday - 1;
          final todayK = dayKey(DateTime.now());
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              IconButton(
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                  child: Text(DateFormat('LLLL yyyy', 'ru').format(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              IconButton(
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                  icon: const Icon(Icons.chevron_right)),
            ]),
            AppCard(
              child: Column(children: [
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.9,
                  children: [
                    for (final w in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                      Center(child: Text(w, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                    for (var i = 0; i < lead; i++) const SizedBox(),
                    for (var d = 1; d <= days; d++)
                      _cell(DateTime(_month.year, _month.month, d), s.days, todayK, cs),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  for (final l in _legend)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: l.$1, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(l.$2, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Wrap(spacing: 18, runSpacing: 8, children: [
                _stat('Дней с питанием', s.foodDays),
                _stat('Лучшая серия', s.bestFoodRun),
                _stat('Вода в норме', s.waterDays),
                _stat('Тренировок', s.workoutDays),
                _stat('Взвешиваний', s.weighDays),
              ]),
            ),
            const SizedBox(height: 12),
            const Text('Достижения', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final a in s.achievements)
              AppCard(
                child: Row(children: [
                  Icon(a.done ? Icons.emoji_events : Icons.emoji_events_outlined,
                      color: a.done ? kOrange : cs.onSurfaceVariant, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(a.description, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                            value: a.progress,
                            minHeight: 6,
                            color: a.done ? kGreen : kPrimary,
                            backgroundColor: cs.onSurface.withOpacity(0.08)),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text('${a.current > a.target ? a.target : a.current}/${a.target}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
          ]);
        },
      ),
    );
  }

  Widget _stat(String l, int v) => SizedBox(
        width: 110,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(fontSize: 12)),
        ]),
      );

  Widget _cell(DateTime d, Map<String, HabitDay> days, String todayK, ColorScheme cs) {
    final k = dayKey(d);
    final h = days[k];
    final isToday = k == todayK;
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isToday ? kPrimary : Colors.transparent, width: 1.5),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${d.day}',
            style: TextStyle(fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
        const SizedBox(height: 3),
        SizedBox(
          height: 6,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (h?.food ?? false) _dot(kGreen),
            if (h?.water ?? false) _dot(kBlue),
            if (h?.workout ?? false) _dot(kOrange),
            if (h?.weighed ?? false) _dot(kViolet),
          ]),
        ),
      ]),
    );
  }

  Widget _dot(Color c) => Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}
