import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/settings/backup_service.dart';

ActivityRecordsCompanion rec(String type, DateTime t, String ext, {String platform = 'apple_health'}) =>
    ActivityRecordsCompanion.insert(
        type: type,
        startTime: t,
        endTime: t.add(const Duration(minutes: 1)),
        value: 1,
        unit: 'u',
        source: 'app',
        externalRecordId: ext,
        platform: Value(platform));

void main() {
  backupCompat();
  scaleDedupe();
  scaleComposition();
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  final t0 = DateTime(2026, 11, 10, 8);

  test('сверка удалённого: большие объёмы удаляются порциями, нужное остаётся', () async {
    final from = DateTime(2026, 11, 1);
    await db.upsertActivity([
      for (var i = 0; i < 1300; i++) rec('heartRate', from.add(Duration(minutes: i + 1)), 'h$i'),
    ]);
    final keep = {for (var i = 0; i < 1300; i += 2) 'h$i'};
    final deleted = await db.deleteActivityMissing('apple_health', 'heartRate', from, keep);
    expect(deleted, 650);
    final left = await db.activityBetween(from, DateTime(2026, 12, 1));
    expect(left.length, 650);
    expect(left.every((r) => keep.contains(r.externalRecordId)), isTrue);
    expect((await db.activityOfTypesBetween(['steps'], from, DateTime(2026, 12, 1))), isEmpty);
    expect((await db.activityOfTypesBetween(['heartRate'], from, DateTime(2026, 12, 1))).length, 650);
  });

  test('вес из Здоровья: добавление, обновление по id, пропуск дубля', () async {
    expect(await db.importWeight(platform: 'apple_health', externalId: 'a', at: t0, kg: 70.0),
        'added');
    expect(await db.importWeight(platform: 'apple_health', externalId: 'a', at: t0, kg: 70.2),
        'updated');
    // Тот же замер, пришедший под другим id через минуту: не дублируется.
    expect(
        await db.importWeight(
            platform: 'health_connect',
            externalId: 'b',
            at: t0.add(const Duration(minutes: 1)),
            kg: 70.1),
        'duplicate');
    final all = await db.allWeights();
    expect(all, hasLength(1));
    expect(all.single.weightKg, 70.2);
    expect(all.single.source, 'health:apple_health');
  });

  test('вес с весов приложения совпадает с импортом из Здоровья: дубля нет', () async {
    await db.addWeight(t0, 69.8);
    expect(await db.importWeight(platform: 'apple_health', externalId: 'x', at: t0, kg: 69.9),
        'duplicate');
    // Другое время или заметно другая масса: отдельное взвешивание.
    expect(
        await db.importWeight(
            platform: 'apple_health',
            externalId: 'y',
            at: t0.add(const Duration(hours: 3)),
            kg: 69.9),
        'added');
    expect(await db.importWeight(platform: 'apple_health', externalId: 'z', at: t0, kg: 72.5),
        'added');
    expect(await db.allWeights(), hasLength(3));
  });

  test('жир и безжировая масса прикрепляются к ближайшему взвешиванию', () async {
    await db.importWeight(platform: 'apple_health', externalId: 'a', at: t0, kg: 70);
    await db.attachBodyComposition(t0.add(const Duration(minutes: 5)), fatPct: 18.5);
    await db.attachBodyComposition(t0, leanKg: 57.0);
    final w = (await db.allWeights()).single;
    expect(w.bodyFatPct, 18.5);
    expect(w.leanMassKg, 57.0);
    // Далеко по времени: ничего не прикрепляется и не падает.
    await db.attachBodyComposition(t0.add(const Duration(hours: 5)), fatPct: 30);
    expect((await db.allWeights()).single.bodyFatPct, 18.5);
  });

  test('сверка удалений: пропавшие в источнике записи убираются, чужие и старые остаются', () async {
    await db.upsertActivity([
      rec('steps', t0, 'keep'),
      rec('steps', t0.add(const Duration(minutes: 5)), 'gone'),
      rec('steps', t0.subtract(const Duration(days: 40)), 'old'),
      rec('steps', t0.add(const Duration(minutes: 9)), 'other', platform: 'health_connect'),
      rec('spo2', t0, 'spo'),
    ]);
    final n = await db.deleteActivityMissing(
        'apple_health', 'steps', t0.subtract(const Duration(days: 30)), {'keep'});
    expect(n, 1);
    final left = (await db.activityBetween(DateTime(2020), DateTime(2030)))
        .map((r) => r.externalRecordId)
        .toSet();
    expect(left, {'keep', 'old', 'other', 'spo'});
  });

  test('удалённый в Здоровье вес убирается, ручной остаётся', () async {
    await db.addWeight(t0.subtract(const Duration(days: 2)), 71);
    await db.importWeight(platform: 'apple_health', externalId: 'a', at: t0, kg: 70);
    await db.importWeight(
        platform: 'apple_health',
        externalId: 'b',
        at: t0.add(const Duration(days: 1)),
        kg: 69);
    final n = await db.deleteImportedWeightsMissing(
        'apple_health', t0.subtract(const Duration(days: 30)), {'b'});
    expect(n, 1);
    expect((await db.allWeights()).map((w) => w.weightKg), [71, 69]);
  });
}

