import '../nutrition.dart' show GoalType;
import 'nutrition_calculation_models.dart';

const kAdaptationIntervalDays = 14;
const kMaxOffsetKcal = 500.0;

/// Целевой недельный темп изменения массы, доля массы тела в неделю.
/// Набор: +0,25…+0,5 %; похудение: −1,0…−0,5 %; поддержание: ±0,25 %.
({double lo, double hi}) targetRate(GoalType g) => switch (g) {
      GoalType.gain => (lo: 0.0025, hi: 0.005),
      GoalType.lose => (lo: -0.010, hi: -0.005),
      GoalType.maintain => (lo: -0.0025, hi: 0.0025),
    };

String _pct(double rate) {
  final v = (rate * 100).abs().toStringAsFixed(2).replaceAll('.', ',');
  return '${rate >= 0 ? '+' : '−'}$v %';
}

/// Проверяет, нужно ли менять норму. Не чаще раза в 14 дней, только при достоверном
/// тренде и достаточно полном дневнике. Шаг — 100 или 150 ккал, накопленная поправка в пределах ±500.
AdaptationCheck checkAdaptation({
  required GoalType goal,
  required WeightTrend trend,
  required double currentTarget,
  required double currentOffset,
  required double floorKcal,
  required double foodCoverage, // доля дней периода с записями питания, 0..1
  required DateTime now,
  DateTime? lastAdjustment,
}) {
  if (lastAdjustment != null &&
      now.difference(lastAdjustment).inDays < kAdaptationIntervalDays) {
    final left =
        kAdaptationIntervalDays - now.difference(lastAdjustment).inDays;
    return AdaptationCheck(null,
        'Следующая проверка через $left дн.: норму не меняют чаще раза в две недели.');
  }
  if (!trend.reliable || trend.kgPerWeek == null || trend.smoothedKg == null) {
    return AdaptationCheck(null, trend.reason ?? 'Недостаточно данных о весе.');
  }
  if (foodCoverage < 0.6) {
    return const AdaptationCheck(
        null,
        'Дневник питания заполнен менее чем за 60 % дней: корректировка по весу была бы '
        'недостоверной.');
  }
  final rate = trend.kgPerWeek! / trend.smoothedKg!; // доля массы в неделю
  final r = targetRate(goal);
  double dir = 0, gap = 0;
  if (rate < r.lo) {
    dir =
        1; // масса растёт медленнее (или падает быстрее) цели → калорий больше
    gap = r.lo - rate;
  } else if (rate > r.hi) {
    dir = -1;
    gap = rate - r.hi;
  }
  final pct = _pct(rate);
  if (dir == 0) {
    return AdaptationCheck(null,
        'Темп изменения массы ($pct в неделю) в пределах цели: норма остаётся.');
  }
  final step = gap > 0.0025 ? 150.0 : 100.0;
  var newOffset = (currentOffset + dir * step)
      .clamp(-kMaxOffsetKcal, kMaxOffsetKcal)
      .toDouble();
  var newTarget = currentTarget + (newOffset - currentOffset);
  if (newTarget < floorKcal) {
    newTarget = floorKcal;
    newOffset = currentOffset + (newTarget - currentTarget);
  }
  final delta = newOffset - currentOffset;
  if (delta.abs() < 1) {
    return const AdaptationCheck(null,
        'Достигнут предел автоматической поправки; при необходимости измените норму вручную.');
  }
  final d = trend.days;
  final why = switch (goal) {
    GoalType.gain => delta > 0
        ? 'Средняя масса за последние $d дн. менялась медленнее целевого темпа ($pct в неделю)'
        : 'Масса за последние $d дн. росла быстрее целевого темпа ($pct в неделю)',
    GoalType.lose => delta > 0
        ? 'Масса за последние $d дн. снижалась быстрее безопасного темпа ($pct в неделю)'
        : 'Масса за последние $d дн. снижалась медленнее целевого темпа ($pct в неделю)',
    GoalType.maintain => delta > 0
        ? 'Масса за последние $d дн. снижалась ($pct в неделю), хотя цель — поддержание'
        : 'Масса за последние $d дн. росла ($pct в неделю), хотя цель — поддержание',
  };
  final act = delta > 0 ? 'увеличить' : 'уменьшить';
  final text =
      '$why. Предлагаем $act суточную норму на ${delta.abs().round()} ккал.';
  return AdaptationCheck(
      AdaptationProposal(delta, newOffset, newTarget, text), text);
}
