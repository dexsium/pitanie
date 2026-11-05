// Карточка «Чем добрать норму» на главном экране: показывается только для сегодняшнего дня,
// когда в дневнике уже есть записи и до нормы ещё что-то не хватает.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../dashboard/day_data.dart';
import 'goal_coach.dart';
import 'goal_service.dart';

class CoachCard extends ConsumerStatefulWidget {
  final DayData d;
  const CoachCard(this.d, {super.key});

  @override
  ConsumerState<CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends ConsumerState<CoachCard> {
  String _sig = '';
  Future<List<FoodSuggestion>>? _future;

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    if (d.key != dayKey(DateTime.now()) || d.food.isEmpty) {
      return const SizedBox.shrink();
    }
    final r = remainingTo(d.eaten, d.goal, d.calorieTarget);
    if (!hasGap(r)) return const SizedBox.shrink();
    final sig = '${r.calories.round()}|${r.proteins.round()}|${r.fats.round()}|'
        '${r.carbs.round()}';
    if (sig != _sig) {
      _sig = sig;
      _future = suggestionsFor(ref.read(dbProvider), r, d.goal);
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(0.45),
            borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lightbulb_outline, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Чем добрать норму',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          Text('Не хватает: ${gapSummary(r)}.'),
          FutureBuilder<List<FoodSuggestion>>(
            future: _future,
            builder: (context, snap) {
              final s = snap.data ?? const <FoodSuggestion>[];
              if (s.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final x in s)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('• ${x.label}'),
                        ),
                      const SizedBox(height: 6),
                      Text(
                          s.any((x) => x.food.approximate)
                              ? 'Подбор примерный: часть значений взята из общего справочника, '
                                  'а не из ваших продуктов.'
                              : 'Подбор из ваших продуктов, порции примерные.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
              );
            },
          ),
        ]),
      ),
    );
  }
}
