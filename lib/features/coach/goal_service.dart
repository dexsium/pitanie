// Уведомления о выполненных целях и вечерняя подсказка «чем добрать норму».
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../activity/activity_page.dart' show defaultStepsGoal;
import '../dashboard/day_data.dart';
import '../settings/notification_service.dart';
import 'goal_coach.dart';

const _kDoneKey = 'goal_done';
const _kWeightDoneKey = 'goal_weight_done';
const _kCoachSchedKey = 'coach_sched';
const _kCoachId = 7;

final _alcohol =
    RegExp(r'пиво|вино|водк|виски|коньяк|ликёр|ликер|шампан|алког|ром\b');

/// Продукты пользователя, которыми он реально пользуется (часто или в избранном).
Future<List<FoodCandidate>> loadCandidates(AppDatabase db) async {
  final rows = await (db.select(db.products)
        ..where((t) =>
            t.kind.equals('food') &
            t.calories.isBiggerThanValue(0) &
            (t.useCount.isBiggerThanValue(0) | t.isFavorite.equals(true)))
        ..orderBy([(t) => OrderingTerm.desc(t.useCount)])
        ..limit(80))
      .get();
  return [
    for (final p in rows)
      if (!_alcohol.hasMatch(p.name.toLowerCase()))
        FoodCandidate(
            p.name, Nutrients(p.calories, p.proteins, p.fats, p.carbohydrates),
            liquid: p.measurementUnit == 'ml',
            pieceWeight: p.pieceWeight,
            portionSize: p.portionSize)
  ];
}

/// Подсказки для остатка: сначала из продуктов пользователя, если не нашлось — из запасного списка.
Future<List<FoodSuggestion>> suggestionsFor(
    AppDatabase db, Nutrients remaining, GoalValues goal) async {
  final own = suggestFoods(remaining, goal, await loadCandidates(db));
  if (own.isNotEmpty) return own;
  final std = suggestFoods(remaining, goal, builtinFoods);
  if (std.isNotEmpty) return std;
  // Калории закрыты, но не хватает белка: предлагаем самый белковый вариант.
  final pf = suggestProteinFirst(remaining, await loadCandidates(db));
  return pf.isNotEmpty ? pf : suggestProteinFirst(remaining, builtinFoods);
}

Set<String> _done(Map<String, String> settings, String today) {
  try {
    final j = jsonDecode(settings[_kDoneKey] ?? '{}') as Map;
    if (j['d'] != today) return {};
    return {for (final x in (j['k'] as List)) x as String};
  } catch (_) {
    return {};
  }
}

/// Проверяет цели сегодняшнего дня и уведомляет о каждой новой выполненной (один раз за день).
Future<int> checkGoals(AppDatabase db,
    Future<void> Function(int id, String title, String body) notify) async {
  final now = DateTime.now();
  final key = dayKey(now);
  final settings = await db.allSettings();
  final d = await loadDayData(db, key);
  final stepsGoal =
      double.tryParse(settings['steps_goal'] ?? '') ?? defaultStepsGoal;
  final events = achievedGoals(
      eaten: d.eaten,
      goal: d.goal,
      calorieTarget: d.calorieTarget,
      waterMl: d.plainWaterMl,
      steps: d.activity.steps,
      stepsGoal: stepsGoal);
  final done = _done(settings, key);
  var sent = 0;
  for (final e in events) {
    if (done.contains(e.id)) continue;
    done.add(e.id);
    await notify(e.notificationId, e.title, e.body);
    sent++;
  }
  if (sent > 0 || settings[_kDoneKey] == null) {
    await db.setSetting(_kDoneKey, jsonEncode({'d': key, 'k': done.toList()}));
  }
  return sent + await _checkWeightGoal(db, settings, notify);
}

/// Целевой вес достигнут: уведомление один раз для каждого значения цели.
Future<int> _checkWeightGoal(AppDatabase db, Map<String, String> settings,
    Future<void> Function(int id, String title, String body) notify) async {
  final user = await db.getUser();
  final target = user?.targetWeightKg;
  if (user == null || target == null) return 0;
  final type = user.goalType;
  if (type != 'lose' && type != 'gain') return 0;
  final weights = await db.allWeights();
  if (weights.isEmpty) return 0;
  final last =
      weights.reduce((a, b) => a.measuredAt.isAfter(b.measuredAt) ? a : b);
  final reached =
      type == 'lose' ? last.weightKg <= target : last.weightKg >= target;
  if (!reached || settings[_kWeightDoneKey] == '$target') return 0;
  await db.setSetting(_kWeightDoneKey, '$target');
  await notify(
      9106,
      'Целевой вес достигнут',
      'Сейчас ${last.weightKg.toStringAsFixed(1)} кг, цель '
          '${target.toStringAsFixed(1)} кг. Можно пересчитать нормы в профиле.');
  return 1;
}

({bool on, int h, int m}) _coachTime(Map<String, String> settings) {
  final parts =
      (settings[coachReminder.key] ?? '1|${coachReminder.defaultTime}')
          .split('|');
  final hm =
      (parts.length > 1 ? parts[1] : coachReminder.defaultTime).split(':');
  return (
    on: parts[0] == '1',
    h: int.tryParse(hm[0]) ?? 20,
    m: hm.length > 1 ? int.tryParse(hm[1]) ?? 0 : 0
  );
}

/// Пересчитывает вечернюю подсказку по текущему дневнику: ставит уведомление на заданное время
/// с актуальным текстом или снимает его, если нормы уже закрыты. Вызывается при любом изменении дня.
Future<void> updateCoach(AppDatabase db, NotificationService n) async {
  final settings = await db.allSettings();
  final t = _coachTime(settings);
  if (!t.on) {
    await n.cancel(_kCoachId);
    return;
  }
  final now = DateTime.now();
  final key = dayKey(now);
  final d = await loadDayData(db, key);
  // Пустой дневник: подсказывать нечего, о нём напомнит «Дневник» в 21:30.
  if (d.food.isEmpty) {
    await n.cancel(_kCoachId);
    return;
  }
  final r = remainingTo(d.eaten, d.goal, d.calorieTarget);
  if (!hasGap(r)) {
    await n.cancel(_kCoachId);
    return;
  }
  final sug = await suggestionsFor(db, r, d.goal);
  final body = StringBuffer('До нормы не хватает: ${gapSummary(r)}.');
  if (sug.isNotEmpty) {
    body.write(' Можно съесть: ${suggestionText(sug)}.');
    final note = overflowNote(r, sug);
    if (note != null) body.write(' $note');
    if (sug.any((s) => s.food.approximate)) {
      body.write(' Значения продуктов примерные.');
    }
  }
  final at = DateTime(now.year, now.month, now.day, t.h, t.m);
  final sched = settings[_kCoachSchedKey] ?? '';
  final mark = '$key|${t.h}:${t.m}';
  // Запись в настройки вызывает пересчёт потоков БД, поэтому пишем только при изменении.
  Future<void> remember() async {
    if (sched != mark) await db.setSetting(_kCoachSchedKey, mark);
  }

  if (at.isAfter(now)) {
    await n.cancel(_kCoachId);
    await n.scheduleOnce(_kCoachId, 'Добор нормы', body.toString(), at);
    await remember();
    return;
  }
  // Время уже прошло. Если на сегодня подсказку уже ставили, она сработала сама.
  if (sched.startsWith('$key|')) return;
  // Позднее 23:00 не беспокоим.
  if (now.hour >= 23) return;
  await remember();
  await n.showGoal(_kCoachId, 'Добор нормы', body.toString());
}
