import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/dates.dart';
import '../core/nutrition.dart';
import 'seed.dart';

part 'database.g.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sex => text().withDefault(const Constant('male'))();
  DateTimeColumn get birthDate => dateTime().nullable()();
  RealColumn get heightCm => real().nullable()();
  RealColumn get targetWeightKg => real().nullable()();
  TextColumn get goalType => text().withDefault(const Constant('maintain'))();
  TextColumn get activityLevel => text().withDefault(const Constant('light'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get brand => text().nullable()();
  TextColumn get searchKey => text().withDefault(const Constant(''))();
  TextColumn get category => text().withDefault(const Constant('Прочее'))();
  RealColumn get calories => real()();
  RealColumn get proteins => real()();
  RealColumn get fats => real()();
  RealColumn get carbohydrates => real()();
  // 'g' или 'ml': значения даны на 100 г или на 100 мл.
  TextColumn get measurementUnit => text().withDefault(const Constant('g'))();
  RealColumn get portionSize => real().nullable()();
  RealColumn get pieceWeight => real().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('Пользователь'))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(true))();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Каталог USDA (схема 2). verified = значение получено из официального справочника,
  // а не оценено; это не лабораторное подтверждение.
  TextColumn get nameEn => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('unknown'))();
  TextColumn get kind => text().withDefault(const Constant('food'))();
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  TextColumn get portionLabel => text().nullable()();
  // Когда карточка продукта последний раз создана или исправлена (schema 5).
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

/// Обхваты тела в сантиметрах (schema 5). kind: waist, chest, hips, arm, thigh или своё название.
class BodyMeasurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  DateTimeColumn get measuredAt => dateTime()();
  TextColumn get kind => text()();
  RealColumn get valueCm => real()();
}

/// Фото прогресса: только имя файла в закрытой папке приложения (schema 5).
class ProgressPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get takenAt => dateTime()();
  TextColumn get fileName => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// Нормы для тренировочных дней. Действуют с даты вступления в силу, как и DailyGoals;
/// enabled = false отключает отдельные нормы с этой даты (schema 5).
class TrainingGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get effectiveDate => text().unique()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  RealColumn get calories => real()();
  RealColumn get proteins => real()();
  RealColumn get fats => real()();
  RealColumn get carbohydrates => real()();
  RealColumn get waterMl => real()();
}

/// Планируемое питание. Хранится отдельно от дневника фактического питания (schema 5).
class MealPlanItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  TextColumn get mealType => text()();
  TextColumn get name => text()();
  IntColumn get productId => integer().nullable()();
  IntColumn get recipeId => integer().nullable()();
  RealColumn get amount => real().withDefault(const Constant(0))();
  TextColumn get amountUnit => text().withDefault(const Constant('g'))();
  RealColumn get displayQty => real().withDefault(const Constant(0))();
  TextColumn get displayUnit => text().withDefault(const Constant('g'))();
  RealColumn get caloriesSnapshot => real()();
  RealColumn get proteinsSnapshot => real()();
  RealColumn get fatsSnapshot => real()();
  RealColumn get carbohydratesSnapshot => real()();
  // Перенесено в дневник.
  BoolColumn get done => boolean().withDefault(const Constant(false))();
}

/// Список покупок на неделю (weekStart — день понедельника). manual: добавлено вручную (schema 5).
class ShoppingItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get weekStart => text()();
  TextColumn get name => text()();
  RealColumn get grams => real().withDefault(const Constant(0))();
  BoolColumn get checked => boolean().withDefault(const Constant(false))();
  BoolColumn get manual => boolean().withDefault(const Constant(false))();
}

/// Шаблон приёма пищи: набор позиций со снимком пищевой ценности (schema 5).
class MealTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class MealTemplateItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId =>
      integer().references(MealTemplates, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  IntColumn get productId => integer().nullable()();
  IntColumn get recipeId => integer().nullable()();
  RealColumn get amount => real().withDefault(const Constant(0))();
  TextColumn get amountUnit => text().withDefault(const Constant('g'))();
  RealColumn get displayQty => real().withDefault(const Constant(0))();
  TextColumn get displayUnit => text().withDefault(const Constant('g'))();
  RealColumn get caloriesSnapshot => real()();
  RealColumn get proteinsSnapshot => real()();
  RealColumn get fatsSnapshot => real()();
  RealColumn get carbohydratesSnapshot => real()();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
}

class Recipes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get cookedWeight => real().nullable()();
  IntColumn get servings => integer().withDefault(const Constant(1))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class RecipeIngredients extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get recipeId =>
      integer().references(Recipes, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  RealColumn get quantity => real()();
}

class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  DateTimeColumn get eatenAt => dateTime()();
  IntColumn get tzOffsetMin => integer().withDefault(const Constant(0))();
  TextColumn get mealType => text()();
  IntColumn get productId => integer().nullable()();
  IntColumn get recipeId => integer().nullable()();
  TextColumn get name => text()();
  // Количество в г или мл (основа расчёта).
  RealColumn get amount => real().withDefault(const Constant(0))();
  TextColumn get amountUnit => text().withDefault(const Constant('g'))();
  // Как ввёл пользователь (например 2 шт.).
  RealColumn get displayQty => real().withDefault(const Constant(0))();
  TextColumn get displayUnit => text().withDefault(const Constant('g'))();
  RealColumn get caloriesSnapshot => real()();
  RealColumn get proteinsSnapshot => real()();
  RealColumn get fatsSnapshot => real()();
  RealColumn get carbohydratesSnapshot => real()();
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
}

class WaterEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  DateTimeColumn get loggedAt => dateTime()();
  IntColumn get tzOffsetMin => integer().withDefault(const Constant(0))();
  RealColumn get volumeMl => real()();
  // 'water' учитывается в норме воды; остальные напитки отдельно.
  TextColumn get beverageType => text().withDefault(const Constant('water'))();
  // Связь с записью еды: калории напитка не дублируются.
  IntColumn get foodEntryId => integer().nullable()();
}

class WeightEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()();
  DateTimeColumn get measuredAt => dateTime()();
  RealColumn get weightKg => real()();
  // Импеданс (Ом) с умных весов: по нему считается состав тела. У ручных замеров его нет.
  RealColumn get impedance => real().nullable()();
  // Откуда запись: 'manual' (ввод и весы приложения) или 'health:<платформа>' (импорт из Здоровья).
  TextColumn get source => text().withDefault(const Constant('manual'))();
  // Идентификатор записи в Здоровье (для импорта: обновление и сверка удалений).
  TextColumn get externalId => text().nullable()();
  // Состав тела, пришедший вместе со взвешиванием (из Здоровья или с весов).
  RealColumn get bodyFatPct => real().nullable()();
  RealColumn get leanMassKg => real().nullable()();
  // Показатели, переданные весами (null — весы их не передали, значения не выдумываются).
  RealColumn get muscleMassKg => real().nullable()();
  RealColumn get bodyWaterKg => real().nullable()();
  RealColumn get bmrKcal => real().nullable()();
  // Драйвер весов: 'mi_scale2', 'gatt_standard'.
  TextColumn get scaleDriver => text().nullable()();
}

class ActivityRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  // steps, distance (м), activeEnergy (ккал), totalEnergy, heartRate, sleep (мин)
  TextColumn get type => text()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  IntColumn get tzOffsetMin => integer().withDefault(const Constant(0))();
  RealColumn get value => real()();
  TextColumn get unit => text()();
  TextColumn get source => text()();
  TextColumn get sourceName => text().withDefault(const Constant(''))();
  TextColumn get externalRecordId => text()();
  // Платформа импорта ('apple_health' / 'health_connect'; пусто — прежние записи).
  TextColumn get platform => text().withDefault(const Constant(''))();
  // Когда запись последний раз добавлена или обновлена в приложении.
  DateTimeColumn get modifiedAt => dateTime().nullable()();
  // Способ получения: 'automatic', 'manual', 'active' или 'unknown'.
  TextColumn get origin => text().withDefault(const Constant(''))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {type, source, externalRecordId}
      ];
}

class Workouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get source => text()();
  TextColumn get sourceName => text().withDefault(const Constant(''))();
  TextColumn get externalRecordId => text()();
  TextColumn get workoutType => text()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  RealColumn get energyKcal => real().nullable()();
  RealColumn get distanceM => real().nullable()();
  RealColumn get avgHr => real().nullable()();
  RealColumn get maxHr => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {source, externalRecordId}
      ];
}

/// Дневник силовых тренировок. Отдельно от `Workouts` (тренировки, пришедшие с часов).
class LiftExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  // weight — внешний вес (штанга, гантели, тренажёр); bodyweight — собственный вес,
  // дополнительное отягощение необязательно.
  TextColumn get kind => text().withDefault(const Constant('weight'))();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
}

class LiftSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationMin => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  // Сопоставление с тренировкой с часов (Workouts.id) при ручной привязке.
  IntColumn get watchWorkoutId => integer().nullable()();
}

class LiftSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(LiftSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(LiftExercises, #id)();
  IntColumn get position => integer()(); // порядок упражнения в тренировке
  IntColumn get setIndex => integer()();
  IntColumn get reps => integer()();
  RealColumn get weightKg => real().nullable()(); // рабочий или дополнительный вес
  IntColumn get restSec => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

class LiftTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get exerciseIds => text()(); // JSON-список id упражнений по порядку
}

class DailyGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get effectiveDate => text().unique()();
  RealColumn get calories => real()();
  RealColumn get proteins => real()();
  RealColumn get fats => real()();
  RealColumn get carbohydrates => real()();
  RealColumn get waterMl => real()();
}

