import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:health/health.dart';

import '../../database/database.dart';

class SyncResult {
  final String status; // ok | no_data | no_access | unavailable | error | not_connected | unsupported
  final int records;
  final int workouts;
  final int weights;
  final int duplicates; // взвешивания, совпавшие с уже имеющимися
  final int deleted; // записи, удалённые в источнике и убранные из приложения
  final Map<String, int> perType;
  final Map<String, String> sources; // id -> имя
  final Map<String, String> errors; // тип данных -> причина (нет доступа и т.п.)
  final String? error;
  const SyncResult(this.status,
      {this.records = 0,
      this.workouts = 0,
      this.weights = 0,
      this.duplicates = 0,
      this.deleted = 0,
      this.perType = const {},
      this.sources = const {},
      this.errors = const {},
      this.error});

  Map<String, dynamic> toJson() => {
        'status': status,
        'records': records,
        'workouts': workouts,
        'weights': weights,
        'duplicates': duplicates,
        'deleted': deleted,
        'perType': perType,
        'sources': sources,
        'errors': errors,
        'error': error,
        'at': DateTime.now().toIso8601String(),
      };
}

/// Группы данных для экрана «Источники здоровья»: название -> типы Health.
const Map<String, List<String>> kHealthCategories = {
  'Шаги и дистанция': ['STEPS', 'DISTANCE_DELTA', 'DISTANCE_WALKING_RUNNING'],
  'Энергия': ['ACTIVE_ENERGY_BURNED', 'BASAL_ENERGY_BURNED', 'TOTAL_CALORIES_BURNED'],
  'Пульс': ['HEART_RATE', 'RESTING_HEART_RATE'],
  'HRV': ['HEART_RATE_VARIABILITY_SDNN', 'HEART_RATE_VARIABILITY_RMSSD'],
  'Кислород в крови (SpO₂)': ['BLOOD_OXYGEN'],
  'Дыхание': ['RESPIRATORY_RATE'],
  'Сон и его фазы': ['SLEEP_ASLEEP', 'SLEEP_SESSION', 'SLEEP_DEEP', 'SLEEP_REM', 'SLEEP_LIGHT'],
  'Тренировки': ['WORKOUT'],
  'Вес': ['WEIGHT'],
  'Состав тела': ['BODY_FAT_PERCENTAGE', 'LEAN_BODY_MASS'],
};

/// Чтение данных из Health Connect (Android) и Apple Health (iOS).
/// Приложение не обращается к часам напрямую по Bluetooth.
class HealthService {
  HealthService(this.db);
  final AppDatabase db;
  final Health _health = Health();
  bool _configured = false;

  static bool get supported => Platform.isAndroid || Platform.isIOS;
  String get sourceType => Platform.isIOS ? 'apple_health' : 'health_connect';
  String get sourceLabel => Platform.isIOS ? 'Apple Health' : 'Health Connect';

  List<HealthDataType> get types => Platform.isIOS
      ? [
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_WALKING_RUNNING,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.BASAL_ENERGY_BURNED,
          HealthDataType.HEART_RATE,
          HealthDataType.RESTING_HEART_RATE,
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
          HealthDataType.BLOOD_OXYGEN,
          HealthDataType.RESPIRATORY_RATE,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.WORKOUT,
          HealthDataType.WEIGHT,
          HealthDataType.BODY_FAT_PERCENTAGE,
          HealthDataType.LEAN_BODY_MASS,
        ]
      : [
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.BASAL_ENERGY_BURNED,
          HealthDataType.TOTAL_CALORIES_BURNED,
          HealthDataType.HEART_RATE,
          HealthDataType.RESTING_HEART_RATE,
          HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
          HealthDataType.BLOOD_OXYGEN,
          HealthDataType.SLEEP_SESSION,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.WORKOUT,
          HealthDataType.WEIGHT,
          HealthDataType.BODY_FAT_PERCENTAGE,
          HealthDataType.LEAN_BODY_MASS,
        ];

  List<HealthDataAccess> get _perms =>
      List.filled(types.length, HealthDataAccess.READ);

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// Health Connect доступен? (на iOS всегда true)
  Future<bool> available() async {
    if (!supported) return false;
    if (!Platform.isAndroid) return true;
    await _configure();
    final s = await _health.getHealthConnectSdkStatus();
    return s == HealthConnectSdkStatus.sdkAvailable;
  }

  Future<void> installHealthConnect() async {
    await _configure();
    await _health.installHealthConnect();
  }

  /// null на iOS: система не сообщает, выдан ли доступ на чтение.
  Future<bool?> hasPermissions() async {
    await _configure();
    return _health.hasPermissions(types, permissions: _perms);
  }

  Future<bool> requestPermissions() async {
    await _configure();
    final ok = await _health.requestAuthorization(types, permissions: _perms);
    await db.saveSource(
        sourceType,
        ConnectedSourcesCompanion(
          deviceName: Value('Часы через $sourceLabel'),
          permissions: Value(ok ? 'granted' : 'denied'),
          syncStatus: Value(ok ? 'waiting' : 'no_access'),
        ));
    return ok;
  }

