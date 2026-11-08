// Достижение целей дня и подсказки «чем добрать норму». Чистая логика без БД и Flutter.
//
// Подсказки считаются по записанным в дневнике продуктам и нормам пользователя. Это подбор
// порций под недостающие значения, а не рекомендация врача или диетолога.
import '../../core/nutrition.dart';

enum GoalKind { calories, protein, water, steps, macros }

class GoalEvent {
  final GoalKind kind;
  final String title, body;
  const GoalEvent(this.kind, this.title, this.body);

  String get id => kind.name;
  int get notificationId => 9101 + kind.index;
}

String _n(double v) => v.round().toString();

/// Какие цели дня выполнены прямо сейчас. Уведомление о каждой отправляется один раз за день.
List<GoalEvent> achievedGoals({
  required Nutrients eaten,
  required GoalValues goal,
  required double calorieTarget,
  required double waterMl,
  required double steps,
  required double stepsGoal,
}) {
  final out = <GoalEvent>[];
  if (calorieTarget > 0 && eaten.calories >= calorieTarget) {
    out.add(GoalEvent(
        GoalKind.calories,
        'Норма калорий набрана',
        'Съедено ${_n(eaten.calories)} из ${_n(calorieTarget)} ккал. '
            'На сегодня достаточно.'));
  }
  if (goal.proteins > 0 && eaten.proteins >= goal.proteins) {
    out.add(GoalEvent(GoalKind.protein, 'Норма белка выполнена',
        'Белка ${_n(eaten.proteins)} г из ${_n(goal.proteins)} г.'));
  }
  if (goal.waterMl > 0 && waterMl >= goal.waterMl) {
    out.add(GoalEvent(GoalKind.water, 'Норма воды выполнена',
        'Выпито ${_n(waterMl)} мл из ${_n(goal.waterMl)} мл.'));
  }
  if (stepsGoal > 0 && steps >= stepsGoal) {
    out.add(GoalEvent(GoalKind.steps, 'Цель по шагам выполнена',
        'Пройдено ${_n(steps)} шагов из ${_n(stepsGoal)}.'));
  }
  bool near(double v, double t) => t > 0 && v >= t * 0.9 && v <= t * 1.1;
  if (near(eaten.calories, calorieTarget) &&
      near(eaten.proteins, goal.proteins) &&
      near(eaten.fats, goal.fats) &&
      near(eaten.carbs, goal.carbs)) {
    out.add(const GoalEvent(GoalKind.macros, 'Отличный день: КБЖУ в норме',
        'Калории, белки, жиры и углеводы в пределах ±10 % от нормы.'));
  }
  return out;
}

/// Сколько ещё нужно до нормы (не меньше нуля).
Nutrients remainingTo(Nutrients eaten, GoalValues goal, double calorieTarget) {
  double r(double target, double v) => target > v ? target - v : 0;
  return Nutrients(
      r(calorieTarget, eaten.calories),
      r(goal.proteins, eaten.proteins),
      r(goal.fats, eaten.fats),
      r(goal.carbs, eaten.carbs));
}

/// Есть ли смысл подсказывать: осталось не меньше 100 ккал или 15 г белка.
bool hasGap(Nutrients r) => r.calories >= 100 || r.proteins >= 15;

class FoodCandidate {
  final String name;

  /// Значения на 100 г (или 100 мл, если [liquid]).
  final Nutrients per100;
  final bool liquid;
  final double? pieceWeight, portionSize;

  /// true для значений из встроенного списка: это средние справочные числа, не ваши продукты.
  final bool approximate;
  const FoodCandidate(this.name, this.per100,
      {this.liquid = false,
      this.pieceWeight,
      this.portionSize,
      this.approximate = false});

  String get unit => liquid ? 'мл' : 'г';

  /// Варианты порции: (количество в г/мл, число штук или 0).
  List<(double, int)> options() {
    final pw = pieceWeight;
    if (pw != null && pw > 0) return [for (var k = 1; k <= 3; k++) (pw * k, k)];
    final ps = portionSize;
    if (ps != null && ps > 0) return [(ps, 0), (ps * 2, 0)];
    return [
      for (final g in const [30.0, 50.0, 75.0, 100.0, 150.0, 200.0, 250.0])
        (g, 0)
    ];
  }
}

/// Ключ «продукт + порция»: по нему «другой набор» исключает уже показанные порции,
/// но тот же продукт в другой порции показать можно.
String suggestionKey(String name, double amount) => '$name|${amount.round()}';

class FoodSuggestion {
  final FoodCandidate food;
  final double amount;
  final int pieces;
  const FoodSuggestion(this.food, this.amount, this.pieces);

  Nutrients get total => food.per100 * (amount / 100);

  /// Количество округляется до 5 г, чтобы подсказка читалась как порция, а не как расчёт.
  String get quantity {
    final a = (amount / 5).round() * 5;
    return pieces > 0 ? '$pieces шт. (~$a ${food.unit})' : '$a ${food.unit}';
  }

  String get label => '${food.name} — $quantity';

  String get key => suggestionKey(food.name, amount);
}

double _err(Nutrients r, List<double> s) {
  double e(double v, double sc, double w) {
    final x = v / sc;
    return w *
        (x >= 0
            ? x * x
            : 3 * x * x); // перебор штрафуется втрое сильнее недобора
  }

  return e(r.calories, s[0], 1) +
      e(r.proteins, s[1], 1.5) +
      e(r.fats, s[2], 1) +
      e(r.carbs, s[3], 1);
}

