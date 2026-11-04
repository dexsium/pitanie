import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../core/nutrition/nutrition_calculation_models.dart';
import '../../services/health/plan_service.dart';

String _n(double v) => v.round().toString();
String _d(double v, [int f = 1]) => v.toStringAsFixed(f).replaceAll('.', ',');

/// Подробное объяснение: формула, входные данные, PAL, дефицит/профицит, источники,
/// достоверность и причина последней корректировки.
List<(String, String)> planExplanation(PlanSnapshot p) {
  final r = p.result;
  final u = p.user;
  final out = <(String, String)>[];
  if (u == null || r == null) {
    out.add((
      'Нормы пока не рассчитаны',
      p.minor
          ? 'Взрослая формула (Миффлина — Сан Жеора) не применяется для пользователей младше 18 лет. '
              'Задайте нормы вручную.'
          : 'Заполните анкету: пол, дату рождения, рост и вес.'
    ));
    return out;
  }
  final lvl = ActivityLevel.values.firstWhere((l) => l.name == u.activityLevel,
      orElse: () => ActivityLevel.light);
  final goal = GoalType.values
      .firstWhere((g) => g.name == u.goalType, orElse: () => GoalType.maintain);
  final male = u.sex != 'female';
  out.add((
    'Базовый обмен (BMR)',
    'Формула Миффлина — Сан Жеора: ${male ? '10 × масса + 6,25 × рост − 5 × возраст + 5' : '10 × масса + 6,25 × рост − 5 × возраст − 161'}.\n'
        'Данные: ${_d(p.weightKg!)} кг, ${_n(u.heightCm!)} см, ${p.age} лет → ${_n(r.bmr)} ккал.'
  ));
  out.add((
    'Суточный расход (TDEE)',
    'TDEE = BMR × коэффициент активности. Уровень «${levelLabel(lvl)}» → ${_d(r.pal, 3)}. '
        'Получается ${_n(r.tdee)} ккал. Коэффициент ориентировочный, а не измеренный. '
        'Тренировки уже входят в него и повторно не добавляются.'
  ));
  final pct = r.goalFraction * 100;
  out.add((
    'Цель: ${goalLabel(goal)}',
    switch (goal) {
          GoalType.maintain => 'Калорийность равна TDEE.',
          GoalType.gain =>
            'Профицит ${_d(pct, 0)} % от TDEE (допустимо 5–15 %). '
                'Не весь набранный вес будет мышечной массой.',
          GoalType.lose =>
            'Дефицит ${_d(-pct, 0)} % от TDEE (допустимо 10–20 %).',
        } +
        (r.adaptationOffsetKcal == 0
            ? ''
            : '\nПоправка адаптации: ${r.adaptationOffsetKcal > 0 ? '+' : ''}${_n(r.adaptationOffsetKcal)} ккал.') +
        '\nИтоговая цель по формуле: ${_n(r.targetCalories)} ккал.'
  ));
  final m = r.macros;
  out.add((
    'БЖУ и вода',
    'Белки ${_d(m.proteins / p.weightKg!)} г/кг → ${_n(m.proteins)} г; жиры ${_d(m.fats / p.weightKg!)} г/кг → ${_n(m.fats)} г; '
        'углеводы — остаток: ${_n(m.carbs)} г. Проверка 4/9/4: ${_n(m.kcalFromMacros)} ккал'
        '${m.mismatch.abs() >= 1 ? ' (расхождение ${_n(m.mismatch)} ккал)' : ''}.\n'
        'Вода ≈ 33 мл на кг: ${_n(r.waterMl)} мл — ориентир, не медицинская норма.'
  ));
  final g = p.currentGoal;
  out.add((
    'Действующие нормы',
    '${_n(g.calories)} ккал, Б ${_n(g.proteins)}, Ж ${_n(g.fats)}, У ${_n(g.carbs)} г, вода ${_n(g.waterMl)} мл. '
        'Режим: ${switch (p.mode) {
      CalcMode.adaptive => 'автоматический адаптивный',
      CalcMode.standard => 'по стандартным формулам',
      CalcMode.manual => 'ручная настройка (автоматика нормы не меняет)',
    }}.'
  ));
  final src = StringBuffer(
      'Вес: ${p.weightSource.isEmpty ? '—' : p.weightSource}'
      '${p.weightAgeDays == null ? '' : p.weightAgeDays == 0 ? ', сегодня' : ', ${p.weightAgeDays} дн. назад'}. '
      'Рост, возраст, пол и уровень активности — из анкеты. Калории часов в расчёт норм не входят.');
  if ((p.weightAgeDays ?? 0) > 30) {
    src.write(' Вес давно не обновлялся: обновите его.');
  }
  out.add(('Источники данных', src.toString()));
  final e = p.energy;
  out.add((
    'Достоверность: ${confidenceLabel(p.confidence)}',
    e.tdee != null
        ? 'По динамике массы и дневнику питания оценка фактического расхода ≈ ${_n(e.tdee!)} ккал '
            '(использован приближённый эквивалент 7700 ккал/кг, это не точная величина).'
        : 'Индивидуальный расход не определён: ${e.reason ?? 'недостаточно данных'} '
            'Показана расчётная норма, а не измеренный расход.'
  ));
  if (p.mode == CalcMode.adaptive) {
    final last =
        p.history.where((h) => h.kind == 'adapt' || h.kind == 'auto').toList();
    out.add((
      'Последняя корректировка',
      last.isEmpty
          ? 'Корректировок не было. ${p.adaptation.message}'
          : '${DateFormat('d.MM.yyyy', 'ru').format(last.last.at)}: ${last.last.text}'
    ));
  }
  if (r.warnings.isNotEmpty) out.add(('Предупреждения', r.warnings.join('\n')));
  out.add((
    'Важно',
    'Это ориентировочные расчёты, а не медицинская рекомендация. '
        'При заболеваниях и особых режимах питания обратитесь к врачу.'
  ));
  return out;
}

Future<void> showPlanExplanation(BuildContext context, PlanSnapshot? p) =>
    showDialog(
      context: context,
      builder: (ctx) {
        final items = p == null
            ? const <(String, String)>[
                ('Данные загружаются', 'Повторите через секунду.')
              ]
            : planExplanation(p);
        return AlertDialog(
          title: const Text('Как считаются нормы'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (t, b) in items) ...[
                      Text(t,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(b),
                      const SizedBox(height: 12),
                    ],
                  ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Понятно'))
          ],
        );
      },
    );
