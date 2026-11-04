import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/database/catalog_importer.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/products/off_api.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const _catalog = 'assets/catalog/catalog.sqlite';

void main() {
  offTests();
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  group('каталог USDA (локально, без сети)', () {
    test('импорт из вшитого файла добавляет столько записей, сколько указано в отчёте', () async {
      final report =
          jsonDecode(File('assets/catalog/import_report.json').readAsStringSync()) as Map;
      final res = await importCatalogFromFile(db, _catalog);
      expect(res.total, report['total_in_catalog']);
      expect(res.added, report['total_in_catalog']);
      final foods = await (db.select(db.products)..where((t) => t.kind.equals('food'))).get();
      final dishes = await (db.select(db.products)..where((t) => t.kind.equals('dish'))).get();
      expect(foods.where((p) => p.verified).length, report['foods']);
      expect(dishes.length, report['dishes']);
    });

    test('повторный импорт идемпотентен (без дублей)', () async {
      await importCatalogFromFile(db, _catalog);
      final before = (await db.select(db.products).get()).length;
      final again = await importCatalogFromFile(db, _catalog);
      expect(again.added, 0);
      expect((await db.select(db.products).get()).length, before);
    });

    test('значения совпадают с файлом каталога, нулей вместо отсутствующих нет', () async {
      await importCatalogFromFile(db, _catalog);
      final src = sql.sqlite3.open(_catalog, mode: sql.OpenMode.readOnly);
      final row = src
          .select("SELECT source_id, kcal, protein, fat, carbs FROM foods WHERE id = 'sr_168462'")
          .first; // Spinach, raw
      src.dispose();
      final p = await (db.select(db.products)..where((t) => t.sourceId.equals('168462'))).getSingle();
      expect(p.calories, row['kcal']);
      expect(p.proteins, row['protein']);
      expect(p.fats, row['fat']);
      expect(p.carbohydrates, row['carbs']);
      expect(p.verified, isTrue);
      // В каталог не попадали записи без полного набора КБЖУ: проверяем, что нет
      // «пустых» записей, у которых все четыре значения нулевые (признак подставленных нулей).
      final allZero = await (db.select(db.products)
            ..where((t) =>
                t.verified.equals(true) &
                t.calories.equals(0) &
                t.proteins.equals(0) &
                t.fats.equals(0) &
                t.carbohydrates.equals(0)))
          .get();
      // Вода и подобные продукты действительно имеют нулевые значения в USDA; они есть в источнике.
      final src2 = sql.sqlite3.open(_catalog, mode: sql.OpenMode.readOnly);
      final zerosInSource = src2
          .select('SELECT COUNT(*) c FROM foods WHERE kcal = 0 AND protein = 0 AND fat = 0 AND carbs = 0')
          .first['c'] as int;
      src2.dispose();
      expect(allZero.length, zerosInSource);
    });

    test('поиск по английскому, русскому названию и по русскому слову основы', () async {
      await importCatalogFromFile(db, _catalog);
      final en = await db.watchProducts(query: 'spinach raw').first;
      expect(en, isNotEmpty);
      final ru = await db.watchProducts(query: 'яичный белок').first;
      expect(ru, isNotEmpty);
      // «курица» есть только в русской основе глоссария, а названия USDA английские.
      final chicken = await db.watchProducts(query: 'курица').first;
      expect(chicken.any((p) => (p.nameEn ?? '').toLowerCase().startsWith('chicken')), isTrue);
    });

    test('фильтры по состоянию и виду (блюдо / продукт)', () async {
      await importCatalogFromFile(db, _catalog);
      final raw = await db.watchProducts(query: 'beef', state: 'raw', limit: 50).first;
      expect(raw, isNotEmpty);
      expect(raw.every((p) => p.state == 'raw'), isTrue);
      final dishes = await db.watchProducts(kind: 'dish', limit: 30).first;
      expect(dishes, isNotEmpty);
      expect(dishes.every((p) => p.kind == 'dish'), isTrue);
    });

    test('КБЖУ порции = значение на 100 г × масса / 100', () async {
      await importCatalogFromFile(db, _catalog);
      final p = await (db.select(db.products)
            ..where((t) => t.sourceId.equals('168462')))
          .getSingle();
      final n = nutrientsForAmount(
          Nutrients(p.calories, p.proteins, p.fats, p.carbohydrates), 250);
      expect(n.calories, closeTo(p.calories * 2.5, 1e-9));
      expect(n.proteins, closeTo(p.proteins * 2.5, 1e-9));
    });
  });

  group('вес штуки', () {
    test('штучные порции USDA распознаются, меры объёма и упаковки — нет', () {
      expect(usdaPieceWeight('1 slice', 25), 25);
      expect(usdaPieceWeight('1 medium', 118), 118);
      expect(usdaPieceWeight('1 egg', 50), 50);
      expect(usdaPieceWeight('1 cup', 240), isNull);
      expect(usdaPieceWeight('1 fl oz', 30), isNull);
      expect(usdaPieceWeight('1 serving', 34), isNull);
      expect(usdaPieceWeight('1 package', 300), isNull);
      expect(usdaPieceWeight('2 slices', 50), isNull);
      expect(usdaPieceWeight('1/2 cup', 100), isNull);
      expect(usdaPieceWeight(null, 10), isNull);
    });
    test('после импорта у штучных продуктов USDA есть вес штуки', () async {
      await importCatalogFromFile(db, _catalog);
      final withPiece = await (db.select(db.products)..where((t) => t.pieceWeight.isNotNull())).get();
      expect(withPiece.length, greaterThan(500));
      for (final p in withPiece.where((p) => p.verified)) {
        expect(p.pieceWeight, p.portionSize); // вес штуки равен весу порции из USDA
      }
    });
    test('повторный импорт дополняет уже импортированные записи весом штуки', () async {
      await importCatalogFromFile(db, _catalog);
      await db.customStatement('UPDATE products SET piece_weight = NULL');
      await importCatalogFromFile(db, _catalog);
      final withPiece = await (db.select(db.products)..where((t) => t.pieceWeight.isNotNull())).get();
      expect(withPiece.length, greaterThan(500));
    });
    test('справочник: Orion Choco Pie можно добавлять штуками, в том числе в старой базе', () async {
      await db.seedProducts();
      var p = await (db.select(db.products)..where((t) => t.name.equals('Orion Choco Pie'))).getSingle();
      expect(p.pieceWeight, 30);
      await db.customStatement("UPDATE products SET piece_weight = NULL WHERE name = 'Orion Choco Pie'");
      await db.setSetting('seed_version', '0');
      await db.seedProducts();
      p = await (db.select(db.products)..where((t) => t.name.equals('Orion Choco Pie'))).getSingle();
      expect(p.pieceWeight, 30);
    });
  });

  group('миграция схемы 1 → 2', () {
    test('данные пользователя сохраняются, новые столбцы добавляются', () async {
      final dir = Directory.systemTemp.createTempSync('pitanie_mig');
      final path = '${dir.path}/old.sqlite';
      // 1. создаём базу текущей схемы и «откатываем» её до вида версии 1
      final first = AppDatabase(NativeDatabase(File(path)));
      await first.select(first.products).get();
      await first.close();
      final raw = sql.sqlite3.open(path);
      raw.execute('DROP INDEX IF EXISTS idx_product_source');
      for (final c in ['name_en', 'source_id', 'state', 'kind', 'verified', 'portion_label']) {
        raw.execute('ALTER TABLE products DROP COLUMN $c');
      }
      raw.execute(
          "INSERT INTO products (name, calories, proteins, fats, carbohydrates, source, is_custom) "
          "VALUES ('Моя гречка', 110, 3.6, 1.2, 21.3, 'Пользователь', 1)");
      raw.execute('PRAGMA user_version = 1');
      raw.dispose();

      // 2. открываем приложением: должна выполниться миграция
      final migrated = AppDatabase(NativeDatabase(File(path)));
      addTearDown(() async {
        await migrated.close();
        dir.deleteSync(recursive: true);
      });
      final mine = await (migrated.select(migrated.products)
            ..where((t) => t.name.equals('Моя гречка')))
          .getSingle();
      expect(mine.calories, 110);
      expect(mine.isCustom, isTrue);
      expect(mine.kind, 'food');
      expect(mine.verified, isFalse);
      expect(mine.state, 'unknown');
      // и импорт каталога после миграции работает
      final res = await importCatalogFromFile(migrated, _catalog);
      expect(res.added, greaterThan(10000));
      final still = await (migrated.select(migrated.products)
            ..where((t) => t.name.equals('Моя гречка')))
          .get();
      expect(still.length, 1);
    });
  });
}

