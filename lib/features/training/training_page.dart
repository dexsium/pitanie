import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../shared/widgets.dart';
import 'strength_progress_page.dart';
import 'training_repo.dart';
import 'workout_editor_page.dart';

/// Дневник силовых тренировок: история, шаблоны, переход к прогрессу.
class TrainingPage extends ConsumerStatefulWidget {
  const TrainingPage({super.key});
  @override
  ConsumerState<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends ConsumerState<TrainingPage> {
  int _rev = 0;

  Future<(List<SessionSummary>, List<dynamic>)> _load() async {
    final repo = TrainingRepo(ref.read(dbProvider));
    return (await repo.history(), await repo.templates());
  }

  Future<void> _open({int? id, List<int>? templateIds, String? title}) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => WorkoutEditorPage(
                sessionId: id, templateIds: templateIds, title: title)));
    if (mounted) setState(() => _rev++);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repo = TrainingRepo(ref.read(dbProvider));
    return Scaffold(
      appBar: AppBar(title: const Text('Тренировки')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Новая тренировка'),
      ),
      body: FutureBuilder(
        key: ValueKey(_rev),
        future: _load(),
        builder: (context, snap) {
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final hist = snap.data!.$1;
          final templates = snap.data!.$2.cast<dynamic>();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              AppCard(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StrengthProgressPage())),
                child: Row(children: [
                  const Icon(Icons.show_chart, color: kPrimary, size: 30),
                  const SizedBox(width: 14),
                  const Expanded(
                      child: Text('Прогресс силы',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800))),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ]),
              ),
              if (templates.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Шаблоны',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final t in templates)
                    InputChip(
                      label: Text(t.name as String),
                      onPressed: () => _open(
                          templateIds: TrainingRepo.templateIds(t),
                          title: t.name as String),
                      onDeleted: () async {
                        await repo.deleteTemplate(t.id as int);
                        if (mounted) setState(() => _rev++);
                      },
                    ),
                ]),
              ],
              const SizedBox(height: 16),
              const Text('История',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (hist.isEmpty)
                const EmptyHint(
                    'Тренировок пока нет. Нажмите «Новая тренировка».')
              else
                for (final h in hist)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      onTap: () => _open(id: h.session.id),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    h.session.title.isEmpty
                                        ? 'Тренировка'
                                        : h.session.title,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                    '${DateFormat('d MMM, HH:mm', 'ru').format(h.session.startedAt.toLocal())}'
                                    '${h.session.durationMin == null ? '' : ' · ${h.session.durationMin} мин'}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: cs.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text(
                                    '${h.exercises} упр., ${h.sets} подх., ${h.reps} повт.'
                                    '${h.volume > 0 ? ', объём ${fmt0(h.volume)} кг' : ''}',
                                    style: const TextStyle(fontSize: 14)),
                              ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                      title: const Text('Удалить тренировку?'),
                                      content: const Text(
                                          'Подходы этой тренировки тоже удалятся.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Отмена')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Удалить')),
                                      ],
                                    ));
                            if (ok == true) {
                              await repo.deleteSession(h.session.id);
                              if (mounted) setState(() => _rev++);
                            }
                          },
                        ),
                      ]),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