/// Подбирает до [max] продуктов, которые лучше всего закрывают недостаток [remaining].
/// Калории не превышаются больше чем на 10 % от остатка. Если подходящего нет, список пуст.
List<FoodSuggestion> suggestFoods(
    Nutrients remaining, GoalValues goal, List<FoodCandidate> pool,
    {int max = 3, Set<String> skip = const {}}) {
  double sc(double v) => v > 0 ? v : 1;
  final s = [
    sc(goal.calories),
    sc(goal.proteins),
    sc(goal.fats),
    sc(goal.carbs)
  ];
  var r = remaining;
  final out = <FoodSuggestion>[];
  final used = <String>{};
  for (var k = 0; k < max; k++) {
    final base = _err(r, s);
    if (base <= 0) break;
    FoodSuggestion? best;
    var bestErr = base;
    for (final f in pool) {
      if (used.contains(f.name)) continue;
      for (final (amount, pieces) in f.options()) {
        if (skip.contains(suggestionKey(f.name, amount))) continue;
        final d = f.per100 * (amount / 100);
        if (d.calories < 20) continue;
        if (d.calories > r.calories * 1.1 + 20) continue;
        final after = Nutrients(r.calories - d.calories,
            r.proteins - d.proteins, r.fats - d.fats, r.carbs - d.carbs);
        final e = _err(after, s);
        if (e < bestErr) {
          bestErr = e;
          best = FoodSuggestion(f, amount, pieces);
        }
      }
    }
    if (best == null || bestErr > base * 0.92) break;
    final t = best.total;
    r = Nutrients(r.calories - t.calories, r.proteins - t.proteins,
        r.fats - t.fats, r.carbs - t.carbs);
    used.add(best.food.name);
    out.add(best);
  }
  return out;
}

/// Когда калории уже закрыты, а белка не хватает: самый «белковый» продукт на недостающий белок.
/// Калории при этом превысятся, об этом сообщает [overflowNote].
List<FoodSuggestion> suggestProteinFirst(
    Nutrients remaining, List<FoodCandidate> pool) {
  if (remaining.proteins < 10) return const [];
  FoodSuggestion? best;
  var bestScore = double.infinity;
  for (final f in pool) {
    final p100 = f.per100;
    if (p100.calories <= 0 || p100.proteins * 4 / p100.calories < 0.4) continue;
    for (final (amount, pieces) in f.options()) {
      final d = p100 * (amount / 100);
      if (d.proteins < remaining.proteins * 0.5 ||
          d.proteins > remaining.proteins * 1.4) {
        continue;
      }
      final score = (d.proteins - remaining.proteins).abs() + d.calories * 0.05;
      if (score < bestScore) {
        bestScore = score;
        best = FoodSuggestion(f, amount, pieces);
      }
    }
  }
  return best == null ? const [] : [best];
}

/// Пояснение, если подсказка выходит за остаток калорий.
String? overflowNote(Nutrients remaining, List<FoodSuggestion> s) {
  final kcal = s.fold(0.0, (a, x) => a + x.total.calories);
  final over = kcal - remaining.calories;
  if (over < 15) return null;
  return 'Это добавит около ${over.round()} ккал сверх нормы.';
}

/// Средние справочные значения на 100 г: запасной список для тех, у кого мало своих продуктов.
const builtinFoods = <FoodCandidate>[
  FoodCandidate('Творог 5 %', Nutrients(121, 17, 5, 1.8), approximate: true),
  FoodCandidate('Куриная грудка варёная', Nutrients(165, 31, 3.6, 0),
      approximate: true),
  FoodCandidate('Яйцо варёное', Nutrients(155, 12.6, 10.6, 1.1),
      pieceWeight: 50, approximate: true),
  FoodCandidate('Греческий йогурт', Nutrients(59, 10.2, 0.4, 3.6),
      portionSize: 150, approximate: true),
  FoodCandidate('Кефир 1 %', Nutrients(40, 3.4, 1, 4.7),
      liquid: true, portionSize: 250, approximate: true),
  FoodCandidate('Тунец консервированный', Nutrients(116, 25.5, 0.8, 0),
      approximate: true),
  FoodCandidate('Гречка варёная', Nutrients(92, 3.4, 0.6, 19.9),
      approximate: true),
  FoodCandidate('Рис варёный', Nutrients(130, 2.7, 0.3, 28), approximate: true),
  FoodCandidate('Овсяные хлопья сухие', Nutrients(379, 13.2, 6.5, 67.7),
      portionSize: 40, approximate: true),
  FoodCandidate('Банан', Nutrients(89, 1.1, 0.3, 22.8),
      pieceWeight: 120, approximate: true),
  FoodCandidate('Яблоко', Nutrients(52, 0.3, 0.2, 13.8),
      pieceWeight: 180, approximate: true),
  FoodCandidate('Миндаль', Nutrients(579, 21.2, 49.9, 21.6),
      portionSize: 30, approximate: true),
  FoodCandidate('Оливковое масло', Nutrients(884, 0, 100, 0),
      portionSize: 10, approximate: true),
];

String _g(double v) => '${v.round()}';

/// Короткий текст для уведомления и карточки.
String gapSummary(Nutrients r) {
  final parts = <String>[
    if (r.calories >= 1) '${_g(r.calories)} ккал',
    if (r.proteins >= 1) 'белка ${_g(r.proteins)} г',
    if (r.fats >= 1) 'жиров ${_g(r.fats)} г',
    if (r.carbs >= 1) 'углеводов ${_g(r.carbs)} г',
  ];
  return parts.join(', ');
}

String suggestionText(List<FoodSuggestion> s) =>
    s.map((e) => e.label).join('; ');
