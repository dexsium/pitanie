import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/dates.dart';
import '../../database/database.dart';
import '../dashboard/day_data.dart';

class BackupCheck {
  final bool ok;
  final String message;
  final Map<String, dynamic>? data;
  const BackupCheck(this.ok, this.message, [this.data]);
}

/// Текущая версия формата резервной копии.
/// 1 — первые версии; 2 — добавлены версия схемы базы и число записей по таблицам.
/// Копии любого старого формата читаются: недостающие поля получают значения по умолчанию,
/// а при несовместимых изменениях формата добавляется шаг в [_migrations].
const kBackupFormat = 2;

/// Шаги переноса данных копии с формата N на N+1 (ключ — исходный формат).
/// Формат 1 → 2 не меняет данные, поэтому шаг пустой; новые поля строк дополняет [_defaults].
final Map<int, void Function(Map<String, dynamic> data)> _migrations = {
  1: (data) {},
};

/// Полная резервная копия в JSON с контрольной суммой SHA-256. В копию не попадают токены,
/// ключи доступа и секреты (они хранятся отдельно в защищённом хранилище, не в базе).
class BackupService {
  BackupService(this.db, {this.snapshotDir});
  final AppDatabase db;

  /// Папка для автоматических снимков перед восстановлением. Если не задана, снимок не делается.
  final String? snapshotDir;

  Future<List<Map<String, dynamic>>> _t<T extends Table, D>(TableInfo<T, D> t) async =>
      [for (final e in await db.select(t).get()) (e as dynamic).toJson() as Map<String, dynamic>];

  Future<Map<String, dynamic>> _collect() async => {
        'users': await _t(db.users),
        'products': await _t(db.products),
        'recipes': await _t(db.recipes),
        'recipeIngredients': await _t(db.recipeIngredients),
        'foodEntries': await _t(db.foodEntries),
        'waterEntries': await _t(db.waterEntries),
        'weightEntries': await _t(db.weightEntries),
        'activityRecords': await _t(db.activityRecords),
        'workouts': await _t(db.workouts),
        'dailyGoals': await _t(db.dailyGoals),
        'liftExercises': await _t(db.liftExercises),
        'liftSessions': await _t(db.liftSessions),
        'liftSets': await _t(db.liftSets),
        'liftTemplates': await _t(db.liftTemplates),
        'mealTemplates': await _t(db.mealTemplates),
        'mealTemplateItems': await _t(db.mealTemplateItems),
        'bodyMeasurements': await _t(db.bodyMeasurements),
        'trainingGoals': await _t(db.trainingGoals),
        'mealPlanItems': await _t(db.mealPlanItems),
        'shoppingItems': await _t(db.shoppingItems),
        'appSettings': await _t(db.appSettings),
      };

  static String _sum(Object data) => sha256.convert(utf8.encode(jsonEncode(data))).toString();

  Future<String> exportJson() async {
    final data = await _collect();
    return jsonEncode({
      'app': 'pitanie',
      'format': kBackupFormat,
      'schema': db.schemaVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'counts': {for (final e in data.entries) e.key: (e.value as List).length},
      'sha256': _sum(data),
      'data': data,
    });
  }

  /// Проверка файла до любых изменений данных: структура, версия формата, контрольная сумма,
  /// число записей. Возвращает данные уже приведёнными к текущему формату.
  static BackupCheck verify(String text) {
    try {
      final m = jsonDecode(text);
      if (m is! Map || m['app'] != 'pitanie' || m['data'] is! Map) {
        return const BackupCheck(false, 'Это не файл резервной копии приложения');
      }
      final format = m['format'];
      if (format is! int || format < 1) {
        return const BackupCheck(false, 'Неизвестная версия формата копии');
      }
      if (format > kBackupFormat) {
        return const BackupCheck(false,
            'Копия создана более новой версией приложения. Обновите приложение и повторите.');
      }
      if (_sum(m['data'] as Object) != m['sha256']) {
        return const BackupCheck(false, 'Контрольная сумма не совпала: файл повреждён');
      }
      final data = Map<String, dynamic>.from(m['data'] as Map);
      final counts = m['counts'];
      if (format >= 2 && counts is Map) {
        for (final e in counts.entries) {
          final rows = data[e.key];
          if (rows is! List || rows.length != e.value) {
            return BackupCheck(false, 'Число записей не совпало (${e.key}): файл повреждён');
          }
        }
      }
      for (var f = format; f < kBackupFormat; f++) {
        _migrations[f]?.call(data);
      }
      return BackupCheck(true, 'Файл корректен', data);
    } catch (e) {
      return BackupCheck(false, 'Не удалось прочитать файл: $e');
    }
  }

