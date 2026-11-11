import 'dart:convert';

import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../../core/nutrition/calc_engine.dart';
import '../../core/nutrition/calorie_adaptation_service.dart';
import '../../core/nutrition/energy_balance_estimator.dart';
import '../../core/nutrition/nutrition_calculation_models.dart';
import '../../core/nutrition/tdee_calculator.dart';
import '../../core/nutrition/weight_trend_analyzer.dart';
import '../../database/database.dart';
import '../../features/dashboard/day_data.dart';

const kCalcModeKey = 'calc_mode';
const kCalcOffsetKey = 'calc_offset_kcal';
const kCalcLastAdjustKey = 'calc_last_adjust';
const kCalcAutoApplyKey = 'calc_auto_apply';
const kCalcHistoryKey = 'calc_history';
const kCalcLastWeightKey = 'calc_last_weight';

CalcMode calcModeOf(String? v) => CalcMode.values
    .firstWhere((m) => m.name == v, orElse: () => CalcMode.adaptive);

/// Запись истории расчётов и корректировок. [prev*] нужны для отмены автоприменения.
class CalcHistoryEntry {
  final DateTime at;
  final String kind; // recalc | adapt | auto | undo | manual
  final String text;
  final double? fromKcal, toKcal;
  final double? prevOffset;
  final List<double>? prevGoal; // ккал, Б, Ж, У, вода

  const CalcHistoryEntry(this.at, this.kind, this.text,
      {this.fromKcal, this.toKcal, this.prevOffset, this.prevGoal});

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'kind': kind,
        'text': text,
        if (fromKcal != null) 'from': fromKcal,
        if (toKcal != null) 'to': toKcal,
        if (prevOffset != null) 'po': prevOffset,
        if (prevGoal != null) 'pg': prevGoal,
      };

  static CalcHistoryEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return CalcHistoryEntry(at, '${j['kind']}', '${j['text']}',
        fromKcal: (j['from'] as num?)?.toDouble(),
        toKcal: (j['to'] as num?)?.toDouble(),
        prevOffset: (j['po'] as num?)?.toDouble(),
        prevGoal:
            (j['pg'] as List?)?.map((e) => (e as num).toDouble()).toList());
  }
}

List<CalcHistoryEntry> parseHistory(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final l = jsonDecode(raw);
    if (l is! List) return const [];
    return [
      for (final e in l)
        if (CalcHistoryEntry.fromJson(e) != null) CalcHistoryEntry.fromJson(e)!
    ];
  } catch (_) {
    return const [];
  }
}

/// Всё, что нужно экрану профиля и окну «как считается».
class PlanSnapshot {
  final User? user;
  final CalcMode mode;
  final bool autoApply;
  final int? age;
  final double? weightKg;
  final String weightSource; // «умные весы», «ручной ввод» или ''
  final int? weightAgeDays;
  final CalcResult? result;
  final bool minor; // формула неприменима
  final WeightTrend trend;
  final AdaptationCheck adaptation;
  final EnergyEstimate energy;
  final double offsetKcal;
  final DateTime? lastAdjust;
  final List<CalcHistoryEntry> history;
  final GoalValues currentGoal;
  final double? weightAtLastCalc;
  final double foodCoverage;

  const PlanSnapshot({
    required this.user,
    required this.mode,
    required this.autoApply,
    required this.age,
    required this.weightKg,
    required this.weightSource,
    required this.weightAgeDays,
    required this.result,
    required this.minor,
    required this.trend,
    required this.adaptation,
    required this.energy,
    required this.offsetKcal,
    required this.lastAdjust,
    required this.history,
    required this.currentGoal,
    required this.weightAtLastCalc,
    required this.foodCoverage,
  });

  bool get hasProfile => user != null && result != null;

  AdaptationProposal? get proposal =>
      mode == CalcMode.adaptive ? adaptation.proposal : null;

  /// Вес заметно изменился с момента последнего расчёта норм.
  double? get weightDriftKg {
    if (weightKg == null || weightAtLastCalc == null) return null;
    final d = weightKg! - weightAtLastCalc!;
    return d.abs() >= 1.0 ? d : null;
  }

  Confidence get confidence {
    if (result == null) return Confidence.none;
    if (energy.tdee != null) return energy.confidence;
    return Confidence.low;
  }
}

GoalValues _toGoal(CalcResult r) => GoalValues(
    r.targetCalories.roundToDouble(),
    r.macros.proteins.roundToDouble(),
    r.macros.fats.roundToDouble(),
    r.macros.carbs.roundToDouble(),
    (r.waterMl / 50).round() * 50.0);