  Future<void> disconnect() => db.deleteSource(sourceType);

  bool _askedAuth = false;

  /// Читает один тип данных; сбой одного типа (например, нет доступа) не мешает остальным.
  Future<List<HealthDataPoint>> _readType(
      HealthDataType t, DateTime from, DateTime to, Map<String, String> errors) async {
    Object? err;
    try {
      return await _health.getHealthDataFromTypes(types: [t], startTime: from, endTime: to);
    } catch (e) {
      err = e;
    }
    // iOS: доступ к типу ещё не запрошен (например, добавлен в новой версии).
    if (err.toString().contains('not determined') && !_askedAuth) {
      _askedAuth = true;
      try {
        await _health.requestAuthorization(types, permissions: _perms);
        return await _health.getHealthDataFromTypes(types: [t], startTime: from, endTime: to);
      } catch (e2) {
        err = e2;
      }
    }
    final m = err.toString().replaceAll(RegExp(r'\s+'), ' ');
    errors[t.name] = m.length > 100 ? m.substring(0, 100) : m;
    return [];
  }

  /// Android: окно разрешений Health Connect показывается только когда список данных изменился.
  Future<void> _askNewPermissionsOnce() async {
    if (!Platform.isAndroid) return;
    const key = 'health_perm_asked';
    final asked = (await db.allSettings())[key];
    if (asked == '${types.length}') return;
    await db.setSetting(key, '${types.length}');
    if (await hasPermissions() == true) return;
    await _health.requestAuthorization(types, permissions: _perms);
  }

  static String _origin(RecordingMethod m) => switch (m) {
        RecordingMethod.manual => 'manual',
        RecordingMethod.automatic => 'automatic',
        RecordingMethod.active => 'active',
        _ => 'unknown',
      };

