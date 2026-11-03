import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

/// Анкета: первый запуск ([editing] = false) или редактирование профиля.
class OnboardingPage extends ConsumerStatefulWidget {
  final bool editing;
  const OnboardingPage({super.key, this.editing = false});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingPage> {
  final _form = GlobalKey<FormState>();
  Sex _sex = Sex.male;
  DateTime? _birth;
  ActivityLevel _level = ActivityLevel.light;
  GoalType _goal = GoalType.maintain;
  final height = TextEditingController();
  final weight = TextEditingController();
  final target = TextEditingController();
  final kcal = TextEditingController();
  final prot = TextEditingController();
  final fat = TextEditingController();
  final carb = TextEditingController();
  final water = TextEditingController();
  bool _goalsTouched = false;
  double? _lastWeight;

  @override
  void initState() {
    super.initState();
    if (widget.editing) _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final u = await db.getUser();
    final ws = await db.allWeights();
    if (u == null || !mounted) return;
    setState(() {
      _sex = Sex.values.firstWhere((s) => s.name == u.sex, orElse: () => Sex.male);
      _birth = u.birthDate;
      _level = ActivityLevel.values.firstWhere((s) => s.name == u.activityLevel, orElse: () => ActivityLevel.light);
      _goal = GoalType.values.firstWhere((s) => s.name == u.goalType, orElse: () => GoalType.maintain);
      height.text = u.heightCm == null ? '' : fmtAuto(u.heightCm!);
      target.text = u.targetWeightKg == null ? '' : fmtAuto(u.targetWeightKg!);
      if (ws.isNotEmpty) {
        _lastWeight = ws.last.weightKg;
        weight.text = fmtInput(ws.last.weightKg);
      }
    });
  }

  GoalValues? _suggest() {
    final h = parseNum(height.text), w = parseNum(weight.text);
    if (h == null || w == null || _birth == null) return null;
    final bmr = bmrMifflin(sex: _sex, weightKg: w, heightCm: h, age: ageOn(_birth!, DateTime.now()));
    return suggestGoals(bmr: bmr, level: _level, goal: _goal, weightKg: w);
  }

  void _fillGoals() {
    final g = _suggest();
    if (g == null) return;
    kcal.text = fmtInput(g.calories);
    prot.text = fmtInput(g.proteins);
    fat.text = fmtInput(g.fats);
    carb.text = fmtInput(g.carbs);
    water.text = fmtInput(g.waterMl);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_birth == null) {
      toast(context, 'Укажите дату рождения');
      return;
    }
    final db = ref.read(dbProvider);
    final w = parseNum(weight.text)!;
    if (_lastWeight == null || (_lastWeight! - w).abs() > 0.001) {
      await db.addWeight(DateTime.now(), w);
    }
    if (!widget.editing) {
      await db.setGoal(
          '1970-01-01',
          GoalValues(parseNum(kcal.text)!, parseNum(prot.text)!, parseNum(fat.text)!,
              parseNum(carb.text)!, parseNum(water.text)!));
    }
    // Пользователь сохраняется последним: появление записи переключает экран.
    await db.saveUser(UsersCompanion(
      sex: Value(_sex.name),
      birthDate: Value(_birth),
      heightCm: Value(parseNum(height.text)),
      targetWeightKg: Value(parseNum(target.text)),
      goalType: Value(_goal.name),
      activityLevel: Value(_level.name),
    ));
    if (widget.editing && mounted) {
      Navigator.pop(context);
      toast(context, 'Профиль сохранён. Нормы не менялись: при необходимости пересчитайте их в профиле.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing ? 'Анкета' : 'Давайте познакомимся')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!widget.editing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Анкета нужна для расчёта ориентировочных норм. Все данные хранятся только на устройстве.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          SegmentedButton<Sex>(
            segments: [for (final s in Sex.values) ButtonSegment(value: s, label: Text(sexLabel(s)))],
            selected: {_sex},
            onSelectionChanged: (s) => setState(() => _sex = s.first),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: Text(_birth == null ? 'Дата рождения' : fullDate(_birth!)),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _birth ?? DateTime(1995),
                  firstDate: DateTime(1920),
                  lastDate: DateTime.now().subtract(const Duration(days: 365 * 10)));
              if (d != null) setState(() => _birth = d);
            },
          ),
          const SizedBox(height: 12),
          NumField(controller: height, label: 'Рост', suffix: 'см', min: 80, max: 250, allowZero: false),
          const SizedBox(height: 12),
          NumField(controller: weight, label: 'Вес', suffix: 'кг', min: 20, max: 400, allowZero: false),
          const SizedBox(height: 12),
          NumField(controller: target, label: 'Целевой вес', suffix: 'кг', min: 20, max: 400, allowZero: false),
          const SizedBox(height: 12),
          DropdownButtonFormField<ActivityLevel>(
            value: _level,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Уровень активности'),
            items: [for (final l in ActivityLevel.values) DropdownMenuItem(value: l, child: Text(levelLabel(l)))],
            onChanged: (v) => setState(() => _level = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GoalType>(
            value: _goal,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Цель питания'),
            items: [for (final g in GoalType.values) DropdownMenuItem(value: g, child: Text(goalLabel(g)))],
            onChanged: (v) => setState(() => _goal = v!),
          ),
          if (!widget.editing) ...[
            const SizedBox(height: 20),
            const SectionTitle('Суточные нормы'),
            const SizedBox(height: 4),
            Text('Расчёт по формуле Миффлина — Сан Жеора ориентировочный. Вы можете изменить любое значение.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Рассчитать нормы'),
              onPressed: () {
                if (_suggest() == null) {
                  toast(context, 'Заполните дату рождения, рост и вес');
                  return;
                }
                setState(() {
                  _fillGoals();
                  _goalsTouched = true;
                });
              },
            ),
            const SizedBox(height: 12),
            NumField(controller: kcal, label: 'Калории', suffix: 'ккал', min: 500, max: 10000, allowZero: false),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: NumField(controller: prot, label: 'Белки', suffix: 'г', max: 1000)),
              const SizedBox(width: 8),
              Expanded(child: NumField(controller: fat, label: 'Жиры', suffix: 'г', max: 1000)),
              const SizedBox(width: 8),
              Expanded(child: NumField(controller: carb, label: 'Углеводы', suffix: 'г', max: 2000)),
            ]),
            const SizedBox(height: 10),
            NumField(controller: water, label: 'Вода', suffix: 'мл', min: 200, max: 10000, allowZero: false),
          ],
          const SizedBox(height: 20),
          FilledButton(
              onPressed: () {
                if (!widget.editing && !_goalsTouched && kcal.text.isEmpty) _fillGoals();
                _save();
              },
              child: Text(widget.editing ? 'Сохранить' : 'Начать')),
        ]),
      ),
    );
  }
}