GoalValues goalFromResult(CalcResult r) => _toGoal(r);

Future<PlanSnapshot> loadPlan(AppDatabase db, DateTime now) async {
  final user = await db.getUser();
  final settings = await db.allSettings();
  final weights = await db.allWeights();
  final today = dayStart(now);
  final goal = await db.goalFor(dayKey(today));
  final mode = calcModeOf(settings[kCalcModeKey]);
  final offset = double.tryParse(settings[kCalcOffsetKey] ?? '') ?? 0;
  final last = DateTime.tryParse(settings[kCalcLastAdjustKey] ?? '');
  final history = parseHistory(settings[kCalcHistoryKey]);
  final w = weights.isEmpty ? null : weights.last;

  int? age;
  CalcResult? result;
  var minor = false;
  if (user != null &&
      user.birthDate != null &&
      user.heightCm != null &&
      w != null) {
    age = ageOn(user.birthDate!, now);
    result = calculatePlan(CalcInput(
      sex: user.sex == 'female' ? Sex.female : Sex.male,
      age: age,
      heightCm: user.heightCm!,
      weightKg: w.weightKg,
      level: ActivityLevel.values.firstWhere(
          (l) => l.name == user.activityLevel,
          orElse: () => ActivityLevel.light),
      goal: GoalType.values.firstWhere((g) => g.name == user.goalType,
          orElse: () => GoalType.maintain),
      adaptationOffsetKcal: mode == CalcMode.adaptive ? offset : 0,
    ));
    minor = result == null;
  }

  final points = [
    for (final e in weights) WeightPoint(e.measuredAt, e.weightKg)
  ];
  final trend = analyzeWeightTrend(points, now);

  // Дневник питания за 28 дней: нужен и для оценки расхода, и для проверки адаптации.
  final from = today.subtract(const Duration(days: 27));
  final intake = await computeIntakeByDay(db, dayKey(from), dayKey(today));
  final coverage = intake.where((v) => v > 0).length / 28;

  final goalType = GoalType.values.firstWhere(
      (g) => g.name == (user?.goalType ?? 'maintain'),
      orElse: () => GoalType.maintain);
  final energy = result == null
      ? const EnergyEstimate(null, Confidence.none, 'Нет данных анкеты.')
      : estimateTdee(
          trend: trend,
          dailyIntakeKcal: intake,
          observedDays: 28,
          formulaTdee: result.tdee);
  final adaptation = result == null
      ? const AdaptationCheck(null, 'Заполните анкету, чтобы рассчитать нормы.')
      : checkAdaptation(
          goal: goalType,
          trend: trend,
          currentTarget: result.targetCalories,
          currentOffset: offset,
          floorKcal: calorieFloor(
              bmr: result.bmr,
              sex: user!.sex == 'female' ? Sex.female : Sex.male),
          foodCoverage: coverage,
          now: now,
          lastAdjustment: last);

  return PlanSnapshot(
    user: user,
    mode: mode,
    autoApply: settings[kCalcAutoApplyKey] == '1',
    age: age,
    weightKg: w?.weightKg,
    weightSource:
        w == null ? '' : (w.impedance != null ? 'умные весы' : 'ручной ввод'),
    weightAgeDays:
        w == null ? null : today.difference(dayStart(w.measuredAt)).inDays,
    result: result,
    minor: minor,
    trend: trend,
    adaptation: adaptation,
    energy: energy,
    offsetKcal: offset,
    lastAdjust: last,
    history: history,
    currentGoal: goal,
    weightAtLastCalc: double.tryParse(settings[kCalcLastWeightKey] ?? ''),
    foodCoverage: coverage,
  );
}

Future<void> _pushHistory(AppDatabase db, CalcHistoryEntry e) async {
  final cur = parseHistory((await db.allSettings())[kCalcHistoryKey]);
  final all = [...cur, e];
  final trimmed = all.length > 40 ? all.sublist(all.length - 40) : all;
  await db.setSetting(
      kCalcHistoryKey, jsonEncode([for (final x in trimmed) x.toJson()]));
}

List<double> _goalList(GoalValues g) =>
    [g.calories, g.proteins, g.fats, g.carbs, g.waterMl];

