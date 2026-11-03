import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'database.dart';

/// Версия вшитого каталога. При её увеличении недостающие записи добавляются
/// (по паре источник + идентификатор), существующие и пользовательские не меняются.
const catalogVersion = 1;
const _catalogVersionKey = 'catalog_version';

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
    const chunk = 500;
    for (var i = 0; i < rows.length; i += chunk) {
      final part = rows.skip(i).take(chunk).toList();
      final companions = <ProductsCompanion>[];
      for (final r in part) {
        final source = r['source'] as String;
        final sourceId = r['source_id'] as String;
        if (existing.contains('$source|$sourceId')) {
          skipped++;
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
        ));
      }
      if (companions.isNotEmpty) {
        await db.batch((b) => b.insertAll(db.products, companions));
        added += companions.length;
      }
      onProgress?.call(i + part.length, rows.length);
      await Future<void>.delayed(Duration.zero); // не блокируем интерфейс надолго
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
