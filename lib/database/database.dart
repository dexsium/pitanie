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
  int get schemaVersion => 3;

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
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await seedProducts();
        },
      );

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

  ProductsCompanion _withKey(ProductsCompanion c) => c.copyWith(
      searchKey: Value(
          '${c.name.value} ${c.brand.value ?? ''}'.toLowerCase().trim()));

  Future<int> insertProduct(ProductsCompanion c) =>
      into(products).insert(_withKey(c));

  Future<void> updateProduct(int id, ProductsCompanion c) =>
      (update(products)..where((t) => t.id.equals(id))).write(_withKey(c));

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

  Future<void> upsertWorkouts(List<WorkoutsCompanion> list) async {
    await batch((b) {
      for (final c in list) {
        b.insert(workouts, c,
            onConflict: DoUpdate((_) => c,
                target: [workouts.source, workouts.externalRecordId]));
      }
    });
  }

  Future<List<ActivityRecord>> activityBetween(DateTime from, DateTime to) =>
      (select(activityRecords)
            ..where((t) =>
                t.endTime.isBiggerOrEqualValue(from) &
                t.startTime.isSmallerOrEqualValue(to)))
          .get();

  /// Минутные записи сна (и фаз) из данных часов за период; без шагов и пульса.
  Future<List<ActivityRecord>> sleepRecordsBetween(DateTime from, DateTime to,
          {required String source, bool stages = true}) =>
      (select(activityRecords)
            ..where((t) =>
                t.source.equals(source) &
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