class ConnectedSources extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceType => text().unique()();
  TextColumn get deviceName => text().withDefault(const Constant(''))();
  TextColumn get permissions => text().withDefault(const Constant(''))();
  DateTimeColumn get lastSync => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('not_connected'))();
  // JSON-отчёт последней синхронизации (типы, источники, ошибки).
  TextColumn get lastReport => text().nullable()();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  Users,
  Products,
  Recipes,
  RecipeIngredients,
  FoodEntries,
  WaterEntries,
  WeightEntries,
  ActivityRecords,
  Workouts,
  LiftExercises,
  LiftSessions,
  LiftSets,
  LiftTemplates,
  MealTemplates,
  MealTemplateItems,
  BodyMeasurements,
  ProgressPhotos,
  TrainingGoals,
  MealPlanItems,
  ShoppingItems,
  DailyGoals,
  ConnectedSources,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.memory() : super(NativeDatabase.memory());

  static AppDatabase open() => AppDatabase(LazyDatabase(() async {
        final dir = await getApplicationDocumentsDirectory();
        return NativeDatabase.createInBackground(
            File(p.join(dir.path, 'pitanie.sqlite')));
      }));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final s in const [
            'CREATE INDEX IF NOT EXISTS idx_food_date ON food_entries(date)',
            'CREATE INDEX IF NOT EXISTS idx_water_date ON water_entries(date)',
            'CREATE INDEX IF NOT EXISTS idx_weight_date ON weight_entries(date)',
            'CREATE INDEX IF NOT EXISTS idx_activity_time ON activity_records(start_time, end_time)',
            'CREATE INDEX IF NOT EXISTS idx_product_barcode ON products(barcode)',
          ]) {
            await customStatement(s);
          }
          await _ensureIndexes();
        },
        // При повышении schemaVersion добавляйте шаги вида
        //   if (from < 2) { await m.addColumn(table, table.newColumn); }
        // Данные пользователя никогда не удаляются при миграции.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Только добавление столбцов: данные пользователя не затрагиваются.
            await m.addColumn(products, products.nameEn);
            await m.addColumn(products, products.sourceId);
            await m.addColumn(products, products.state);
            await m.addColumn(products, products.kind);
            await m.addColumn(products, products.verified);
            await m.addColumn(products, products.portionLabel);
            await customStatement(
                'CREATE INDEX IF NOT EXISTS idx_product_source ON products(source, source_id)');
          }
          if (from < 3) {
            await m.addColumn(weightEntries, weightEntries.impedance);
          }
          if (from < 4) {
            // Только новые таблицы: существующие данные не затрагиваются.
            await m.createTable(liftExercises);
            await m.createTable(liftSessions);
            await m.createTable(liftSets);
            await m.createTable(liftTemplates);
          }
          if (from < 5) {
            // Только добавление столбцов со значениями по умолчанию: данные не затрагиваются.
            await m.addColumn(weightEntries, weightEntries.source);
            await m.addColumn(weightEntries, weightEntries.externalId);
            await m.addColumn(weightEntries, weightEntries.bodyFatPct);
            await m.addColumn(weightEntries, weightEntries.leanMassKg);
            await m.addColumn(weightEntries, weightEntries.muscleMassKg);
            await m.addColumn(weightEntries, weightEntries.bodyWaterKg);
            await m.addColumn(weightEntries, weightEntries.bmrKcal);
            await m.addColumn(weightEntries, weightEntries.scaleDriver);
            await m.addColumn(activityRecords, activityRecords.platform);
            await m.addColumn(activityRecords, activityRecords.modifiedAt);
            await m.addColumn(activityRecords, activityRecords.origin);
            await m.addColumn(products, products.updatedAt);
            await m.createTable(mealTemplates);
            await m.createTable(mealTemplateItems);
            await m.createTable(bodyMeasurements);
            await m.createTable(progressPhotos);
            await m.createTable(trainingGoals);
            await m.createTable(mealPlanItems);
            await m.createTable(shoppingItems);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _ensureIndexes();
          await seedProducts();
          await seedLiftExercises();
        },
      );

  /// Индексы для больших объёмов истории (запросы по продукту, типу данных и времени).
  Future<void> _ensureIndexes() async {
    for (final s in const [
      'CREATE INDEX IF NOT EXISTS idx_food_product ON food_entries(product_id)',
      'CREATE INDEX IF NOT EXISTS idx_food_meal_date ON food_entries(meal_type, date)',
      'CREATE INDEX IF NOT EXISTS idx_activity_type_time ON activity_records(type, start_time)',
      'CREATE INDEX IF NOT EXISTS idx_weight_time ON weight_entries(measured_at)',
      'CREATE INDEX IF NOT EXISTS idx_body_kind ON body_measurements(kind, measured_at)',
      'CREATE INDEX IF NOT EXISTS idx_plan_date ON meal_plan_items(date)',
      'CREATE INDEX IF NOT EXISTS idx_shop_week ON shopping_items(week_start)',
    ]) {
      await customStatement(s);
    }
  }

  /// Проверка целостности базы SQLite: пустой список означает, что проблем нет.
  Future<List<String>> integrityProblems() async {
    final out = <String>[];
    final ic = await customSelect('PRAGMA integrity_check').get();
    for (final r in ic) {
      final v = r.data.values.first.toString();
      if (v != 'ok') out.add(v);
    }
    final fk = await customSelect('PRAGMA foreign_key_check').get();
    for (final r in fk) {
      out.add('нарушена связь: ${r.data['table']} -> ${r.data['parent']}');
    }
    return out;
  }

  /// Удаляет все данные пользователя: дневник, воду, вес, активность, тренировки, цели, блюда,
  /// шаблоны, свои продукты, настройки и подключённые источники. Встроенный справочник остаётся,
  /// у его продуктов сбрасываются избранное и счётчик использования.
  Future<void> wipeUserData() => transaction(() async {
        for (final t in <TableInfo>[
          shoppingItems,
          mealPlanItems,
          trainingGoals,
          progressPhotos,
          bodyMeasurements,
          mealTemplateItems,
          mealTemplates,
          liftSets,
          liftSessions,
          liftTemplates,
          liftExercises,
          recipeIngredients,
          recipes,
          foodEntries,
          waterEntries,
          weightEntries,
          activityRecords,
          workouts,
          dailyGoals,
          connectedSources,
          appSettings,
          users,
        ]) {
          await delete(t).go();
        }
        await (delete(products)..where((t) => t.isCustom.equals(true))).go();
        await update(products).write(const ProductsCompanion(
            isFavorite: Value(false), useCount: Value(0), lastUsedAt: Value(null)));
      });

  /// Базовый список упражнений при первом запуске. Дальше пользователь правит его сам.
  Future<void> seedLiftExercises() async {
    if ((await allSettings())['lift_seed'] == '1') return;
    const base = <(String, String)>[
      ('Жим штанги лёжа', 'weight'),
      ('Жим гантелей лёжа', 'weight'),
      ('Жим стоя', 'weight'),
      ('Приседания со штангой', 'weight'),
      ('Становая тяга', 'weight'),
      ('Румынская тяга', 'weight'),
      ('Тяга штанги в наклоне', 'weight'),
      ('Тяга верхнего блока', 'weight'),
      ('Тяга гантели в наклоне', 'weight'),
      ('Жим ногами', 'weight'),
      ('Подъём на бицепс', 'weight'),
      ('Французский жим', 'weight'),
      ('Подтягивания', 'bodyweight'),
      ('Отжимания', 'bodyweight'),
      ('Отжимания на брусьях', 'bodyweight'),
      ('Выпады', 'bodyweight'),
      ('Планка (секунды в повторениях)', 'bodyweight'),
      ('Скручивания', 'bodyweight'),
    ];
    await batch((b) {
      for (final e in base) {
        b.insert(liftExercises,
            LiftExercisesCompanion.insert(name: e.$1, kind: Value(e.$2)));
      }
    });
    await setSetting('lift_seed', '1');
  }

  /// Добавляет недостающие справочные продукты (по имени). Выполняется один раз
  /// на версию каталога, существующие и удалённые пользователем записи не трогает.
  Future<void> seedProducts() async {
    final saved = (await allSettings())['seed_version'];
    if ((int.tryParse(saved ?? '') ?? 0) >= seedVersion) return;
    final existing = {
      for (final p in await (select(products)..where((t) => t.isCustom.equals(false))).get()) p.name
    };
    await batch((b) {
      for (final s in seedFoods) {
        if (existing.contains(s.name)) {
          // Продукт уже есть: добавляем вес штуки, если он не задан (значения пользователя не трогаем).
          if (s.piece != null) {
            b.update(products, ProductsCompanion(pieceWeight: Value(s.piece)),
                where: (t) =>
                    t.name.equals(s.name) & t.isCustom.equals(false) & t.pieceWeight.isNull());
          }
          continue;
        }
        b.insert(
            products,
            ProductsCompanion.insert(
              name: s.name,
              calories: s.kcal,
              proteins: s.p,
              fats: s.f,
              carbohydrates: s.c,
              searchKey: Value(s.name.toLowerCase()),
              category: Value(s.category),
              measurementUnit: Value(s.unit),
              pieceWeight: Value(s.piece),
              portionSize: Value(s.portion),
              source: const Value(seedSource),
              isCustom: const Value(false),
            ));
      }
    });
    await setSetting('seed_version', '$seedVersion');
  }

  // ---------- настройки ----------
  Stream<Map<String, String>> watchSettings() => select(appSettings)
      .watch()
      .map((rows) => {for (final r in rows) r.key: r.value});

  Future<Map<String, String>> allSettings() async =>
      {for (final r in await select(appSettings).get()) r.key: r.value};

  Future<void> setSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(key: Value(key), value: Value(value)));

  Future<void> removeSetting(String key) =>
      (delete(appSettings)..where((t) => t.key.equals(key))).go();

  // ---------- профиль и цели ----------
  Future<User?> getUser() => (select(users)..limit(1)).getSingleOrNull();
  Stream<User?> watchUser() => (select(users)..limit(1)).watchSingleOrNull();

  Future<void> saveUser(UsersCompanion c) async {
    final u = await getUser();
    if (u == null) {
      await into(users).insert(c);
    } else {
      await (update(users)..where((t) => t.id.equals(u.id))).write(c);
    }
  }

  Future<GoalValues> goalFor(String day) async {
    final g = await (select(dailyGoals)
          ..where((t) => t.effectiveDate.isSmallerOrEqualValue(day))
          ..orderBy([(t) => OrderingTerm.desc(t.effectiveDate)])
          ..limit(1))
        .getSingleOrNull();
    if (g == null) return GoalValues.fallback;
    return GoalValues(g.calories, g.proteins, g.fats, g.carbohydrates, g.waterMl);
  }

  Future<List<DailyGoal>> allGoals() => (select(dailyGoals)
        ..orderBy([(t) => OrderingTerm.asc(t.effectiveDate)]))
      .get();

  Future<void> setGoal(String effectiveDate, GoalValues g) {
    final c = DailyGoalsCompanion.insert(
      effectiveDate: effectiveDate,
      calories: g.calories,
      proteins: g.proteins,
      fats: g.fats,
      carbohydrates: g.carbs,
      waterMl: g.waterMl,
    );
    return into(dailyGoals).insert(c,
        onConflict: DoUpdate((_) => c, target: [dailyGoals.effectiveDate]));
  }

  // ---------- продукты ----------
  Stream<List<Product>> watchProducts({
    String query = '',
    String? category,
    bool favoritesOnly = false,
    bool recentOnly = false,
    String? state,
    String? kind,
    int limit = 120,
  }) {
    final q = select(products);
    q.where((t) {
      Expression<bool> e = const Constant(true);
      // Несколько слов запроса: каждое должно встречаться в названии (русском или английском).
      for (final w in query.trim().toLowerCase().split(RegExp(r'\s+'))) {
        if (w.isNotEmpty) e = e & t.searchKey.like('%$w%');
      }
      if (category != null) e = e & t.category.equals(category);
      if (state != null) e = e & t.state.equals(state);
      if (kind != null) e = e & t.kind.equals(kind);
      if (favoritesOnly) e = e & t.isFavorite.equals(true);
      if (recentOnly) e = e & t.lastUsedAt.isNotNull();
      return e;
    });
    q.orderBy(recentOnly
        ? [(t) => OrderingTerm.desc(t.lastUsedAt)]
        : [
            (t) => OrderingTerm.desc(t.useCount),
            (t) => OrderingTerm.desc(t.isCustom),
            (t) => OrderingTerm.asc(t.name.length),
            (t) => OrderingTerm.asc(t.name),
          ]);
    q.limit(limit);
    return q.watch();
  }

  /// Категории продуктов (не блюд), которые есть в базе: для фильтра.
  Future<List<String>> usedCategories() async {
    final rows = await customSelect(
            "SELECT category, COUNT(*) c FROM products WHERE kind = 'food' GROUP BY category ORDER BY c DESC",
            readsFrom: {products})
        .get();
    return [for (final r in rows) r.read<String>('category')];
  }

  Future<Product?> productById(int id) =>
      (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Product?> productByBarcode(String code) => (select(products)
        ..where((t) => t.barcode.equals(code))
        ..limit(1))
      .getSingleOrNull();

  ProductsCompanion _withKey(ProductsCompanion c) => !c.name.present
      ? c
      : c.copyWith(
      searchKey: Value(
          '${c.name.value} ${c.brand.value ?? ''}'.toLowerCase().trim()));

  Future<int> insertProduct(ProductsCompanion c) =>
      into(products).insert(_withKey(c).copyWith(updatedAt: Value(DateTime.now())));

  Future<void> updateProduct(int id, ProductsCompanion c) =>
      (update(products)..where((t) => t.id.equals(id)))
          .write(_withKey(c).copyWith(updatedAt: Value(DateTime.now())));

  static String _norm(String s) =>
      s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Продукт с тем же названием и производителем и практически той же пищевой ценностью
  /// (±1 ккал, ±0,5 г на 100 г). Товары с отличающимся составом дублями не считаются.
  Future<Product?> findSimilarProduct(
      {required String name,
      String? brand,
      required double kcal,
      required double p,
      required double f,
      required double c,
      int? excludeId}) async {
    final n = _norm(name), b = _norm(brand ?? '');
    final rows = await (select(products)
          ..where((t) => t.searchKey.like('%${n.replaceAll('%', '')}%'))
          ..limit(60))
        .get();
    for (final r in rows) {
      if (r.id == excludeId) continue;
      if (_norm(r.name) != n || _norm(r.brand ?? '') != b) continue;
      if ((r.calories - kcal).abs() <= 1 &&
          (r.proteins - p).abs() <= 0.5 &&
          (r.fats - f).abs() <= 0.5 &&
          (r.carbohydrates - c).abs() <= 0.5) {
        return r;
      }
    }
    return null;
  }

  Future<void> setFavorite(int id, bool v) => (update(products)
        ..where((t) => t.id.equals(id)))
      .write(ProductsCompanion(isFavorite: Value(v)));

  Future<void> touchProduct(int id) async {
    final pr = await productById(id);
    if (pr == null) return;
    await (update(products)..where((t) => t.id.equals(id))).write(
        ProductsCompanion(
            useCount: Value(pr.useCount + 1), lastUsedAt: Value(DateTime.now())));
  }

  /// Удаляет пользовательский продукт. Записи дневника сохраняют снимок.
  /// Возвращает false, если продукт используется в рецепте.
  Future<bool> deleteCustomProduct(int id) async {
    final used = await (select(recipeIngredients)
          ..where((t) => t.productId.equals(id))
          ..limit(1))
        .get();
    if (used.isNotEmpty) return false;
    await transaction(() async {
      await (update(foodEntries)..where((t) => t.productId.equals(id)))
          .write(const FoodEntriesCompanion(productId: Value(null)));
      await (delete(products)
            ..where((t) => t.id.equals(id) & t.isCustom.equals(true)))
          .go();
    });
    return true;
  }

  // ---------- рецепты ----------
  Stream<List<Recipe>> watchRecipes() => (select(recipes)
        ..orderBy([
          (t) => OrderingTerm.desc(t.isFavorite),
          (t) => OrderingTerm.asc(t.name),
        ]))
      .watch();

  Future<Recipe?> recipeById(int id) =>
      (select(recipes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<(RecipeIngredient, Product)>> ingredientsOf(int recipeId) async {
    final q = select(recipeIngredients).join([
      innerJoin(products, products.id.equalsExp(recipeIngredients.productId))
    ])
      ..where(recipeIngredients.recipeId.equals(recipeId))
      ..orderBy([OrderingTerm.asc(recipeIngredients.id)]);
    final rows = await q.get();
    return rows
        .map((r) => (r.readTable(recipeIngredients), r.readTable(products)))
        .toList();
  }

  Future<RecipeResult> recipeResult(int recipeId) async {
    final r = await recipeById(recipeId);
    final ing = await ingredientsOf(recipeId);
    return calcRecipe(
      ing
          .map((e) => RecipeLine(
              Nutrients(e.$2.calories, e.$2.proteins, e.$2.fats, e.$2.carbohydrates),
              e.$1.quantity))
          .toList(),
      cookedWeight: r?.cookedWeight,
      servings: r?.servings ?? 1,
    );
  }

  Future<int> saveRecipe({
    int? id,
    required String name,
    double? cookedWeight,
    required int servings,
    bool isFavorite = false,
    required List<({int productId, double quantity})> ingredients,
  }) {
    return transaction(() async {
      late int rid;
      final c = RecipesCompanion(
        name: Value(name),
        cookedWeight: Value(cookedWeight),
        servings: Value(servings),
        isFavorite: Value(isFavorite),
      );
      if (id == null) {
        rid = await into(recipes).insert(c);
      } else {
        rid = id;
        await (update(recipes)..where((t) => t.id.equals(id))).write(c);
        await (delete(recipeIngredients)..where((t) => t.recipeId.equals(id)))
            .go();
      }
      for (final i in ingredients) {
        await into(recipeIngredients).insert(RecipeIngredientsCompanion.insert(
            recipeId: rid, productId: i.productId, quantity: i.quantity));
      }
      return rid;
    });
  }

  Future<void> setRecipeFavorite(int id, bool v) => (update(recipes)
        ..where((t) => t.id.equals(id)))
      .write(RecipesCompanion(isFavorite: Value(v)));

  Future<int> copyRecipe(int id) async {
    final r = await recipeById(id);
    if (r == null) throw StateError('Рецепт не найден');
    final ing = await ingredientsOf(id);
    return saveRecipe(
      name: '${r.name} (копия)',
      cookedWeight: r.cookedWeight,
      servings: r.servings,
      ingredients:
          ing.map((e) => (productId: e.$2.id, quantity: e.$1.quantity)).toList(),
    );
  }

  Future<void> deleteRecipe(int id) => transaction(() async {
        await (delete(recipeIngredients)..where((t) => t.recipeId.equals(id)))
            .go();
        await (delete(recipes)..where((t) => t.id.equals(id))).go();
      });

  // ---------- питание ----------
  Future<List<FoodEntry>> foodForDay(String day) => (select(foodEntries)
        ..where((t) => t.date.equals(day))
        ..orderBy([(t) => OrderingTerm.asc(t.eatenAt)]))
      .get();

  Future<List<FoodEntry>> foodBetween(String from, String to) =>
      (select(foodEntries)
            ..where((t) =>
                t.date.isBiggerOrEqualValue(from) &
                t.date.isSmallerOrEqualValue(to)))
          .get();

  Future<int> addFood(FoodEntriesCompanion c) => into(foodEntries).insert(c);

  Future<void> deleteFood(int id) => transaction(() async {
        await (delete(waterEntries)..where((t) => t.foodEntryId.equals(id)))
            .go();
        await (delete(foodEntries)..where((t) => t.id.equals(id))).go();
      });

  /// Меняет количество; снимок пищевой ценности масштабируется пропорционально.
  Future<void> updateFoodAmount(FoodEntry e, double newAmount) async {
    if (e.amount <= 0 || newAmount <= 0) return;
    final k = newAmount / e.amount;
    await transaction(() async {
      await (update(foodEntries)..where((t) => t.id.equals(e.id))).write(
          FoodEntriesCompanion(
        amount: Value(newAmount),
        displayQty: Value(e.displayQty * k),
        caloriesSnapshot: Value(e.caloriesSnapshot * k),
        proteinsSnapshot: Value(e.proteinsSnapshot * k),
        fatsSnapshot: Value(e.fatsSnapshot * k),
        carbohydratesSnapshot: Value(e.carbohydratesSnapshot * k),
      ));
      await (update(waterEntries)..where((t) => t.foodEntryId.equals(e.id)))
          .write(WaterEntriesCompanion(volumeMl: Value(newAmount)));
    });
  }

  /// Правка записи дневника. Если задана масса, пищевая ценность масштабируется пропорционально
  /// (снимок сохраняется); у ручных записей значения можно задать напрямую.
  Future<void> updateFoodEntry(
    FoodEntry e, {
    String? mealType,
    double? amount,
    double? displayQty,
    String? displayUnit,
    String? name,
    double? kcal,
    double? p,
    double? f,
    double? c,
  }) async {
    var comp = FoodEntriesCompanion(
      mealType: mealType == null ? const Value.absent() : Value(mealType),
      name: name == null ? const Value.absent() : Value(name),
      displayUnit: displayUnit == null ? const Value.absent() : Value(displayUnit),
    );
    var rescaled = false;
    if (amount != null && amount > 0 && e.amount > 0) {
      final k = amount / e.amount;
      comp = comp.copyWith(
        amount: Value(amount),
        displayQty: Value(displayQty ?? e.displayQty * k),
        caloriesSnapshot: Value(e.caloriesSnapshot * k),
        proteinsSnapshot: Value(e.proteinsSnapshot * k),
        fatsSnapshot: Value(e.fatsSnapshot * k),
        carbohydratesSnapshot: Value(e.carbohydratesSnapshot * k),
      );
      rescaled = true;
    } else if (e.isManual && kcal != null) {
      comp = comp.copyWith(
        caloriesSnapshot: Value(kcal),
        proteinsSnapshot: Value(p ?? 0),
        fatsSnapshot: Value(f ?? 0),
        carbohydratesSnapshot: Value(c ?? 0),
      );
    }
    await transaction(() async {
      await (update(foodEntries)..where((t) => t.id.equals(e.id))).write(comp);
      if (rescaled) {
        await (update(waterEntries)..where((t) => t.foodEntryId.equals(e.id)))
            .write(WaterEntriesCompanion(volumeMl: Value(amount!)));
      }
    });
  }

  /// Копирует приём пищи с одного дня на другой.
  Future<int> copyMeal(String fromDay, String toDay, String meal) async {
    final src = (await foodForDay(fromDay)).where((e) => e.mealType == meal);
    var n = 0;
    final now = DateTime.now();
    for (final e in src) {
      await into(foodEntries).insert(FoodEntriesCompanion.insert(
        date: toDay,
        eatenAt: now,
        mealType: meal,
        name: e.name,
        caloriesSnapshot: e.caloriesSnapshot,
        proteinsSnapshot: e.proteinsSnapshot,
        fatsSnapshot: e.fatsSnapshot,
        carbohydratesSnapshot: e.carbohydratesSnapshot,
        tzOffsetMin: Value(tzOffsetMinutes(now)),
        productId: Value(e.productId),
        recipeId: Value(e.recipeId),
        amount: Value(e.amount),
        amountUnit: Value(e.amountUnit),
        displayQty: Value(e.displayQty),
        displayUnit: Value(e.displayUnit),
        isManual: Value(e.isManual),
      ));
      n++;
    }
    return n;
  }

  /// Копирует все приёмы пищи одного дня в другой. Возвращает число записей.
  Future<int> copyDay(String fromDay, String toDay) async {
    if (fromDay == toDay) return 0;
    var n = 0;
    for (final m in ['breakfast', 'lunch', 'dinner', 'snack']) {
      n += await copyMeal(fromDay, toDay, m);
    }
    return n;
  }

  /// День, в который [meal] последний раз записывался раньше [beforeDay]; null, если не было.
  Future<String?> lastMealDay(String meal, String beforeDay) async {
    final row = await (select(foodEntries)
          ..where((t) => t.mealType.equals(meal) & t.date.isSmallerThanValue(beforeDay))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(1))
        .getSingleOrNull();
    return row?.date;
  }

  /// Повторяет последний записанный раньше приём пищи этого типа. Возвращает число записей.
  Future<int> repeatLastMeal(String toDay, String meal) async {
    final from = await lastMealDay(meal, toDay);
    if (from == null) return 0;
    return copyMeal(from, toDay, meal);
  }

  // ---------- гибкие нормы: тренировочные дни ----------
  Future<void> setTrainingGoal(String effectiveDate, GoalValues g, {bool enabled = true}) {
    final c = TrainingGoalsCompanion.insert(
      effectiveDate: effectiveDate,
      enabled: Value(enabled),
      calories: g.calories,
      proteins: g.proteins,
      fats: g.fats,
      carbohydrates: g.carbs,
      waterMl: g.waterMl,
    );
    return into(trainingGoals).insertOnConflictUpdate(c);
  }

  /// Нормы тренировочных дней, действовавшие в [day]; null, если не заданы или отключены.
  Future<GoalValues?> trainingGoalFor(String day) async {
    final g = await (select(trainingGoals)
          ..where((t) => t.effectiveDate.isSmallerOrEqualValue(day))
          ..orderBy([(t) => OrderingTerm.desc(t.effectiveDate)])
          ..limit(1))
        .getSingleOrNull();
    if (g == null || !g.enabled) return null;
    return GoalValues(g.calories, g.proteins, g.fats, g.carbohydrates, g.waterMl);
  }

  Future<List<TrainingGoal>> allTrainingGoals() => (select(trainingGoals)
        ..orderBy([(t) => OrderingTerm.asc(t.effectiveDate)]))
      .get();

  /// В этот день была тренировка: с часов (Здоровье) или записанная в дневнике тренировок.
  Future<bool> isTrainingDay(String day) async {
    final d = parseDayKey(day);
    final from = dayStart(d), to = dayEnd(d);
    final w = await (select(workouts)
          ..where((t) => t.startTime.isBiggerOrEqualValue(from) & t.startTime.isSmallerThanValue(to))
          ..limit(1))
        .get();
    if (w.isNotEmpty) return true;
    final l = await (select(liftSessions)
          ..where((t) => t.startedAt.isBiggerOrEqualValue(from) & t.startedAt.isSmallerThanValue(to))
          ..limit(1))
        .get();
    return l.isNotEmpty;
  }

  Future<List<LiftSession>> liftSessionsBetween(DateTime from, DateTime to) =>
      (select(liftSessions)
            ..where((t) => t.startedAt.isBiggerOrEqualValue(from) & t.startedAt.isSmallerThanValue(to)))
          .get();

  /// Норма дня с учётом типа дня: для тренировочного дня берутся нормы тренировочных дней,
  /// если они заданы и включены, иначе обычные. Прошлые дни не меняются при новой цели.
  Future<GoalValues> goalForDay(String day) async {
    final base = await goalFor(day);
    final tg = await trainingGoalFor(day);
    if (tg == null) return base;
    return await isTrainingDay(day) ? tg : base;
  }

  // ---------- обхваты тела и фото прогресса ----------
  Future<int> addBodyMeasure(String kind, double cm, DateTime at) =>
      into(bodyMeasurements).insert(BodyMeasurementsCompanion.insert(
          date: dayKey(at), measuredAt: at, kind: kind.trim(), valueCm: cm));

  Stream<List<BodyMeasurement>> watchBodyMeasures() => (select(bodyMeasurements)
        ..orderBy([(t) => OrderingTerm.asc(t.measuredAt)]))
      .watch();

  Future<void> deleteBodyMeasure(int id) =>
      (delete(bodyMeasurements)..where((t) => t.id.equals(id))).go();

  Future<int> addProgressPhoto(String fileName, DateTime at, {String note = ''}) =>
      into(progressPhotos).insert(
          ProgressPhotosCompanion.insert(takenAt: at, fileName: fileName, note: Value(note)));

  Stream<List<ProgressPhoto>> watchProgressPhotos() => (select(progressPhotos)
        ..orderBy([(t) => OrderingTerm.desc(t.takenAt)]))
      .watch();

  Future<List<ProgressPhoto>> allProgressPhotos() => select(progressPhotos).get();

  /// Удаляет запись о фото и возвращает имя файла, который нужно удалить с диска.
  Future<String?> deleteProgressPhoto(int id) async {
    final p = await (select(progressPhotos)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (p == null) return null;
    await (delete(progressPhotos)..where((t) => t.id.equals(id))).go();
    return p.fileName;
  }

  // ---------- планировщик питания ----------
  Future<int> addPlanItem(MealPlanItemsCompanion c) => into(mealPlanItems).insert(c);

  Stream<List<MealPlanItem>> watchPlan(String fromDay, String toDay) =>
      (select(mealPlanItems)
            ..where((t) => t.date.isBiggerOrEqualValue(fromDay) & t.date.isSmallerOrEqualValue(toDay))
            ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
          .watch();

  Future<List<MealPlanItem>> planBetween(String fromDay, String toDay) =>
      (select(mealPlanItems)
            ..where((t) => t.date.isBiggerOrEqualValue(fromDay) & t.date.isSmallerOrEqualValue(toDay))
            ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
          .get();

  Future<void> deletePlanItem(int id) =>
      (delete(mealPlanItems)..where((t) => t.id.equals(id))).go();

  Future<void> clearPlanDay(String day) =>
      (delete(mealPlanItems)..where((t) => t.date.equals(day))).go();

  /// Копирует план одного дня в другой (отметки «перенесено» не копируются).
  Future<int> copyPlanDay(String fromDay, String toDay) async {
    if (fromDay == toDay) return 0;
    final src = await planBetween(fromDay, fromDay);
    for (final i in src) {
      await into(mealPlanItems).insert(MealPlanItemsCompanion.insert(
        date: toDay,
        mealType: i.mealType,
        name: i.name,
        caloriesSnapshot: i.caloriesSnapshot,
        proteinsSnapshot: i.proteinsSnapshot,
        fatsSnapshot: i.fatsSnapshot,
        carbohydratesSnapshot: i.carbohydratesSnapshot,
        productId: Value(i.productId),
        recipeId: Value(i.recipeId),
        amount: Value(i.amount),
        amountUnit: Value(i.amountUnit),
        displayQty: Value(i.displayQty),
        displayUnit: Value(i.displayUnit),
      ));
    }
    return src.length;
  }

  /// Переносит запланированную позицию в дневник фактического питания (в тот же день и приём
  /// пищи) и отмечает её выполненной. План и дневник остаются раздельными записями.
  Future<bool> transferPlanItemToDiary(int id) async {
    final i = await (select(mealPlanItems)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (i == null || i.done) return false;
    final now = DateTime.now();
    final d = parseDayKey(i.date);
    await into(foodEntries).insert(FoodEntriesCompanion.insert(
      date: i.date,
      eatenAt: DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second),
      mealType: i.mealType,
      name: i.name,
      caloriesSnapshot: i.caloriesSnapshot,
      proteinsSnapshot: i.proteinsSnapshot,
      fatsSnapshot: i.fatsSnapshot,
      carbohydratesSnapshot: i.carbohydratesSnapshot,
      tzOffsetMin: Value(tzOffsetMinutes(now)),
      productId: Value(i.productId),
      recipeId: Value(i.recipeId),
      amount: Value(i.amount),
      amountUnit: Value(i.amountUnit),
      displayQty: Value(i.displayQty),
      displayUnit: Value(i.displayUnit),
    ));
    await (update(mealPlanItems)..where((t) => t.id.equals(id)))
        .write(const MealPlanItemsCompanion(done: Value(true)));
    return true;
  }

  // ---------- список покупок ----------
  Stream<List<ShoppingItem>> watchShopping(String weekStart) => (select(shoppingItems)
        ..where((t) => t.weekStart.equals(weekStart))
        ..orderBy([(t) => OrderingTerm.asc(t.checked), (t) => OrderingTerm.asc(t.name)]))
      .watch();

  Future<void> toggleShopping(int id, bool checked) =>
      (update(shoppingItems)..where((t) => t.id.equals(id)))
          .write(ShoppingItemsCompanion(checked: Value(checked)));

  Future<void> deleteShopping(int id) =>
      (delete(shoppingItems)..where((t) => t.id.equals(id))).go();

  Future<void> addManualShopping(String weekStart, String name) =>
      into(shoppingItems).insert(ShoppingItemsCompanion.insert(
          weekStart: weekStart, name: name.trim(), manual: const Value(true)));

  /// Список покупок по плану недели: ингредиенты блюд и продукты, суммированные по продукту.
  /// Позиции без состава (быстрые записи) в список не попадают. Отметки «куплено» сохраняются
  /// для тех же названий, ручные позиции не трогаются.
  Future<int> buildShoppingList(String weekStart) async {
    final from = weekStart;
    final to = dayKey(parseDayKey(weekStart).add(const Duration(days: 6)));
    final items = await planBetween(from, to);
    final need = <String, double>{};
    void add(String name, double g) => need[name] = (need[name] ?? 0) + g;
    for (final i in items) {
      if (i.recipeId != null) {
        final r = await recipeById(i.recipeId!);
        if (r == null) continue;
        final res = await recipeResult(r.id);
        final factor = i.displayUnit == 'portion'
            ? i.displayQty / (r.servings <= 0 ? 1 : r.servings)
            : (res.finalWeight <= 0 ? 0.0 : i.amount / res.finalWeight);
        for (final ing in await ingredientsOf(r.id)) {
          add(ing.$2.name, ing.$1.quantity * factor);
        }
      } else if (i.productId != null && i.amount > 0) {
        final pr = await productById(i.productId!);
        if (pr != null) add(pr.name, i.amount);
      }
    }
    final old = await (select(shoppingItems)..where((t) => t.weekStart.equals(weekStart))).get();
    final checked = {for (final o in old) if (!o.manual && o.checked) o.name};
    await (delete(shoppingItems)
          ..where((t) => t.weekStart.equals(weekStart) & t.manual.equals(false)))
        .go();
    for (final e in need.entries) {
      await into(shoppingItems).insert(ShoppingItemsCompanion.insert(
          weekStart: weekStart,
          name: e.key,
          grams: Value(double.parse(e.value.toStringAsFixed(0))),
          checked: Value(checked.contains(e.key))));
    }
    return need.length;
  }

  // ---------- шаблоны приёмов пищи ----------
  /// Сохраняет приём пищи дня как шаблон. Возвращает id или null, если записей нет.
  Future<int?> saveMealTemplate(String day, String meal, String name) async {
    final src = (await foodForDay(day)).where((e) => e.mealType == meal).toList();
    if (src.isEmpty) return null;
    final id = await into(mealTemplates).insert(MealTemplatesCompanion.insert(
        name: name.trim().isEmpty ? 'Шаблон' : name.trim()));
    for (final e in src) {
      await into(mealTemplateItems).insert(MealTemplateItemsCompanion.insert(
        templateId: id,
        name: e.name,
        caloriesSnapshot: e.caloriesSnapshot,
        proteinsSnapshot: e.proteinsSnapshot,
        fatsSnapshot: e.fatsSnapshot,
        carbohydratesSnapshot: e.carbohydratesSnapshot,
        productId: Value(e.productId),
        recipeId: Value(e.recipeId),
        amount: Value(e.amount),
        amountUnit: Value(e.amountUnit),
        displayQty: Value(e.displayQty),
        displayUnit: Value(e.displayUnit),
        isManual: Value(e.isManual),
      ));
    }
    return id;
  }

  Stream<List<MealTemplate>> watchMealTemplates() => (select(mealTemplates)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<List<MealTemplateItem>> templateItems(int templateId) =>
      (select(mealTemplateItems)..where((t) => t.templateId.equals(templateId))).get();

  Future<void> deleteMealTemplate(int id) => transaction(() async {
        await (delete(mealTemplateItems)..where((t) => t.templateId.equals(id))).go();
        await (delete(mealTemplates)..where((t) => t.id.equals(id))).go();
      });

  /// Добавляет позиции шаблона в приём пищи дня (со снимком из шаблона).
  Future<int> applyMealTemplate(int id, String toDay, String meal) async {
    final items = await templateItems(id);
    final now = DateTime.now();
    for (final i in items) {
      await into(foodEntries).insert(FoodEntriesCompanion.insert(
        date: toDay,
        eatenAt: now,
        mealType: meal,
        name: i.name,
        caloriesSnapshot: i.caloriesSnapshot,
        proteinsSnapshot: i.proteinsSnapshot,
        fatsSnapshot: i.fatsSnapshot,
        carbohydratesSnapshot: i.carbohydratesSnapshot,
        tzOffsetMin: Value(tzOffsetMinutes(now)),
        productId: Value(i.productId),
        recipeId: Value(i.recipeId),
        amount: Value(i.amount),
        amountUnit: Value(i.amountUnit),
        displayQty: Value(i.displayQty),
        displayUnit: Value(i.displayUnit),
        isManual: Value(i.isManual),
      ));
    }
    return items.length;
  }

  /// Самые частые порции продукта: количество, единица и сколько раз выбиралась.
  Future<List<({double qty, String unit, int count})>> frequentPortions(int productId,
      {int limit = 3}) async {
    final rows = await customSelect(
        'SELECT display_qty q, display_unit u, COUNT(*) c, MAX(eaten_at) last '
        'FROM food_entries WHERE product_id = ? AND is_manual = 0 AND display_qty > 0 '
        'GROUP BY display_qty, display_unit ORDER BY c DESC, last DESC LIMIT ?',
        variables: [Variable<int>(productId), Variable<int>(limit)],
        readsFrom: {foodEntries}).get();
    return [
      for (final r in rows)
        (qty: r.read<double>('q'), unit: r.read<String>('u'), count: r.read<int>('c'))
    ];
  }

  // ---------- вода ----------
  Future<List<WaterEntry>> waterForDay(String day) => (select(waterEntries)
        ..where((t) => t.date.equals(day))
        ..orderBy([(t) => OrderingTerm.desc(t.loggedAt)]))
      .get();

  Future<List<WaterEntry>> waterBetween(String from, String to) =>
      (select(waterEntries)
            ..where((t) =>
                t.date.isBiggerOrEqualValue(from) &
                t.date.isSmallerOrEqualValue(to)))
          .get();

  Future<int> addWater(String day, double ml,
      {String type = 'water', DateTime? at, int? foodEntryId}) {
    final t = at ?? DateTime.now();
    return into(waterEntries).insert(WaterEntriesCompanion.insert(
      date: day,
      loggedAt: t,
      volumeMl: ml,
      tzOffsetMin: Value(tzOffsetMinutes(t)),
      beverageType: Value(type),
      foodEntryId: Value(foodEntryId),
    ));
  }

  Future<void> updateWater(int id, double ml, String type) =>
      (update(waterEntries)..where((t) => t.id.equals(id))).write(
          WaterEntriesCompanion(volumeMl: Value(ml), beverageType: Value(type)));

  Future<void> deleteWater(int id) =>
      (delete(waterEntries)..where((t) => t.id.equals(id))).go();

  // ---------- вес ----------
  Stream<List<WeightEntry>> watchWeights() => (select(weightEntries)
        ..orderBy([(t) => OrderingTerm.asc(t.measuredAt)]))
      .watch();

  Future<WeightEntry> weightById(int id) =>
      (select(weightEntries)..where((t) => t.id.equals(id))).getSingle();

  Future<List<WeightEntry>> allWeights() => (select(weightEntries)
        ..orderBy([(t) => OrderingTerm.asc(t.measuredAt)]))
      .get();

  Future<int> addWeight(DateTime at, double kg, {double? impedance}) =>
      into(weightEntries).insert(WeightEntriesCompanion.insert(
          date: dayKey(at),
          measuredAt: at,
          weightKg: kg,
          impedance: Value(impedance)));

  /// Импорт взвешивания из Здоровья. Возвращает 'added', 'updated' или 'duplicate'.
  /// Запись, совпавшая по времени (±10 мин) и массе (±0,3 кг) с уже имеющейся, не добавляется.
  Future<String> importWeight(
      {required String platform,
      required String externalId,
      required DateTime at,
      required double kg}) async {
    final tag = 'health:$platform';
    final same = await (select(weightEntries)
          ..where((t) => t.source.equals(tag) & t.externalId.equals(externalId)))
        .getSingleOrNull();
    if (same != null) {
      await (update(weightEntries)..where((t) => t.id.equals(same.id))).write(
          WeightEntriesCompanion(
              date: Value(dayKey(at)), measuredAt: Value(at), weightKg: Value(kg)));
      return 'updated';
    }
    const win = Duration(minutes: 10);
    final near = await (select(weightEntries)
          ..where((t) =>
              t.measuredAt.isBiggerOrEqualValue(at.subtract(win)) &
              t.measuredAt.isSmallerOrEqualValue(at.add(win))))
        .get();
    if (near.any((e) => (e.weightKg - kg).abs() <= 0.3)) return 'duplicate';
    await into(weightEntries).insert(WeightEntriesCompanion.insert(
        date: dayKey(at),
        measuredAt: at,
        weightKg: kg,
        source: Value(tag),
        externalId: Value(externalId)));
    return 'added';
  }

  /// Записывает жир и безжировую массу во взвешивание, ближайшее по времени (±15 мин).
  Future<void> attachBodyComposition(DateTime at, {double? fatPct, double? leanKg}) async {
    const win = Duration(minutes: 15);
    final near = await (select(weightEntries)
          ..where((t) =>
              t.measuredAt.isBiggerOrEqualValue(at.subtract(win)) &
              t.measuredAt.isSmallerOrEqualValue(at.add(win))))
        .get();
    if (near.isEmpty) return;
    near.sort((a, b) => a.measuredAt
        .difference(at)
        .abs()
        .compareTo(b.measuredAt.difference(at).abs()));
    final w = near.first;
    await (update(weightEntries)..where((t) => t.id.equals(w.id))).write(
        WeightEntriesCompanion(
            bodyFatPct: fatPct != null ? Value(fatPct) : const Value.absent(),
            leanMassKg: leanKg != null ? Value(leanKg) : const Value.absent()));
  }

  /// Удаляет импортированные взвешивания, которых больше нет в источнике (сверка окна).
  Future<int> deleteImportedWeightsMissing(
      String platform, DateTime from, Set<String> keepIds) async {
    final tag = 'health:$platform';
    final rows = await (select(weightEntries)
          ..where((t) => t.source.equals(tag) & t.measuredAt.isBiggerOrEqualValue(from)))
        .get();
    final gone = [for (final r in rows) if (!keepIds.contains(r.externalId)) r.id];
    if (gone.isEmpty) return 0;
    return (delete(weightEntries)..where((t) => t.id.isIn(gone))).go();
  }

  /// Удаляет записи активности платформы, которых больше нет в источнике (сверка окна).
  Future<int> deleteActivityMissing(
      String platform, String type, DateTime from, Set<String> keepIds) async {
    // Только id и внешний id (без загрузки целых записей): для плотных данных это тысячи строк.
    final rows = await (selectOnly(activityRecords)
          ..addColumns([activityRecords.id, activityRecords.externalRecordId])
          ..where(activityRecords.platform.equals(platform) &
              activityRecords.type.equals(type) &
              activityRecords.startTime.isBiggerOrEqualValue(from)))
        .get();
    final gone = [
      for (final r in rows)
        if (!keepIds.contains(r.read(activityRecords.externalRecordId)))
          r.read(activityRecords.id)!
    ];
    if (gone.isEmpty) return 0;
    var n = 0;
    for (var i = 0; i < gone.length; i += 500) {
      final part = gone.sublist(i, i + 500 > gone.length ? gone.length : i + 500);
      n += await (delete(activityRecords)..where((t) => t.id.isIn(part))).go();
    }
    return n;
  }

  /// Взвешивание с весов приложения. Если то же измерение уже пришло из Здоровья
  /// (±10 мин, ±0,3 кг), оно дополняется данными весов вместо добавления дубля.
  /// Показатели состава записываются только те, что весы действительно передали.
  Future<int> saveScaleWeight(DateTime at, double kg,
      {double? impedance,
      double? bodyFatPct,
      double? fatFreeKg,
      double? muscleKg,
      double? waterKg,
      double? bmrKcal,
      String? driver}) async {
    WeightEntriesCompanion extra() => WeightEntriesCompanion(
          impedance: impedance != null ? Value(impedance) : const Value.absent(),
          bodyFatPct: bodyFatPct != null ? Value(bodyFatPct) : const Value.absent(),
          leanMassKg: fatFreeKg != null ? Value(fatFreeKg) : const Value.absent(),
          muscleMassKg: muscleKg != null ? Value(muscleKg) : const Value.absent(),
          bodyWaterKg: waterKg != null ? Value(waterKg) : const Value.absent(),
          bmrKcal: bmrKcal != null ? Value(bmrKcal) : const Value.absent(),
          scaleDriver: driver != null ? Value(driver) : const Value.absent(),
        );
    const win = Duration(minutes: 10);
    final near = await (select(weightEntries)
          ..where((t) =>
              t.source.like('health:%') &
              t.measuredAt.isBiggerOrEqualValue(at.subtract(win)) &
              t.measuredAt.isSmallerOrEqualValue(at.add(win))))
        .get();
    for (final e in near) {
      if ((e.weightKg - kg).abs() <= 0.3) {
        await (update(weightEntries)..where((t) => t.id.equals(e.id))).write(extra());
        return e.id;
      }
    }
    final id = await addWeight(at, kg, impedance: impedance);
    await (update(weightEntries)..where((t) => t.id.equals(id))).write(extra());
    return id;
  }

  Future<void> updateWeight(int id, DateTime at, double kg) =>
      (update(weightEntries)..where((t) => t.id.equals(id))).write(
          WeightEntriesCompanion(
              date: Value(dayKey(at)), measuredAt: Value(at), weightKg: Value(kg)));

  Future<void> deleteWeight(int id) =>
      (delete(weightEntries)..where((t) => t.id.equals(id))).go();

  // ---------- активность ----------
  Future<void> upsertActivity(List<ActivityRecordsCompanion> list) async {
    await batch((b) {
      for (final c in list) {
        b.insert(activityRecords, c,
            onConflict: DoUpdate((_) => c, target: [
              activityRecords.type,
              activityRecords.source,
              activityRecords.externalRecordId
            ]));
      }
    });
  }

  /// Удаляет сохранённые фазы сна с часов (глубокий, быстрый, лёгкий) начиная с [since]:
  /// после смены порогов они записываются заново.
  Future<void> deleteBleSleepStages(DateTime since) =>
      (delete(activityRecords)
            ..where((t) =>
                t.source.equals('amazfit_ble') &
                t.type.isIn(['sleepDeep', 'sleepRem', 'sleepLight']) &
                t.startTime.isBiggerOrEqualValue(since)))
          .go();

  Future<void> upsertWorkouts(List<WorkoutsCompanion> list) async {
    await batch((b) {
      for (final c in list) {
        b.insert(workouts, c,
            onConflict: DoUpdate((_) => c,
                target: [workouts.source, workouts.externalRecordId]));
      }
    });
  }

  /// Записи нужных типов за период (без загрузки остальных).
  Future<List<ActivityRecord>> activityOfTypesBetween(
          List<String> types, DateTime from, DateTime to) =>
      (select(activityRecords)
            ..where((t) =>
                t.type.isIn(types) &
                t.endTime.isBiggerOrEqualValue(from) &
                t.startTime.isSmallerOrEqualValue(to)))
          .get();

  Future<List<ActivityRecord>> activityBetween(DateTime from, DateTime to) =>
      (select(activityRecords)
            ..where((t) =>
                t.endTime.isBiggerOrEqualValue(from) &
                t.startTime.isSmallerOrEqualValue(to)))
          .get();

  /// Записи сна (и фаз) за период; без шагов и пульса. Без [source] — из всех источников.
  Future<List<ActivityRecord>> sleepRecordsBetween(DateTime from, DateTime to,
          {String? source, bool stages = true}) =>
      (select(activityRecords)
            ..where((t) =>
                (source == null ? const Constant(true) : t.source.equals(source)) &
                t.startTime.isBiggerOrEqualValue(from) &
                t.startTime.isSmallerThanValue(to) &
                (stages
                    ? t.type.isIn(['sleep', 'sleepDeep', 'sleepRem', 'sleepLight'])
                    : t.type.equals('sleep'))))
          .get();

  Future<List<Workout>> workoutsBetween(DateTime from, DateTime to) =>
      (select(workouts)
            ..where((t) =>
                t.endTime.isBiggerOrEqualValue(from) &
                t.startTime.isSmallerOrEqualValue(to))
            ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
          .get();

  // ---------- источники здоровья ----------
  Future<ConnectedSource?> getSource(String type) => (select(connectedSources)
        ..where((t) => t.sourceType.equals(type)))
      .getSingleOrNull();

  Stream<ConnectedSource?> watchSource(String type) => (select(connectedSources)
        ..where((t) => t.sourceType.equals(type)))
      .watchSingleOrNull();

  Future<void> saveSource(String type, ConnectedSourcesCompanion c) async {
    final s = await getSource(type);
    if (s == null) {
      await into(connectedSources)
          .insert(c.copyWith(sourceType: Value(type)));
    } else {
      await (update(connectedSources)..where((t) => t.id.equals(s.id))).write(c);
    }
  }

  Future<void> deleteSource(String type) =>
      (delete(connectedSources)..where((t) => t.sourceType.equals(type))).go();
}

/// Поток, пересчитываемый при любом изменении таблиц БД.
Stream<T> reactive<T>(AppDatabase db, Future<T> Function() load) async* {
  yield await load();
  await for (final _ in db.tableUpdates()) {
    yield await load();
  }
}
