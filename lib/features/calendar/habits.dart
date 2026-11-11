// Календарь привычек и достижения. Всё считается из данных приложения; пропущенные дни ничего
// не отнимают: достижения только накапливаются, штрафов и «сгоревших серий» нет.
import '../../core/dates.dart';
import '../../database/database.dart';

class HabitDay {
  final String key;
  final bool food;
  final bool water;
  final bool workout;
  final bool weighed;
  final bool goalMet;
  const HabitDay(this.key, this.food, this.water, this.workout, this.weighed, this.goalMet);
  bool get any => food || water || workout || weighed;
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final int current;
  final int target;
  const Achievement(this.id, this.title, this.description, this.current, this.target);
  bool get done => current >= target;
  double get progress => target <= 0 ? 1 : (current / target).clamp(0.0, 1.0);
}

class HabitSummary {
  final Map<String, HabitDay> days;
  final List<Achievement> achievements;
  final int foodDays, waterDays, workoutDays, weighDays, goalDays, bestFoodRun;
  const HabitSummary(this.days, this.achievements, this.foodDays, this.waterDays,
      this.workoutDays, this.weighDays, this.goalDays, this.bestFoodRun);
}

/// Самая длинная серия подряд идущих дней из [keys] (ключи вида yyyy-MM-dd).
int longestRun(Iterable<String> keys) {
  final days = keys.map(parseDayKey).toSet().toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in days) {
    run = prev != null && d.difference(prev).inHours <= 36 ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

List<Achievement> buildAchievements(
    {required int foodDays,
    required int bestRun,
    required int waterDays,
    required int workoutDays,
    required int weighDays,
    required int goalDays}) {
  return [
    Achievement('first_food', 'Первая запись', 'Запишите первый день питания', foodDays, 1),
    Achievement('run7', 'Неделя подряд', '7 дней записей питания подряд (лучшая серия)', bestRun, 7),
    Achievement('food30', '30 дней дневника', 'Всего 30 дней с записями питания', foodDays, 30),
    Achievement('water7', 'Водный режим', 'Норма воды выполнена 7 дней', waterDays, 7),
    Achievement('goal7', 'В норме', 'Калории в пределах нормы 7 дней', goalDays, 7),
    Achievement('train1', 'Первая тренировка', 'Одна тренировка в дневнике или с часов', workoutDays, 1),
    Achievement('train10', '10 тренировочных дней', 'Всего 10 дней с тренировкой', workoutDays, 10),
    Achievement('weigh1', 'Первое взвешивание', 'Одно взвешивание', weighDays, 1),
    Achievement('weigh10', '10 взвешиваний', '10 дней с взвешиванием', weighDays, 10),
  ];
}

Future<HabitSummary> loadHabits(AppDatabase db, {DateTime? now}) async {
  final today = dayStart(now ?? DateTime.now());
  final foods = await db.select(db.foodEntries).get();
  final waters = await db.select(db.waterEntries).get();
  final weights = await db.allWeights();
  final goals = await db.allGoals();
  final tGoals = await db.allTrainingGoals();
  final workouts = await db.select(db.workouts).get();
  final lifts = await db.select(db.liftSessions).get();

  final kcal = <String, double>{};
  for (final f in foods) {
    kcal[f.date] = (kcal[f.date] ?? 0) + f.caloriesSnapshot;
  }
  final water = <String, double>{};
  for (final w in waters) {
    if (w.beverageType == 'water') water[w.date] = (water[w.date] ?? 0) + w.volumeMl;
  }
  final weighed = {for (final w in weights) w.date};
  final trained = <String>{
    for (final w in workouts) dayKey(w.startTime),
    for (final l in lifts) dayKey(l.startedAt),
  };

  ({double cal, double water}) goalOf(String k) {
    DailyGoal? g;
    for (final x in goals) {
      if (x.effectiveDate.compareTo(k) <= 0) g = x;
    }
    var cal = g?.calories ?? 2000, wat = g?.waterMl ?? 2000;
    if (trained.contains(k)) {
      TrainingGoal? t;
      for (final x in tGoals) {
        if (x.effectiveDate.compareTo(k) <= 0) t = x;
      }
      if (t != null && t.enabled) {
        cal = t.calories;
        wat = t.waterMl;
      }
    }
    return (cal: cal, water: wat);
  }

  final allKeys = <String>{...kcal.keys, ...water.keys, ...weighed, ...trained};
  final days = <String, HabitDay>{};
  var foodDays = 0, waterDays = 0, goalDays = 0;
  for (final k in allKeys) {
    if (k.compareTo(dayKey(today)) > 0) continue;
    final g = goalOf(k);
    final hasFood = kcal.containsKey(k);
    final waterOk = (water[k] ?? 0) >= g.water && g.water > 0;
    final met = hasFood && kcal[k]! >= g.cal * 0.9 && kcal[k]! <= g.cal * 1.1;
    if (hasFood) foodDays++;
    if (waterOk) waterDays++;
    if (met) goalDays++;
    days[k] = HabitDay(k, hasFood, waterOk, trained.contains(k), weighed.contains(k), met);
  }
  final foodKeys = days.values.where((d) => d.food).map((d) => d.key);
  final run = longestRun(foodKeys);
  final workoutDays = days.values.where((d) => d.workout).length;
  final weighDays = days.values.where((d) => d.weighed).length;
  return HabitSummary(
      days,
      buildAchievements(
          foodDays: foodDays,
          bestRun: run,
          waterDays: waterDays,
          workoutDays: workoutDays,
          weighDays: weighDays,
          goalDays: goalDays),
      foodDays,
      waterDays,
      workoutDays,
      weighDays,
      goalDays,
      run);
}