// Копия, сделанная до версии 1.22 (без новых полей), по-прежнему восстанавливается.
void backupCompat() {
  test('восстановление копии старого вида без полей источника', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await db.addWeight(DateTime(2026, 11, 1, 8), 70.5);
    await db.upsertActivity([
      ActivityRecordsCompanion.insert(
          type: 'steps',
          startTime: DateTime(2026, 11, 1, 9),
          endTime: DateTime(2026, 11, 1, 10),
          value: 100,
          unit: 'count',
          source: 'x',
          externalRecordId: '1')
    ]);
    final m = jsonDecode(await BackupService(db).exportJson()) as Map<String, dynamic>;
    final data = m['data'] as Map<String, dynamic>;
    for (final r in data['weightEntries'] as List) {
      (r as Map).remove('source');
      r.remove('externalId');
      r.remove('bodyFatPct');
      r.remove('leanMassKg');
    }
    for (final r in data['activityRecords'] as List) {
      (r as Map).remove('platform');
      r.remove('modifiedAt');
      r.remove('origin');
    }
    m['sha256'] = sha256.convert(utf8.encode(jsonEncode(data))).toString();
    final other = AppDatabase.memory();
    addTearDown(other.close);
    await BackupService(other).restore(jsonEncode(m));
    final w = (await other.allWeights()).single;
    expect(w.weightKg, 70.5);
    expect(w.source, 'manual');
    final a = (await other.activityBetween(DateTime(2020), DateTime(2030))).single;
    expect(a.platform, '');
  });
}

void scaleDedupe() {
  test('весы приложения после импорта из Здоровья: дополняют запись, дубля нет', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final t = DateTime(2026, 11, 10, 8);
    await db.importWeight(platform: 'apple_health', externalId: 'a', at: t, kg: 70.0);
    final id = await db.saveScaleWeight(t.add(const Duration(minutes: 2)), 70.1, impedance: 480);
    final all = await db.allWeights();
    expect(all, hasLength(1));
    expect(all.single.id, id);
    expect(all.single.impedance, 480);
    // Другое взвешивание позже: отдельная запись.
    await db.saveScaleWeight(t.add(const Duration(hours: 4)), 70.4, impedance: 470);
    expect(await db.allWeights(), hasLength(2));
  });
}

void scaleComposition() {
  test('состав тела с весов записывается только если весы его передали', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final t = DateTime(2026, 11, 10, 8);
    await db.saveScaleWeight(t, 70.5,
        impedance: 485, bodyFatPct: 21.5, muscleKg: 38, waterKg: 45, driver: 'gatt_standard');
    await db.saveScaleWeight(t.add(const Duration(hours: 5)), 70.0, driver: 'mi_scale2');
    final all = await db.allWeights();
    expect(all[0].bodyFatPct, 21.5);
    expect(all[0].muscleMassKg, 38);
    expect(all[0].scaleDriver, 'gatt_standard');
    expect(all[1].bodyFatPct, isNull);
    expect(all[1].muscleMassKg, isNull);
    expect(all[1].scaleDriver, 'mi_scale2');
  });
}