  /// Загружает новые данные. Ошибка не удаляет ранее сохранённые данные.
  /// Окно чтения: с прошлой синхронизации (минус 2 дня запаса). Записи, удалённые в источнике,
  /// убираются сверкой окна, но только для типов, по которым источник вернул данные:
  /// отзыв доступа не стирает историю.
  Future<SyncResult> sync({bool full = false}) async {
    if (!supported) return const SyncResult('unsupported');
    final src = await db.getSource(sourceType);
    if (src == null) return const SyncResult('not_connected');
    try {
      if (!await available()) {
        await _saveStatus('unavailable', null, null);
        return const SyncResult('unavailable');
      }
      await _configure();
      await _askNewPermissionsOnce();
      final now = DateTime.now();
      final from = (src.lastSync == null || full)
          ? now.subtract(const Duration(days: 30))
          : src.lastSync!.subtract(const Duration(days: 2));

      final errors = <String, String>{};
      final points = <HealthDataPoint>[];
      for (final t in types) {
        points.addAll(await _readType(t, from, now, errors));
      }
      if (errors.length == types.length) {
        final r = SyncResult('no_access', errors: errors);
        await _saveStatus('no_access', null, r);
        return r;
      }

      final recs = <ActivityRecordsCompanion>[];
      final works = <WorkoutsCompanion>[];
      final perType = <String, int>{};
      final sources = <String, String>{};
      final seen = <String, Set<String>>{}; // тип записи -> id, пришедшие из источника
      final weightIds = <String>{};
      var weights = 0, duplicates = 0;
      final hr = points.where((p) => p.type == HealthDataType.HEART_RATE).toList();
      final comp = <(DateTime, double?, double?)>[];

      for (final p in points) {
        final sid = p.sourceId.isNotEmpty ? p.sourceId : p.sourceName;
        final sname = p.sourceName.isNotEmpty ? p.sourceName : sid;
        sources[sid] = sname;
        final ext = p.uuid.isNotEmpty
            ? p.uuid
            : '${p.type.name}_${p.dateFrom.millisecondsSinceEpoch}_${p.dateTo.millisecondsSinceEpoch}';
        final tz = p.dateFrom.timeZoneOffset.inMinutes;

        if (p.type == HealthDataType.WORKOUT && p.value is WorkoutHealthValue) {
          final w = p.value as WorkoutHealthValue;
          final inside = hr
              .where((h) =>
                  (h.sourceId.isNotEmpty ? h.sourceId : h.sourceName) == sid &&
                  !h.dateFrom.isBefore(p.dateFrom) &&
                  !h.dateFrom.isAfter(p.dateTo))
              .map((h) => (h.value as NumericHealthValue).numericValue.toDouble())
              .toList();
          works.add(WorkoutsCompanion.insert(
            source: sid,
            sourceName: Value(sname),
            externalRecordId: ext,
            workoutType: w.workoutActivityType.name,
            startTime: p.dateFrom,
            endTime: p.dateTo,
            energyKcal: Value(w.totalEnergyBurned?.toDouble()),
            distanceM: Value(w.totalDistance?.toDouble()),
            avgHr: Value(inside.isEmpty
                ? null
                : inside.reduce((a, b) => a + b) / inside.length),
            maxHr: Value(inside.isEmpty
                ? null
                : inside.reduce((a, b) => a > b ? a : b)),
          ));
          perType['WORKOUT'] = (perType['WORKOUT'] ?? 0) + 1;
          continue;
        }
        if (p.value is! NumericHealthValue) continue;
        final v = (p.value as NumericHealthValue).numericValue.toDouble();
        final mins = p.dateTo.difference(p.dateFrom).inMinutes.toDouble();

        if (p.type == HealthDataType.WEIGHT) {
          if (v < 20 || v > 400) continue;
          weightIds.add(ext);
          perType['WEIGHT'] = (perType['WEIGHT'] ?? 0) + 1;
          final r = await db.importWeight(
              platform: sourceType, externalId: ext, at: p.dateFrom, kg: v);
          if (r == 'duplicate') {
            duplicates++;
          } else {
            weights++;
          }
          continue;
        }

        final (type, unit, value) = switch (p.type) {
          HealthDataType.STEPS => ('steps', 'count', v),
          HealthDataType.DISTANCE_DELTA ||
          HealthDataType.DISTANCE_WALKING_RUNNING =>
            ('distance', 'm', v),
          HealthDataType.ACTIVE_ENERGY_BURNED => ('activeEnergy', 'kcal', v),
          HealthDataType.BASAL_ENERGY_BURNED => ('basalEnergy', 'kcal', v),
          HealthDataType.TOTAL_CALORIES_BURNED => ('totalEnergy', 'kcal', v),
          HealthDataType.HEART_RATE => ('heartRate', 'bpm', v),
          HealthDataType.RESTING_HEART_RATE => ('restingHeartRate', 'bpm', v),
          HealthDataType.HEART_RATE_VARIABILITY_SDNN => ('hrvSdnn', 'ms', v),
          HealthDataType.HEART_RATE_VARIABILITY_RMSSD => ('hrvRmssd', 'ms', v),
          // Apple Health отдаёт насыщение кислородом долей (0.97), приводим к процентам.
          HealthDataType.BLOOD_OXYGEN => ('spo2', '%', v <= 1.0 ? v * 100 : v),
          HealthDataType.RESPIRATORY_RATE => ('respiration', 'br/min', v),
          HealthDataType.BODY_FAT_PERCENTAGE => ('bodyFat', '%', v <= 1.0 ? v * 100 : v),
          HealthDataType.LEAN_BODY_MASS => ('leanMass', 'kg', v),
          HealthDataType.SLEEP_SESSION || HealthDataType.SLEEP_ASLEEP => ('sleep', 'min', mins),
          HealthDataType.SLEEP_DEEP => ('sleepDeep', 'min', mins),
          HealthDataType.SLEEP_REM => ('sleepRem', 'min', mins),
          HealthDataType.SLEEP_LIGHT => ('sleepLight', 'min', mins),
          _ => ('', '', 0.0),
        };
        if (type.isEmpty) continue;
        perType[p.type.name] = (perType[p.type.name] ?? 0) + 1;
        seen.putIfAbsent(type, () => {}).add(ext);
        if (type == 'bodyFat') comp.add((p.dateFrom, value, null));
        if (type == 'leanMass') comp.add((p.dateFrom, null, value));
        recs.add(ActivityRecordsCompanion.insert(
          type: type,
          startTime: p.dateFrom,
          endTime: p.dateTo,
          value: value,
          unit: unit,
          source: sid,
          externalRecordId: ext,
          sourceName: Value(sname),
          tzOffsetMin: Value(tz),
          platform: Value(sourceType),
          modifiedAt: Value(now),
          origin: Value(_origin(p.recordingMethod)),
        ));
      }

      await db.upsertActivity(recs);
      await db.upsertWorkouts(works);
      for (final c in comp) {
        await db.attachBodyComposition(c.$1, fatPct: c.$2, leanKg: c.$3);
      }

      // Удалённое в источнике: сверка окна по типам, которые источник вернул.
      var deleted = 0;
      for (final e in seen.entries) {
        deleted += await db.deleteActivityMissing(sourceType, e.key, from, e.value);
      }
      if (weightIds.isNotEmpty) {
        deleted += await db.deleteImportedWeightsMissing(sourceType, from, weightIds);
      }

      final empty = recs.isEmpty && works.isEmpty && weights == 0 && duplicates == 0;
      final result = SyncResult(empty ? 'no_data' : 'ok',
          records: recs.length,
          workouts: works.length,
          weights: weights,
          duplicates: duplicates,
          deleted: deleted,
          perType: perType,
          sources: sources,
          errors: errors);
      await _saveStatus(result.status, now, result);
      return result;
    } catch (e) {
      final r = SyncResult('error', error: e.toString());
      await _saveStatus('error', null, r);
      return r;
    }
  }

  Future<void> _saveStatus(String status, DateTime? at, SyncResult? r) {
    return db.saveSource(
        sourceType,
        ConnectedSourcesCompanion(
          syncStatus: Value(status),
          lastSync: at == null ? const Value.absent() : Value(at),
          lastReport: r == null ? const Value.absent() : Value(jsonEncode(r.toJson())),
        ));
  }
}
