import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

/// Отдельные суточные нормы для тренировочных дней. Тренировочный день определяется по данным:
/// тренировка из Здоровья (часы) или запись в дневнике тренировок. Нормы действуют с сегодняшнего
/// дня, прошлые дни не пересчитываются.
class TrainingGoalsPage extends ConsumerStatefulWidget {
  const TrainingGoalsPage({super.key});

  @override
  ConsumerState<TrainingGoalsPage> createState() => _TrainingGoalsPageState();
}

class _TrainingGoalsPageState extends ConsumerState<TrainingGoalsPage> {
  final _form = GlobalKey<FormState>();
  final _k = TextEditingController(),
      _p = TextEditingController(),
      _f = TextEditingController(),
      _c = TextEditingController(),
      _w = TextEditingController();
  bool _on = false;
  bool _loaded = false;
  GoalValues _base = GoalValues.fallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final today = dayKey(DateTime.now());
    _base = await db.goalFor(today);
    TrainingGoal? cur;
    for (final g in await db.allTrainingGoals()) {
      if (g.effectiveDate.compareTo(today) <= 0) cur = g;
    }
    // Если нормы ещё не заданы, подставляем обычные плюс небольшой запас на тренировку.
    final g = cur == null
        ? GoalValues(_base.calories + 250, _base.proteins, _base.fats, _base.carbs + 60, _base.waterMl + 500)
        : GoalValues(cur.calories, cur.proteins, cur.fats, cur.carbohydrates, cur.waterMl);
    _on = cur?.enabled ?? false;
    _k.text = fmtInput(g.calories.roundToDouble());
    _p.text = fmtInput(g.proteins.roundToDouble());
    _f.text = fmtInput(g.fats.roundToDouble());
    _c.text = fmtInput(g.carbs.roundToDouble());
    _w.text = fmtInput(g.waterMl.roundToDouble());
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_k, _p, _f, _c, _w]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_on && !(_form.currentState?.validate() ?? false)) return;
    final g = GoalValues(parseNum(_k.text) ?? _base.calories, parseNum(_p.text) ?? _base.proteins,
        parseNum(_f.text) ?? _base.fats, parseNum(_c.text) ?? _base.carbs,
        parseNum(_w.text) ?? _base.waterMl);
    await ref.read(dbProvider).setTrainingGoal(dayKey(DateTime.now()), g, enabled: _on);
    ref.invalidate(dayDataProvider);
    if (mounted) {
      toast(context, _on ? 'Нормы тренировочных дней сохранены' : 'Отдельные нормы отключены');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Цели для тренировочных дней')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              AppCard(
                child: Text(
                    'В день с тренировкой (по данным часов из Здоровья или по дневнику тренировок) '
                    'действуют эти нормы, в остальные дни обычные. Новые нормы действуют с сегодняшнего '
                    'дня: прошлые дни не пересчитываются. Нормы дня и фактическое питание показываются '
                    'отдельно.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _on,
                onChanged: (v) => setState(() => _on = v),
                title: const Text('Отдельные нормы для тренировочных дней'),
              ),
              Text(
                  'Обычные нормы: ${fmt0(_base.calories)} ккал, Б ${fmt0(_base.proteins)}, '
                  'Ж ${fmt0(_base.fats)}, У ${fmt0(_base.carbs)} г, вода ${fmt0(_base.waterMl)} мл',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (_on)
                Form(
                  key: _form,
                  child: Column(children: [
                    NumField(controller: _k, label: 'Калории', suffix: 'ккал', min: 500, max: 10000, allowZero: false),
                    const SizedBox(height: 10),
                    NumField(controller: _p, label: 'Белки', suffix: 'г', max: 1000),
                    const SizedBox(height: 10),
                    NumField(controller: _f, label: 'Жиры', suffix: 'г', max: 1000),
                    const SizedBox(height: 10),
                    NumField(controller: _c, label: 'Углеводы', suffix: 'г', max: 2000),
                    const SizedBox(height: 10),
                    NumField(controller: _w, label: 'Вода', suffix: 'мл', min: 200, max: 10000, allowZero: false),
                  ]),
                ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: const Text('Сохранить')),
            ]),
    );
  }
}
