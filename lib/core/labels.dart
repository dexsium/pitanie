import 'package:flutter/material.dart';

import 'nutrition.dart';

enum Meal { breakfast, lunch, dinner, snack }

extension MealX on Meal {
  String get label => switch (this) {
        Meal.breakfast => 'Завтрак',
        Meal.lunch => 'Обед',
        Meal.dinner => 'Ужин',
        Meal.snack => 'Перекус',
      };
  IconData get icon => switch (this) {
        Meal.breakfast => Icons.wb_twilight_rounded,
        Meal.lunch => Icons.rice_bowl_rounded,
        Meal.dinner => Icons.dinner_dining_rounded,
        Meal.snack => Icons.apple_rounded,
      };
  Color get color => switch (this) {
        Meal.breakfast => const Color(0xFFFFA41B),
        Meal.lunch => const Color(0xFF3CC84B),
        Meal.dinner => const Color(0xFF8B5CF6),
        Meal.snack => const Color(0xFFEF4444),
      };
}

Meal mealFromKey(String k) =>
    Meal.values.firstWhere((m) => m.name == k, orElse: () => Meal.snack);

Meal mealForNow() {
  final h = DateTime.now().hour;
  if (h < 11) return Meal.breakfast;
  if (h < 16) return Meal.lunch;
  if (h < 21) return Meal.dinner;
  return Meal.snack;
}

String sexLabel(Sex s) => s == Sex.male ? 'Мужской' : 'Женский';

String goalLabel(GoalType g) => switch (g) {
      GoalType.gain => 'Набор мышечной массы',
      GoalType.lose => 'Снижение веса',
      GoalType.maintain => 'Поддержание веса',
    };

String levelLabel(ActivityLevel l) => switch (l) {
      ActivityLevel.sedentary => 'Сидячий образ жизни',
      ActivityLevel.light => 'Лёгкая (1–3 тренировки в неделю)',
      ActivityLevel.moderate => 'Умеренная (3–5 тренировок)',
      ActivityLevel.high => 'Высокая (6–7 тренировок)',
      ActivityLevel.extreme => 'Очень высокая (тяжёлый труд/спорт)',
    };

const beverageTypes = {
  'water': 'Вода',
  'tea': 'Чай',
  'coffee': 'Кофе',
  'juice': 'Сок',
  'milk': 'Молоко',
  'other': 'Другой напиток',
};

const productCategories = [
  'Крупы',
  'Мясо и птица',
  'Рыба',
  'Яйца',
  'Молочные',
  'Овощи',
  'Фрукты',
  'Орехи',
  'Хлеб и выпечка',
  'Масла',
  'Сладкое',
  'Напитки',
  'Прочее',
];

const workoutNames = {
  'RUNNING': 'Бег',
  'WALKING': 'Ходьба',
  'BIKING': 'Велосипед',
  'SWIMMING': 'Плавание',
  'HIKING': 'Поход',
  'YOGA': 'Йога',
  'STRENGTH_TRAINING': 'Силовая',
  'TRADITIONAL_STRENGTH_TRAINING': 'Силовая',
  'ELLIPTICAL': 'Эллипс',
  'ROWING': 'Гребля',
  'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
};

String workoutLabel(String t) => workoutNames[t] ?? t.replaceAll('_', ' ').toLowerCase();
