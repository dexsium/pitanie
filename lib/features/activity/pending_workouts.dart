import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/labels.dart';
import '../wearables/workout_service.dart';

const _types = [
  'STRENGTH_TRAINING',
  'RUNNING',
  'WALKING',
  'BIKING',
  'HIGH_INTENSITY_INTERVAL_TRAINING',
  'YOGA',
  'OTHER',
];

/// Тренировки, найденные по пульсу: ждут подтверждения пользователя.
class PendingWorkouts extends ConsumerWidget {
  const PendingWorkouts({super.key});

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? const {};
    final list = pendingWorkouts(settings);
    if (list.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final db = ref.read(dbProvider);
    return Column(children: [
      for (final w in list)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Похоже на тренировку',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  '${_hm(w.start)}–${_hm(w.end)} (${w.minutes} мин), '
                  'средний пульс ${w.avgHr.round()}, максимум ${w.maxHr.round()}. '
                  'Найдено по пульсу, тип неизвестен. Выберите, чем вы занимались.',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final t in _types)
                  ActionChip(
                    label: Text(t == 'OTHER' ? 'Другое' : workoutLabel(t)),
                    onPressed: () => confirmWorkout(db, w, t),
                  ),
              ]),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => dismissWorkout(db, w),
                    child: const Text('Это не тренировка')),
              ),
            ]),
          ),
        ),
    ]);
  }
}
