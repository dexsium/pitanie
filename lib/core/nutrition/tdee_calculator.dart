import '../nutrition.dart' show ActivityLevel, GoalType, Sex, activityFactor;

/// Стартовая доля дефицита/профицита по цели (от TDEE).
double defaultGoalFraction(GoalType g) => switch (g) {
      GoalType.lose => -0.15,
      GoalType.gain => 0.10,
      GoalType.maintain => 0.0,
    };

/// Допустимые границы доли: дефицит 10–20 %, профицит 5–15 %.
double clampGoalFraction(GoalType g, double f) => switch (g) {
      GoalType.lose => f.clamp(-0.20, -0.10).toDouble(),
      GoalType.gain => f.clamp(0.05, 0.15).toDouble(),
      GoalType.maintain => 0.0,
    };

/// TDEE = BMR × PAL. Тренировки уже входят в PAL, повторно не добавляются.
double tdeeFrom(double bmr, ActivityLevel level) =>
    bmr * activityFactor[level]!;

/// Нижняя граница суточной калорийности: не ниже BMR и не ниже 1200 (ж) / 1500 (м) ккал.
double calorieFloor({required double bmr, required Sex sex}) {
  final abs = sex == Sex.male ? 1500.0 : 1200.0;
  return bmr > abs ? bmr : abs;
}

/// Режим «с часами»: к базовой норме добавляются только достоверные активные калории
/// сверх уже учтённых в PAL. Если данные часов ненадёжны или отсутствуют — база без изменений.
/// Активные калории — это не весь расход, поэтому полный «расход часов» к TDEE не прибавляется.
double watchAdjustedTarget({
  required double base,
  required double? activeKcal,
  required double includedActiveKcal,
  required bool reliable,
}) {
  if (!reliable || activeKcal == null) return base;
  final extra = activeKcal - includedActiveKcal;
  return base + (extra > 0 ? extra : 0);
}