  /// Значения полей, появившихся после выпуска формата 1: копии старых версий их не содержат.
  static const _defaults = <String, Map<String, Object>>{
    'weightEntries': {'source': 'manual'},
    'activityRecords': {'platform': '', 'origin': ''},
  };

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> d, String k) =>
      ((d[k] ?? []) as List).map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        _defaults[k]?.forEach((f, v) => row.putIfAbsent(f, () => v));
        return row;
      }).toList();

  /// Снимок текущих данных перед восстановлением: если копия окажется не той, данные можно
  /// вернуть. Хранятся три последних снимка. Возвращает путь или null.
  Future<String?> _snapshot() async {
    final dir = snapshotDir;
    if (dir == null) return null;
    final d = Directory(dir)..createSync(recursive: true);
    final name = 'pre_restore_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File(p.join(d.path, name));
    await file.writeAsString(await exportJson());
    final old = d
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('pre_restore_'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(3)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    return file.path;
  }

  /// Заменяет все данные содержимым копии. Сначала файл полностью разбирается без изменения
  /// базы, затем делается снимок текущих данных, затем замена выполняется в одной транзакции:
  /// при любой ошибке прежние данные остаются как были.
  Future<void> restore(String text) async {
    final check = verify(text);
    if (!check.ok) throw FormatException(check.message);
    final d = check.data!;

    // Пробный разбор всех строк: битый файл не должен дойти до удаления данных.
    List<D> parse<D>(String k, D Function(Map<String, dynamic>) from) =>
        [for (final r in _rows(d, k)) from(r)];
    final users = parse('users', User.fromJson);
    final products = parse('products', Product.fromJson);
    final recipes = parse('recipes', Recipe.fromJson);
    final ingredients = parse('recipeIngredients', RecipeIngredient.fromJson);
    final foods = parse('foodEntries', FoodEntry.fromJson);
    final waters = parse('waterEntries', WaterEntry.fromJson);
    final weights = parse('weightEntries', WeightEntry.fromJson);
    final acts = parse('activityRecords', ActivityRecord.fromJson);
    final works = parse('workouts', Workout.fromJson);
    final goals = parse('dailyGoals', DailyGoal.fromJson);
    final settings = parse('appSettings', AppSetting.fromJson);
    // Копии старых версий не содержат дневник тренировок и шаблоны: тогда их не трогаем.
    final hasLift = d.containsKey('liftSets');
    final hasTemplates = d.containsKey('mealTemplates');
    final lifts = hasLift ? parse('liftExercises', LiftExercise.fromJson) : <LiftExercise>[];
    final liftSessions = hasLift ? parse('liftSessions', LiftSession.fromJson) : <LiftSession>[];
    final liftTemplates = hasLift ? parse('liftTemplates', LiftTemplate.fromJson) : <LiftTemplate>[];
    final liftSets = hasLift ? parse('liftSets', LiftSet.fromJson) : <LiftSet>[];
    final templates = hasTemplates ? parse('mealTemplates', MealTemplate.fromJson) : <MealTemplate>[];
    final templateItems =
        hasTemplates ? parse('mealTemplateItems', MealTemplateItem.fromJson) : <MealTemplateItem>[];

    final hasStage6 = d.containsKey('bodyMeasurements');
    final measures = hasStage6 ? parse('bodyMeasurements', BodyMeasurement.fromJson) : <BodyMeasurement>[];
    final tGoals = hasStage6 ? parse('trainingGoals', TrainingGoal.fromJson) : <TrainingGoal>[];
    final plan = hasStage6 ? parse('mealPlanItems', MealPlanItem.fromJson) : <MealPlanItem>[];
    final shop = hasStage6 ? parse('shoppingItems', ShoppingItem.fromJson) : <ShoppingItem>[];

    await _snapshot();

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
      if (hasLift) {
        await db.delete(db.liftSets).go();
        await db.delete(db.liftSessions).go();
        await db.delete(db.liftTemplates).go();
        await db.delete(db.liftExercises).go();
      }
      if (hasTemplates) {
        await db.delete(db.mealTemplateItems).go();
        await db.delete(db.mealTemplates).go();
      }
      if (hasStage6) {
        await db.delete(db.bodyMeasurements).go();
        await db.delete(db.trainingGoals).go();
        await db.delete(db.mealPlanItems).go();
        await db.delete(db.shoppingItems).go();
      }
      Future<void> put<T extends Table, D>(TableInfo<T, D> t, List<D> rows) async {
        for (final r in rows) {
          await db.into(t).insert(r as Insertable<D>, mode: InsertMode.insertOrReplace);
        }
      }

      await put(db.users, users);
      await put(db.products, products);
      await put(db.recipes, recipes);
      await put(db.recipeIngredients, ingredients);
      await put(db.foodEntries, foods);
      await put(db.waterEntries, waters);
      await put(db.weightEntries, weights);
      await put(db.activityRecords, acts);
      await put(db.workouts, works);
      await put(db.dailyGoals, goals);
      await put(db.appSettings, settings);
      if (hasStage6) {
        await put(db.bodyMeasurements, measures);
        await put(db.trainingGoals, tGoals);
        await put(db.mealPlanItems, plan);
        await put(db.shoppingItems, shop);
      }
      if (hasTemplates) {
        await put(db.mealTemplates, templates);
        await put(db.mealTemplateItems, templateItems);
      }
      if (hasLift) {
        await put(db.liftExercises, lifts);
        await put(db.liftSessions, liftSessions);
        await put(db.liftTemplates, liftTemplates);
        await put(db.liftSets, liftSets);
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
