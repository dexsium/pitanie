import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:health/health.dart';

import '../../database/database.dart';

class SyncResult {
  final String status; // ok | no_data | no_access | unavailable | error | not_connected | unsupported
  final int records;
  final int workouts;
  final Map<String, int> perType;
  final Map<String, String> sources; // id -> имя
  final String? error;
  const SyncResult(this.status,
      {this.records = 0,
      this.workouts = 0,
      this.perType = const {},
      this.sources = const {},
      this.error});

  Map<String, dynamic> toJson() => {
        'status': status,
        'records': records,
        'workouts': workouts,
        'perType': perType,
        'sources': sources,
        'error': error,
        'at': DateTime.now().toIso8601String(),
      };
}

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
          HealthDataType.HEART_RATE,
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.WORKOUT,
          // Показатели для «Анализа здоровья»: часы пишут их, если умеют измерять.
          HealthDataType.RESTING_HEART_RATE,
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
          HealthDataType.BLOOD_OXYGEN,
          HealthDataType.RESPIRATORY_RATE,
        ]
      : [
          HealthDataType.STEPS,
          HealthDataType.DISTANCE_DELTA,
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.TOTAL_CALORIES_BURNED,
          HealthDataType.HEART_RATE,
          HealthDataType.SLEEP_SESSION,
          HealthDataType.WORKOUT,
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

  /// Загружает новые данные. Ошибка не удаляет ранее сохранённые данные.
  Future<SyncResult> sync({bool full = false}) async {
    if (!supported) return const SyncResult('unsupported');
    final src = await db.getSource(sourceType);
    if (src == null) return const SyncResult('not_connected');
    try {
      if (!await available()) {
        await _saveStatus('unavailable', null, null);
        return const SyncResult('unavailable');
      }
      final now = DateTime.now();
      final from = (src.lastSync == null || full)
          ? now.subtract(const Duration(days: 30))
          : src.lastSync!.subtract(const Duration(days: 2));

      List<HealthDataPoint> points;
      try {
        points = await _health.getHealthDataFromTypes(
            types: types, startTime: from, endTime: now);
      } catch (e) {
        // iOS: для части типов (например, добавленных в новой версии) доступ ещё не запрошен.
        // Система покажет окно разрешений только для них, затем повторяем чтение.
        if (!e.toString().contains('not determined')) rethrow;
        await _health.requestAuthorization(types, permissions: _perms);
        points = await _health.getHealthDataFromTypes(
            types: types, startTime: from, endTime: now);
      }

      final recs = <ActivityRecordsCompanion>[];
      final works = <WorkoutsCompanion>[];
      final perType = <String, int>{};
      final sources = <String, String>{};
      final hr = points.where((p) => p.type == HealthDataType.HEART_RATE).toList();

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
        final (type, unit, value) = switch (p.type) {
          HealthDataType.STEPS => ('steps', 'count', v),
          HealthDataType.DISTANCE_DELTA ||
          HealthDataType.DISTANCE_WALKING_RUNNING =>
            ('distance', 'm', v),
          HealthDataType.ACTIVE_ENERGY_BURNED => ('activeEnergy', 'kcal', v),
          HealthDataType.TOTAL_CALORIES_BURNED => ('totalEnergy', 'kcal', v),
          HealthDataType.HEART_RATE => ('heartRate', 'bpm', v),
          HealthDataType.RESTING_HEART_RATE => ('restingHeartRate', 'bpm', v),
          HealthDataType.HEART_RATE_VARIABILITY_SDNN => ('hrvSdnn', 'ms', v),
          // Apple Health отдаёт насыщение кислородом долей (0.97), приводим к процентам.
          HealthDataType.BLOOD_OXYGEN => ('spo2', '%', v <= 1.0 ? v * 100 : v),
          HealthDataType.RESPIRATORY_RATE => ('respiration', 'br/min', v),
          HealthDataType.SLEEP_SESSION ||
          HealthDataType.SLEEP_ASLEEP =>
            ('sleep', 'min', p.dateTo.difference(p.dateFrom).inMinutes.toDouble()),
          _ => ('', '', 0.0),
        };
        if (type.isEmpty) continue;
        perType[type] = (perType[type] ?? 0) + 1;
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
        ));
      }

      await db.upsertActivity(recs);
      await db.upsertWorkouts(works);

      final empty = recs.isEmpty && works.isEmpty;
      final result = SyncResult(empty ? 'no_data' : 'ok',
          records: recs.length,
          workouts: works.length,
          perType: perType,
          sources: sources);
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
