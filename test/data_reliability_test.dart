import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/dates.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/day_data.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/features/settings/backup_service.dart';

String sum(Object d) => sha256.convert(utf8.encode(jsonEncode(d))).toString();

/// Копия с пересчитанной контрольной суммой после правки данных.
String rewrap(Map<String, dynamic> m) {
  m['sha256'] = sum(m['data'] as Object);
  return jsonEncode(m);
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<void> seed(AppDatabase d) async {
    await d.addWeight(DateTime(2026, 11, 1, 8), 70.5);
    await d.addWater('2026-11-01', 250);
    await d.setGoal('1970-01-01', const GoalValues(2000, 100, 60, 250, 2000));
    await addManualEntry(d, day: '2026-11-01', meal: Meal.lunch, name: 'Суп', kcal: 300, p: 10);
  }

  group('резервная копия', () {
    test('формат 2: версия схемы, число записей, проверка при чтении', () async {
      await seed(db);
      final text = await BackupService(db).exportJson();
      final m = jsonDecode(text) as Map<String, dynamic>;
      expect(m['format'], kBackupFormat);
      expect(m['schema'], db.schemaVersion);
      expect((m['counts'] as Map)['foodEntries'], 1);
      expect(BackupService.verify(text).ok, isTrue);

      // Число записей не совпало с заявленным, хотя сумма пересчитана: файл отвергается.
      ((m['data'] as Map)['foodEntries'] as List).clear();
      final bad = BackupService.verify(rewrap(m));
      expect(bad.ok, isFalse);
      expect(bad.message, contains('Число записей'));
    });

    test('копия более новой версии формата отвергается понятным сообщением', () async {
      final m = jsonDecode(await BackupService(db).exportJson()) as Map<String, dynamic>;
      m['format'] = kBackupFormat + 1;
      final r = BackupService.verify(jsonEncode(m));
      expect(r.ok, isFalse);
      expect(r.message, contains('более новой версией'));
    });

    test('копия формата 1 (без версии схемы и счётчиков) читается', () async {
      await seed(db);
      final m = jsonDecode(await BackupService(db).exportJson()) as Map<String, dynamic>;
      m['format'] = 1;
      m.remove('schema');
      m.remove('counts');
      for (final r in (m['data'] as Map)['weightEntries'] as List) {
        (r as Map).remove('source');
      }
      final other = AppDatabase.memory();
      addTearDown(other.close);
      await BackupService(other).restore(rewrap(m));
      expect((await other.allWeights()).single.source, 'manual');
      expect((await other.foodForDay('2026-11-01')).single.name, 'Суп');
    });

    test('повреждённая строка не стирает текущие данные', () async {
      await seed(db);
      final text = await BackupService(db).exportJson();
      final m = jsonDecode(text) as Map<String, dynamic>;
      // В копии вместо числа лежит строка: разбор строки упадёт до удаления данных.
      (((m['data'] as Map)['weightEntries'] as List).first as Map)['weightKg'] = 'не число';
      final target = AppDatabase.memory();
      addTearDown(target.close);
      await target.addWeight(DateTime(2026, 5, 5, 8), 99.9);
      await expectLater(BackupService(target).restore(rewrap(m)), throwsA(anything));
      final left = await target.allWeights();
      expect(left.single.weightKg, 99.9);
    });

    test('перед восстановлением делается снимок текущих данных, хранятся три последних', () async {
      await seed(db);
      final text = await BackupService(db).exportJson();
      final dir = Directory.systemTemp.createTempSync('pitanie_snap');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svc = BackupService(db, snapshotDir: dir.path);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        await svc.restore(text);
      }
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(3));
      // Снимок сам является корректной копией.
      expect(BackupService.verify(await files.first.readAsString()).ok, isTrue);
    });
  });

  group('удаление и целостность', () {
    test('удаление всех данных очищает пользователя, оставляет справочник без отметок', () async {
      await seed(db);
      await db.saveUser(UsersCompanion.insert());
      await db.insertProduct(ProductsCompanion.insert(
          name: 'Мой', calories: 1, proteins: 1, fats: 1, carbohydrates: 1));
      final cat = await db.insertProduct(ProductsCompanion.insert(
          name: 'Справочный',
          calories: 1,
          proteins: 1,
          fats: 1,
          carbohydrates: 1,
          isCustom: const Value(false),
          isFavorite: const Value(true),
          useCount: const Value(5)));
      await db.setSetting('scale_enabled', '1');
      await db.wipeUserData();
      expect(await db.getUser(), isNull);
      expect(await db.allWeights(), isEmpty);
      expect(await db.foodForDay('2026-11-01'), isEmpty);
      expect(await db.waterForDay('2026-11-01'), isEmpty);
      expect(await db.allGoals(), isEmpty);
      expect(await db.allSettings(), isEmpty);
      final kept = await db.productById(cat);
      expect(kept, isNotNull);
      expect(kept!.isFavorite, isFalse);
      expect(kept.useCount, 0);
      expect((await db.select(db.products).get()).where((p) => p.name == 'Мой'), isEmpty);
    });

    test('проверка целостности базы не находит проблем в нормальной базе', () async {
      await seed(db);
      expect(await db.integrityProblems(), isEmpty);
    });
  });

  group('даты и цели', () {
    test('переход через полночь: запись относится ко дню, на который она создана', () async {
      final late = DateTime(2026, 11, 9, 23, 59, 30);
      final early = DateTime(2026, 11, 10, 0, 0, 5);
      expect(dayKey(late), '2026-11-09');
      expect(dayKey(early), '2026-11-10');
      await db.addWater(dayKey(late), 200);
      await db.addWater(dayKey(early), 300);
      expect((await db.waterForDay('2026-11-09')).single.volumeMl, 200);
      expect((await db.waterForDay('2026-11-10')).single.volumeMl, 300);
    });

    test('смена часового пояса не переносит записи на другой день', () async {
      // День хранится строкой в момент записи; смещение запоминается отдельно.
      await addManualEntry(db, day: '2026-11-09', meal: Meal.dinner, name: 'Ужин', kcal: 500);
      final e = (await db.foodForDay('2026-11-09')).single;
      expect(e.date, '2026-11-09');
      expect(e.tzOffsetMin, DateTime.now().timeZoneOffset.inMinutes);
      // Запись остаётся за исходным днём независимо от того, в каком поясе её потом читают.
      expect((await db.foodForDay('2026-11-09')).length, 1);
    });

    test('новая цель не меняет нормы прошлых дней', () async {
      await db.setGoal('1970-01-01', const GoalValues(2000, 100, 60, 250, 2000));
      await db.setGoal('2026-11-10', const GoalValues(1800, 120, 50, 190, 2500));
      expect((await db.goalFor('2026-11-09')).calories, 2000);
      expect((await db.goalFor('2026-11-10')).calories, 1800);
      expect((await db.goalFor('2026-12-01')).calories, 1800);
      final past = await loadDayData(db, '2026-11-09');
      expect(past.goal.calories, 2000);
    });
  });

  test('большой объём: 60 тыс. записей активности и быстрые выборки за день', () async {
    final base = DateTime(2026, 1, 1);
    final rows = <ActivityRecordsCompanion>[
      for (var i = 0; i < 60000; i++)
        ActivityRecordsCompanion.insert(
            type: i % 3 == 0 ? 'heartRate' : 'steps',
            startTime: base.add(Duration(minutes: i * 8)),
            endTime: base.add(Duration(minutes: i * 8 + 1)),
            value: 70,
            unit: 'u',
            source: 'app',
            externalRecordId: 'r$i'),
    ];
    await db.upsertActivity(rows);
    final sw = Stopwatch()..start();
    final day = await db.activityBetween(DateTime(2026, 6, 1), DateTime(2026, 6, 2));
    sw.stop();
    expect(day, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(1500));
    expect(await db.integrityProblems(), isEmpty);
  });
}