// ---- Open Food Facts: проверка нутриентов ----
void offTests() {
  group('Open Food Facts: проверка нутриентов', () {
    test('нормальные значения принимаются без предупреждения', () {
      final r = validateOffNutrients(250, 10, 12, 26); // 4*10 + 4*26 + 9*12 = 252
      expect(r.isValid, isTrue);
      expect(r.warning, isNull);
    });
    test('невозможные значения отклоняются', () {
      expect(validateOffNutrients(300, 60, 30, 30).isValid, isFalse); // сумма > 100 г
      expect(validateOffNutrients(1500, 10, 10, 10).isValid, isFalse);
      expect(validateOffNutrients(-1, 1, 1, 1).isValid, isFalse);
      expect(validateOffNutrients(double.nan, 1, 1, 1).isValid, isFalse);
    });
    test('сильное расхождение калорий и БЖУ даёт предупреждение, но не отказ', () {
      final r = validateOffNutrients(500, 5, 5, 10); // ожидалось ~105
      expect(r.isValid, isTrue);
      expect(r.warning, isNotNull);
    });
    test('неполный результат непригоден', () {
      const off = OffResult('Продукт', null, null, 5, 5, 5);
      expect(off.complete, isFalse);
      expect(off.usable, isFalse);
    });
  });
}
