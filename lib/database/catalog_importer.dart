import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'database.dart';

/// Версия вшитого каталога. При её увеличении недостающие записи добавляются
/// (по паре источник + идентификатор), существующие и пользовательские не меняются.
const catalogVersion = 2;
const _catalogVersionKey = 'catalog_version';

const _notPiece = [
  'cup', 'oz', 'tbsp', 'tablespoon', 'tsp', 'teaspoon', 'serving', 'package', 'container',
  'packet', 'scoop', 'pint', 'quart', 'gallon', 'liter', 'bottle', 'can ', 'jar', 'bag',
  'box', 'dash', 'pinch', 'portion', 'meal', 'sheet', 'pan', 'recipe', 'bowl', 'drink',
];

/// Вес одной штуки по порции USDA: только если порция описана как «1 <штучная единица>»
/// (ломтик, яйцо, печенье и т. п.), без мер объёма и упаковок. Иначе null.
double? usdaPieceWeight(String? label, double? grams) {
  if (label == null || grams == null || grams < 0.5 || grams > 1000) return null;
  final l = label.toLowerCase().trim();
  if (!RegExp(r'^1\s+[a-z]').hasMatch(l)) return null;
  for (final w in _notPiece) {
    if (l.contains(w)) return null;
  }
  return grams;
}

class CatalogImportResult {
  final int added, alreadyThere, total;
  const CatalogImportResult(this.added, this.alreadyThere, this.total);
}

/// Читает каталог из файла SQLite (вшит в приложение, интернет не нужен) и добавляет
/// продукты в локальную базу. Идемпотентно: повторный запуск ничего не дублирует.
Future<CatalogImportResult> importCatalogFromFile(AppDatabase db, String path,
    {void Function(int done, int total)? onProgress}) async {
  final src = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  try {
    final rows = src.select('''
      SELECT id, source, source_id, kind, name_en, name_ru, search_ru, category_en, category_ru,
             kcal, protein, fat, carbs, state, portion_g, portion_label
      FROM foods''');
    final existing = <String>{
      for (final r in await (db.selectOnly(db.products)
            ..addColumns([db.products.source, db.products.sourceId])
            ..where(db.products.sourceId.isNotNull()))
          .get())
        '${r.read(db.products.source)}|${r.read(db.products.sourceId)}'
    };
    var added = 0, skipped = 0;
    final pieceUpdates = <(String, String, double)>[];
    const chunk = 500;
    for (var i = 0; i < rows.length; i += chunk) {
      final part = rows.skip(i).take(chunk).toList();
      final companions = <ProductsCompanion>[];
      for (final r in part) {
        final source = r['source'] as String;
        final sourceId = r['source_id'] as String;
        final pieceW = usdaPieceWeight(
            r['portion_label'] as String?, (r['portion_g'] as num?)?.toDouble());
        if (existing.contains('$source|$sourceId')) {
          skipped++;
          // Каталог версии 2 добавил вес штуки: дополняем уже импортированные записи.
          if (pieceW != null) pieceUpdates.add((source, sourceId, pieceW));
          continue;
        }
        final nameEn = r['name_en'] as String;
        final nameRu = r['name_ru'] as String?;
        final name = (nameRu != null && nameRu.isNotEmpty) ? nameRu : nameEn;
        final isDish = r['kind'] == 'dish';
        final category = isDish
            ? 'Готовые блюда (USDA)'
            : ((r['category_ru'] as String?)?.isNotEmpty ?? false)
                ? r['category_ru'] as String
                : ((r['category_en'] as String?) ?? 'Прочее');
        final key = [name, nameEn, r['search_ru'] ?? '']
            .join(' ')
            .toLowerCase();
        companions.add(ProductsCompanion.insert(
          name: name.length > 200 ? name.substring(0, 200) : name,
          calories: (r['kcal'] as num).toDouble(),
          proteins: (r['protein'] as num).toDouble(),
          fats: (r['fat'] as num).toDouble(),
          carbohydrates: (r['carbs'] as num).toDouble(),
          searchKey: Value(key),
          category: Value(category),
          source: Value(source),
          sourceId: Value(sourceId),
          nameEn: Value(nameEn),
          state: Value(r['state'] as String),
          kind: Value(r['kind'] as String),
          verified: const Value(true),
          isCustom: const Value(false),
          portionSize: Value((r['portion_g'] as num?)?.toDouble()),
          portionLabel: Value(r['portion_label'] as String?),
          pieceWeight: Value(pieceW),
        ));
      }
      if (companions.isNotEmpty) {
        await db.batch((b) => b.insertAll(db.products, companions));
        added += companions.length;
      }
      onProgress?.call(i + part.length, rows.length);
      await Future<void>.delayed(Duration.zero); // не блокируем интерфейс надолго
    }
    if (pieceUpdates.isNotEmpty) {
      await db.batch((b) {
        for (final u in pieceUpdates) {
          b.customStatement(
              'UPDATE products SET piece_weight = ? WHERE source = ? AND source_id = ? '
              'AND piece_weight IS NULL',
              [u.$3, u.$1, u.$2]);
        }
      });
    }
    return CatalogImportResult(added, skipped, rows.length);
  } finally {
    src.dispose();
  }
}

/// При первом запуске (и после обновления каталога) копирует вшитый файл во временную
/// папку и добавляет его содержимое в базу. Без сети.
Future<CatalogImportResult?> ensureCatalog(AppDatabase db,
    {void Function(int done, int total)? onProgress}) async {
  final saved = (await db.allSettings())[_catalogVersionKey];
  if (saved == '$catalogVersion') return null;
  final bytes = await rootBundle.load('assets/catalog/catalog.sqlite');
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, 'catalog_import.sqlite'));
  await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true);
  try {
    final res = await importCatalogFromFile(db, file.path, onProgress: onProgress);
    await db.setSetting(_catalogVersionKey, '$catalogVersion');
    return res;
  } finally {
    try {
      await file.delete();
    } catch (_) {}
  }
}
