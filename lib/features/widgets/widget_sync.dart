import 'dart:async';
import 'dart:convert';

import 'package:pitanie_widgets/pitanie_widgets.dart';

import '../../core/dates.dart';
import '../../database/database.dart';
import '../dashboard/day_data.dart';

/// Настройка «Показывать данные в виджетах». По умолчанию выключена: данные о питании и воде
/// попадают на главный экран телефона только после явного согласия пользователя.
const kWidgetsEnabledKey = 'widgets_enabled';

bool widgetsEnabled(Map<String, String> settings) => settings[kWidgetsEnabledKey] == '1';

/// Снимок дня для виджетов. Если показ выключен, в снимке нет никаких данных о здоровье.
/// Рекламным и аналитическим SDK снимок не передаётся: он уходит только в хранилище виджета.
Map<String, dynamic> buildWidgetSnapshot(DayData d, {required bool enabled}) {
  if (!enabled) return {'enabled': false, 'day': d.key};
  return {
    'enabled': true,
    'day': d.key,
    'kcal': d.eaten.calories,
    'kcalGoal': d.calorieTarget,
    'p': d.eaten.proteins,
    'pGoal': d.goal.proteins,
    'f': d.eaten.fats,
    'fGoal': d.goal.fats,
    'c': d.eaten.carbs,
    'cGoal': d.goal.carbs,
    'water': d.plainWaterMl,
    'waterGoal': d.goal.waterMl,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

Timer? _debounce;

/// Передаёт виджетам актуальный снимок сегодняшнего дня. Вызовы подряд склеиваются, чтобы
/// не нагружать телефон; в тестах и на платформах без виджетов ничего не происходит.
void scheduleWidgetUpdate(AppDatabase db, {Duration delay = const Duration(seconds: 2)}) {
  _debounce?.cancel();
  _debounce = Timer(delay, () => pushWidgetsNow(db));
}

Future<bool> pushWidgetsNow(AppDatabase db) async {
  try {
    final enabled = widgetsEnabled(await db.allSettings());
    final d = await loadDayData(db, dayKey(DateTime.now()));
    return PitanieWidgets.update(jsonEncode(buildWidgetSnapshot(d, enabled: enabled)));
  } catch (_) {
    return false;
  }
}
