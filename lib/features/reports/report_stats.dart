// Сводка за период для PDF-отчёта. Только реальные данные: если за период их нет, поле null.
import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../database/database.dart';
import '../dashboard/day_data.dart';
import '../training/strength_math.dart';

class LiftExerciseSummary {
  final String name;
  final int sets;
  final double? maxWeight, est1Rm;
  const LiftExerciseSummary(this.name, this.sets, this.maxWeight, this.est1Rm);
}

class LiftSummary {
  final int sessions;
  final double volume;
  final List<LiftExerciseSummary> exercises;
  const LiftSummary(this.sessions, this.volume, this.exercises);
  static const empty = LiftSummary(0, 0, []);
}

class ReportStats {
  final String fromKey, toKey;
  final List<DayStat> days;
  final LiftSummary lift;

  /// Среднее по дням, где есть записи о питании.
  final int foodDays;
  final double? avgKcal, avgProteins, avgFats, avgCarbs, avgWaterMl, goalKcal;
  final int stepDays;
  final double? avgSteps, avgDistanceKm;
  final int workoutCount;
  final double workoutMinutes;
  final int sleepDays;
  final double? avgSleepHours;
  final int hrDays;
  final double? avgHr, maxHr;
  final double? firstWeight, lastWeight;
  final int weightDays;

  const ReportStats({
    required this.fromKey,
    required this.toKey,
    required this.days,
    required this.lift,
    required this.foodDays,
    this.avgKcal,
    this.avgProteins,
    this.avgFats,
    this.avgCarbs,
    this.avgWaterMl,
    this.goalKcal,
    required this.stepDays,
    this.avgSteps,
    this.avgDistanceKm,
    required this.workoutCount,
    required this.workoutMinutes,
    required this.sleepDays,
    this.avgSleepHours,
    required this.hrDays,
    this.avgHr,
    this.maxHr,
    this.firstWeight,
    this.lastWeight,
    required this.weightDays,
  });

  double? get weightChange =>
      firstWeight == null || lastWeight == null || weightDays < 2
          ? null
          : lastWeight! - firstWeight!;
}

double? _avg(Iterable<double> v) =>
    v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

ReportStats buildReportStats(
    String fromKey, String toKey, List<DayStat> stats, LiftSummary lift) {
  final food = stats.where((d) => d.hasFood).toList();
  final steps = stats.where((d) => d.act.steps > 0).toList();
  final sleep = stats.where((d) => d.act.sleepMinutes > 0).toList();
  final hr = stats.where((d) => d.act.avgHr != null).toList();
  final weights = stats.where((d) => d.weight != null).toList();
  double? maxHr;
  for (final d in stats) {
    final m = d.act.maxHr;
    if (m != null && (maxHr == null || m > maxHr)) maxHr = m;
  }
  return ReportStats(
    fromKey: fromKey,
    toKey: toKey,
    days: stats,
    lift: lift,
    foodDays: food.length,
    avgKcal: _avg(food.map((d) => d.n.calories)),
    avgProteins: _avg(food.map((d) => d.n.proteins)),
    avgFats: _avg(food.map((d) => d.n.fats)),
    avgCarbs: _avg(food.map((d) => d.n.carbs)),
    avgWaterMl: _avg(food.map((d) => d.waterMl)),
    goalKcal: _avg(food.map((d) => d.goal.calories)),
    stepDays: steps.length,
    avgSteps: _avg(steps.map((d) => d.act.steps)),
    avgDistanceKm: _avg(steps.map((d) => d.act.distanceKm)),
    workoutCount: stats.fold(0, (a, d) => a + d.act.workouts.length),
    workoutMinutes: stats.fold(0.0, (a, d) => a + d.act.workoutMinutes),
    sleepDays: sleep.length,
    avgSleepHours: _avg(sleep.map((d) => d.act.sleepMinutes / 60)),
    hrDays: hr.length,
    avgHr: _avg(hr.map((d) => d.act.avgHr!)),
    maxHr: maxHr,
    firstWeight: weights.isEmpty ? null : weights.first.weight,
    lastWeight: weights.isEmpty ? null : weights.last.weight,
    weightDays: weights.length,
  );
}

Future<LiftSummary> loadLiftSummary(
    AppDatabase db, DateTime from, DateTime toExclusive) async {
  final sessions = await (db.select(db.liftSessions)
        ..where((t) =>
            t.startedAt.isBiggerOrEqualValue(from) &
            t.startedAt.isSmallerThanValue(toExclusive)))
      .get();
  if (sessions.isEmpty) return LiftSummary.empty;
  final ids = sessions.map((s) => s.id).toList();
  final sets =
      await (db.select(db.liftSets)..where((t) => t.sessionId.isIn(ids))).get();
  final names = {
    for (final e in await db.select(db.liftExercises).get()) e.id: e.name
  };
  final by = <int, List<SetData>>{};
  for (final s in sets) {
    by.putIfAbsent(s.exerciseId, () => []).add(SetData(s.reps, s.weightKg));
  }
  final ex = [
    for (final e in by.entries)
      LiftExerciseSummary(names[e.key] ?? 'Упражнение', e.value.length,
          maxWeight(e.value), best1Rm(e.value))
  ]..sort((a, b) => b.sets.compareTo(a.sets));
  return LiftSummary(sessions.length,
      volumeKg([for (final s in sets) SetData(s.reps, s.weightKg)]), ex);
}

Future<ReportStats> loadReportStats(
    AppDatabase db, DateTime from, DateTime to) async {
  final fk = dayKey(from), tk = dayKey(to);
  final stats = await computeRangeStats(db, fk, tk);
  final list = stats.values.toList()..sort((a, b) => a.key.compareTo(b.key));
  final lift = await loadLiftSummary(db, from, to.add(const Duration(days: 1)));
  return buildReportStats(fk, tk, list, lift);
}
