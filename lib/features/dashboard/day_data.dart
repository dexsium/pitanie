import '../../core/activity_aggregator.dart';
import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';

class ActivityDay {
  final double steps, distanceKm, activeKcal, totalKcal, workoutMinutes, sleepMinutes;
  final double? avgHr, maxHr;
  final List<Workout> workouts;
  final String? source;
  const ActivityDay({
    this.steps = 0,
    this.distanceKm = 0,
    this.activeKcal = 0,
    this.totalKcal = 0,
    this.workoutMinutes = 0,
    this.sleepMinutes = 0,
    this.avgHr,
    this.maxHr,
    this.workouts = const [],
    this.source,
  });

  bool get hasData =>
      steps > 0 || distanceKm > 0 || activeKcal > 0 || workouts.isNotEmpty || avgHr != null;
}

ActivityDay buildActivityDay(List<ActivityRecord> recs, List<Workout> wk,
    DateTime day, String? preferred) {
  final from = dayStart(day), to = dayEnd(day);
  List<Interval> of(String t) => recs
      .where((r) => r.type == t)
      .map((r) => Interval(r.source, r.startTime, r.endTime, r.value))
      .toList();

  final steps = of('steps');
  final hr = dayRecords(of('heartRate'), from, to, preferred: preferred);
  const six = Duration(hours: 6);
  final dayWorkouts = wk
      .where((w) => w.endTime.isAfter(from) && w.startTime.isBefore(to))
      .toList();
  double? avg, mx;
  if (hr.isNotEmpty) {
    avg = hr.map((e) => e.value).reduce((a, b) => a + b) / hr.length;
    mx = hr.map((e) => e.value).reduce((a, b) => a > b ? a : b);
  }
  return ActivityDay(
    steps: dayTotal(steps, from, to, preferred: preferred),
    distanceKm: dayTotal(of('distance'), from, to, preferred: preferred) / 1000,
    activeKcal: dayTotal(of('activeEnergy'), from, to, preferred: preferred),
    totalKcal: dayTotal(of('totalEnergy'), from, to, preferred: preferred),
    // Сон относится к дню пробуждения: окно 18:00 → 18:00.
    sleepMinutes: dayTotal(of('sleep'), from.subtract(six), to.subtract(six),
        preferred: preferred),
    workoutMinutes: unionMinutes(
        dayWorkouts.map((w) => (w.startTime, w.endTime)).toList(), from, to),
    avgHr: avg,
    maxHr: mx,
    workouts: dayWorkouts,
    source: pickSource(steps, from, to, preferred),
  );
}

Future<ActivityDay> loadActivityDay(
    AppDatabase db, DateTime day, String? preferred) async {
  final recs = await db.activityBetween(
      dayStart(day).subtract(const Duration(hours: 6)), dayEnd(day));
  final wk = await db.workoutsBetween(dayStart(day), dayEnd(day));
  return buildActivityDay(recs, wk, day, preferred);
}

class DayData {
  final String key;
  final List<FoodEntry> food;
  final List<WaterEntry> water;
  final GoalValues goal;
  final ActivityDay activity;
  final double? weight;
  final CalorieMode mode;
  final double includedActiveKcal;

  const DayData(this.key, this.food, this.water, this.goal, this.activity,
      this.weight, this.mode, this.includedActiveKcal);

  Nutrients get eaten => food.fold(
      Nutrients.zero,
      (s, e) => s +
          Nutrients(e.caloriesSnapshot, e.proteinsSnapshot, e.fatsSnapshot,
              e.carbohydratesSnapshot));

  Nutrients mealTotal(String meal) => food.where((e) => e.mealType == meal).fold(
      Nutrients.zero,
      (s, e) => s +
          Nutrients(e.caloriesSnapshot, e.proteinsSnapshot, e.fatsSnapshot,
              e.carbohydratesSnapshot));

  double get plainWaterMl =>
      water.where((w) => w.beverageType == 'water').fold(0.0, (s, w) => s + w.volumeMl);
  double get otherDrinksMl =>
      water.where((w) => w.beverageType != 'water').fold(0.0, (s, w) => s + w.volumeMl);

  double get calorieTarget => effectiveCalorieTarget(
      base: goal.calories,
      mode: mode,
      activeKcal: activity.activeKcal,
      includedActiveKcal: includedActiveKcal);
}

Future<DayData> loadDayData(AppDatabase db, String key) async {
  final settings = await db.allSettings();
  final food = await db.foodForDay(key);
  final water = await db.waterForDay(key);
  final goal = await db.goalFor(key);
  final act =
      await loadActivityDay(db, parseDayKey(key), settings['preferred_source']);
  final weights = (await db.allWeights()).where((w) => w.date == key).toList();
  return DayData(
    key,
    food,
    water,
    goal,
    act,
    weights.isEmpty ? null : weights.last.weightKg,
    settings['calorie_mode'] == 'dynamic' ? CalorieMode.dynamic : CalorieMode.fixed,
    double.tryParse(settings['included_active_kcal'] ?? '') ?? 0,
  );
}

class DayStat {
  final String key;
  final Nutrients n;
  final double waterMl;
  final ActivityDay act;
  final double? weight;
  final GoalValues goal;
  final bool hasFood;
  const DayStat(this.key, this.n, this.waterMl, this.act, this.weight, this.goal,
      this.hasFood);

  /// Норма выполнена: калории в пределах 90–110 % цели.
  bool get met =>
      hasFood && n.calories >= goal.calories * 0.9 && n.calories <= goal.calories * 1.1;
}

Future<Map<String, DayStat>> computeRangeStats(
    AppDatabase db, String fromKey, String toKey) async {
  final settings = await db.allSettings();
  final preferred = settings['preferred_source'];
  final food = await db.foodBetween(fromKey, toKey);
  final water = await db.waterBetween(fromKey, toKey);
  final goals = await db.allGoals();
  final weights = await db.allWeights();
  final fromD = parseDayKey(fromKey), toD = parseDayKey(toKey);
  final recs = await db.activityBetween(
      fromD.subtract(const Duration(hours: 6)), dayEnd(toD));
  final wk = await db.workoutsBetween(fromD, dayEnd(toD));

  GoalValues goalFor(String k) {
    DailyGoal? g;
    for (final x in goals) {
      if (x.effectiveDate.compareTo(k) <= 0) g = x;
    }
    return g == null
        ? GoalValues.fallback
        : GoalValues(g.calories, g.proteins, g.fats, g.carbohydrates, g.waterMl);
  }

  final out = <String, DayStat>{};
  for (var d = fromD; !d.isAfter(toD); d = DateTime(d.year, d.month, d.day + 1)) {
    final k = dayKey(d);
    final fd = food.where((e) => e.date == k).toList();
    final n = fd.fold(
        Nutrients.zero,
        (s, e) => s +
            Nutrients(e.caloriesSnapshot, e.proteinsSnapshot, e.fatsSnapshot,
                e.carbohydratesSnapshot));
    final w = water
        .where((e) => e.date == k && e.beverageType == 'water')
        .fold(0.0, (s, e) => s + e.volumeMl);
    final wd = weights.where((e) => e.date == k).toList();
    out[k] = DayStat(k, n, w, buildActivityDay(recs, wk, d, preferred),
        wd.isEmpty ? null : wd.last.weightKg, goalFor(k), fd.isNotEmpty);
  }
  return out;
}
