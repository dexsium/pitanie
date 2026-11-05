import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../database/database.dart';
import '../dashboard/day_data.dart';

class BackupCheck {
  final bool ok;
  final String message;
  final Map<String, dynamic>? data;
  const BackupCheck(this.ok, this.message, [this.data]);
}

/// Полная резервная копия в JSON с контрольной суммой SHA-256.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  Future<Map<String, dynamic>> _collect() async => {
        'users': (await db.select(db.users).get()).map((e) => e.toJson()).toList(),
        'products': (await db.select(db.products).get()).map((e) => e.toJson()).toList(),
        'recipes': (await db.select(db.recipes).get()).map((e) => e.toJson()).toList(),
        'recipeIngredients':
            (await db.select(db.recipeIngredients).get()).map((e) => e.toJson()).toList(),
        'foodEntries': (await db.select(db.foodEntries).get()).map((e) => e.toJson()).toList(),
        'waterEntries': (await db.select(db.waterEntries).get()).map((e) => e.toJson()).toList(),
        'weightEntries':
            (await db.select(db.weightEntries).get()).map((e) => e.toJson()).toList(),
        'activityRecords':
            (await db.select(db.activityRecords).get()).map((e) => e.toJson()).toList(),
        'workouts': (await db.select(db.workouts).get()).map((e) => e.toJson()).toList(),
        'dailyGoals': (await db.select(db.dailyGoals).get()).map((e) => e.toJson()).toList(),
        'liftExercises':
            (await db.select(db.liftExercises).get()).map((e) => e.toJson()).toList(),
        'liftSessions': (await db.select(db.liftSessions).get()).map((e) => e.toJson()).toList(),
        'liftSets': (await db.select(db.liftSets).get()).map((e) => e.toJson()).toList(),
        'liftTemplates':
            (await db.select(db.liftTemplates).get()).map((e) => e.toJson()).toList(),
        'appSettings': (await db.select(db.appSettings).get()).map((e) => e.toJson()).toList(),
      };

  static String _sum(Object data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString();

  Future<String> exportJson() async {
    final data = await _collect();
    return jsonEncode({
      'app': 'pitanie',
      'format': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'sha256': _sum(data),
      'data': data,
    });
  }

  static BackupCheck verify(String text) {
    try {
      final m = jsonDecode(text);
      if (m is! Map || m['app'] != 'pitanie' || m['data'] is! Map) {
        return const BackupCheck(false, 'Это не файл резервной копии приложения');
      }
      if (m['format'] != 1) {
        return const BackupCheck(false, 'Неподдерживаемая версия формата');
      }
      if (_sum(m['data'] as Object) != m['sha256']) {
        return const BackupCheck(false, 'Контрольная сумма не совпала: файл повреждён');
      }
      return BackupCheck(true, 'Файл корректен', Map<String, dynamic>.from(m['data'] as Map));
    } catch (e) {
      return BackupCheck(false, 'Не удалось прочитать файл: $e');
    }
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> d, String k) =>
      ((d[k] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  /// Заменяет все данные содержимым копии. Выполняется в одной транзакции.
  Future<void> restore(String text) async {
    final check = verify(text);
    if (!check.ok) throw FormatException(check.message);
    final d = check.data!;
    await db.transaction(() async {
      await db.delete(db.recipeIngredients).go();
      await db.delete(db.recipes).go();
      await db.delete(db.products).go();
      await db.delete(db.users).go();
      await db.delete(db.foodEntries).go();
      await db.delete(db.waterEntries).go();
      await db.delete(db.weightEntries).go();
      await db.delete(db.activityRecords).go();
      await db.delete(db.workouts).go();
      await db.delete(db.dailyGoals).go();
      await db.delete(db.appSettings).go();
      // Копии старых версий не содержат дневник тренировок: тогда его не трогаем.
      final hasLift = d.containsKey('liftSets');
      if (hasLift) {
        await db.delete(db.liftSets).go();
        await db.delete(db.liftSessions).go();
        await db.delete(db.liftTemplates).go();
        await db.delete(db.liftExercises).go();
      }
      Future<void> put<T extends Table, D>(
          TableInfo<T, D> t, String k, D Function(Map<String, dynamic>) from) async {
        for (final r in _rows(d, k)) {
          await db.into(t).insert(from(r) as Insertable<D>, mode: InsertMode.insertOrReplace);
        }
      }

      await put(db.users, 'users', User.fromJson);
      await put(db.products, 'products', Product.fromJson);
      await put(db.recipes, 'recipes', Recipe.fromJson);
      await put(db.recipeIngredients, 'recipeIngredients', RecipeIngredient.fromJson);
      await put(db.foodEntries, 'foodEntries', FoodEntry.fromJson);
      await put(db.waterEntries, 'waterEntries', WaterEntry.fromJson);
      await put(db.weightEntries, 'weightEntries', WeightEntry.fromJson);
      await put(db.activityRecords, 'activityRecords', ActivityRecord.fromJson);
      await put(db.workouts, 'workouts', Workout.fromJson);
      await put(db.dailyGoals, 'dailyGoals', DailyGoal.fromJson);
      await put(db.appSettings, 'appSettings', AppSetting.fromJson);
      if (hasLift) {
        await put(db.liftExercises, 'liftExercises', LiftExercise.fromJson);
        await put(db.liftSessions, 'liftSessions', LiftSession.fromJson);
        await put(db.liftTemplates, 'liftTemplates', LiftTemplate.fromJson);
        await put(db.liftSets, 'liftSets', LiftSet.fromJson);
      }
    });
  }

  /// Статистика по дням в CSV (с BOM для корректного открытия в Excel).
  Future<String> exportCsv() async {
    final foods = await db.select(db.foodEntries).get();
    final today = dayStart(DateTime.now());
    var first = today;
    for (final f in foods) {
      final d = parseDayKey(f.date);
      if (d.isBefore(first)) first = d;
    }
    final stats = await computeRangeStats(db, dayKey(first), dayKey(today));
    final b = StringBuffer('﻿');
    b.writeln('Дата;Ккал;Белки г;Жиры г;Углеводы г;Вода мл;Шаги;Расстояние км;'
        'Активные ккал;Вес кг;Цель ккал');
    String n(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    for (final s in stats.values) {
      if (!s.hasFood && s.waterMl == 0 && !s.act.hasData && s.weight == null) continue;
      b.writeln([
        s.key,
        n(s.n.calories),
        n(s.n.proteins),
        n(s.n.fats),
        n(s.n.carbs),
        n(s.waterMl),
        s.act.steps.round(),
        n(s.act.distanceKm),
        n(s.act.activeKcal),
        s.weight == null ? '' : n(s.weight!),
        n(s.goal.calories),
      ].join(';'));
    }
    return b.toString();
  }
}