/// Явный пересчёт норм по текущим данным (кнопка «Пересчитать»).
Future<GoalValues?> applyRecalc(AppDatabase db, PlanSnapshot p,
    {DateTime? now}) async {
  final r = p.result;
  if (r == null) return null;
  final at = now ?? DateTime.now();
  final g = _goalFromResultWithMode(p, r);
  final prev = p.currentGoal;
  await db.setGoal(dayKey(at), g);
  await db.setSetting(kCalcLastWeightKey, '${p.weightKg}');
  await _pushHistory(
      db,
      CalcHistoryEntry(at, 'recalc',
          'Пересчёт: ${g.calories.round()} ккал, Б ${g.proteins.round()}, Ж ${g.fats.round()}, У ${g.carbs.round()}',
          fromKcal: prev.calories,
          toKcal: g.calories,
          prevOffset: p.offsetKcal,
          prevGoal: _goalList(prev)));
  return g;
}

GoalValues _goalFromResultWithMode(PlanSnapshot p, CalcResult r) => _toGoal(r);

/// Принять предложение адаптации: сохранить поправку и нормы, записать в историю.
Future<GoalValues?> acceptProposal(AppDatabase db, PlanSnapshot p,
    {DateTime? now, bool auto = false}) async {
  final prop = p.adaptation.proposal;
  final user = p.user;
  if (prop == null || user == null || p.result == null) return null;
  final at = now ?? DateTime.now();
  await db.setSetting(kCalcOffsetKey, '${prop.newOffsetKcal}');
  await db.setSetting(kCalcLastAdjustKey, at.toIso8601String());
  final fresh = await loadPlan(db, at);
  final g = _toGoal(fresh.result!);
  final prev = p.currentGoal;
  await db.setGoal(dayKey(at), g);
  await db.setSetting(kCalcLastWeightKey, '${fresh.weightKg}');
  await _pushHistory(
      db,
      CalcHistoryEntry(at, auto ? 'auto' : 'adapt', prop.reason,
          fromKcal: prev.calories,
          toKcal: g.calories,
          prevOffset: p.offsetKcal,
          prevGoal: _goalList(prev)));
  return g;
}

/// Отмена последнего изменения (ручная или автоматическая корректировка).
Future<bool> undoLast(AppDatabase db, {DateTime? now}) async {
  final settings = await db.allSettings();
  final hist = parseHistory(settings[kCalcHistoryKey]);
  final idx = hist.lastIndexWhere(
      (e) => (e.kind == 'adapt' || e.kind == 'auto') && e.prevGoal != null);
  if (idx < 0) return false;
  final e = hist[idx];
  final at = now ?? DateTime.now();
  final pg = e.prevGoal!;
  await db.setGoal(dayKey(at), GoalValues(pg[0], pg[1], pg[2], pg[3], pg[4]));
  await db.setSetting(kCalcOffsetKey, '${e.prevOffset ?? 0}');
  // чтобы отменённое предложение не вернулось сразу же, откладываем следующую проверку
  await db.setSetting(kCalcLastAdjustKey, at.toIso8601String());
  final rest = [...hist]..removeAt(idx);
  rest.add(CalcHistoryEntry(
      at, 'undo', 'Изменение отменено: норма ${pg[0].round()} ккал.',
      fromKcal: e.toKcal, toKcal: pg[0]));
  await db.setSetting(
      kCalcHistoryKey, jsonEncode([for (final x in rest) x.toJson()]));
  return true;
}

/// Отложить предложение: следующая проверка не раньше чем через 14 дней.
Future<void> dismissProposal(AppDatabase db, {DateTime? now}) => db.setSetting(
    kCalcLastAdjustKey, (now ?? DateTime.now()).toIso8601String());

Future<void> setCalcMode(AppDatabase db, CalcMode m) =>
    db.setSetting(kCalcModeKey, m.name);

/// Ручное изменение норм переводит расчёт в режим «вручную»: автоматика их не трогает.
Future<void> recordManualGoals(AppDatabase db, GoalValues prev, GoalValues now,
    {DateTime? at}) async {
  await setCalcMode(db, CalcMode.manual);
  await _pushHistory(
      db,
      CalcHistoryEntry(at ?? DateTime.now(), 'manual',
          'Нормы изменены вручную: ${now.calories.round()} ккал. Режим расчёта: вручную.',
          fromKcal: prev.calories, toKcal: now.calories));
}

/// Автоприменение: только в адаптивном режиме при включённой настройке.
Future<bool> maybeAutoApply(AppDatabase db, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final p = await loadPlan(db, at);
  if (p.mode != CalcMode.adaptive ||
      !p.autoApply ||
      p.adaptation.proposal == null) return false;
  return await acceptProposal(db, p, now: at, auto: true) != null;
}

String confidenceLabel(Confidence c) => switch (c) {
      Confidence.none => 'нет данных',
      Confidence.low => 'низкая (расчёт по формуле)',
      Confidence.medium => 'средняя (уточнено по динамике веса)',
      Confidence.high => 'высокая',
    };
