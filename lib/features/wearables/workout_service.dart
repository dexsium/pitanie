// Автоопределение тренировок по пульсу: поиск, уведомление, подтверждение пользователем.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../database/database.dart';
import '../dashboard/day_data.dart' show mainSourceOf;
import 'workout_detector.dart';

const kWorkoutPendingKey = 'wk_pending';
const kWorkoutSeenKey = 'wk_seen';
const kDetectedSource = 'detected';

List<DetectedWorkout> pendingWorkouts(Map<String, String> settings) {
  try {
    final l = jsonDecode(settings[kWorkoutPendingKey] ?? '[]') as List;
    return [
      for (final j in l)
        DetectedWorkout.fromJson((j as Map).cast<String, dynamic>())
    ];
  } catch (_) {
    return const [];
  }
}

Set<int> _seen(Map<String, String> settings) {
  try {
    return {
      for (final x in jsonDecode(settings[kWorkoutSeenKey] ?? '[]') as List)
        x as int
    };
  } catch (_) {
    return {};
  }
}

Future<void> _save(
    AppDatabase db, List<DetectedWorkout> pending, Set<int> seen) async {
  final s = seen.toList()..sort();
  await db.setSetting(
      kWorkoutPendingKey, jsonEncode([for (final p in pending) p.toJson()]));
  await db.setSetting(kWorkoutSeenKey,
      jsonEncode(s.length > 60 ? s.sublist(s.length - 60) : s));
}

int _age(DateTime birth, DateTime now) {
  var a = now.year - birth.year;
  if (now.month < birth.month ||
      (now.month == birth.month && now.day < birth.day)) a--;
  return a;
}

/// Ищет тренировки за последние сутки. О каждой новой отправляет уведомление
/// через [notify] и кладёт её в список «ждёт подтверждения». Возвращает число новых.
Future<int> scanWorkouts(AppDatabase db,
    Future<void> Function(int id, String title, String body) notify) async {
  final settings = await db.allSettings();
  final now = DateTime.now();
  final from = now.subtract(const Duration(hours: 30));
  final main = mainSourceOf(settings);
  final recs = await db.activityBetween(from, now);

  var hrRecs = recs.where((r) => r.type == 'heartRate').toList();
  if (main != null) {
    final m = hrRecs.where((r) => r.source == main).toList();
    if (m.isNotEmpty) hrRecs = m;
  }
  if (hrRecs.isEmpty) return 0;

  final rest = recs.where((r) => r.type == 'restingHeartRate').toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final user = await db.getUser();
  final age = user?.birthDate == null ? null : _age(user!.birthDate!, now);
  final threshold = workoutThreshold(
      rest: rest.isEmpty ? null : rest.last.value.round(), age: age);

  final found = detectWorkouts([
    for (final r in hrRecs) (t: r.startTime, bpm: r.value),
  ], threshold: threshold);

  final seen = _seen(settings);
  final pending = pendingWorkouts(settings);
  final existing = await db.workoutsBetween(from, now);
  // Тренировка, которую часы записали сами, важнее найденной по пульсу.
  pending.removeWhere((p) => existing
      .any((e) => e.startTime.isBefore(p.end) && e.endTime.isAfter(p.start)));
  var added = 0;
  for (final w in found) {
    if (existing.any(
        (e) => e.startTime.isBefore(w.end) && e.endTime.isAfter(w.start))) {
      continue;
    }
    final i = pending.indexWhere((p) => p.key == w.key);
    if (i >= 0) {
      pending[i] = w; // тренировка ещё идёт или данные дополнились
      continue;
    }
    if (seen.contains(w.key)) continue;
    pending.add(w);
    seen.add(w.key);
    added++;
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    await notify(
        9001,
        'Похоже на тренировку',
        '${hm(w.start)}–${hm(w.end)}, средний пульс ${w.avgHr.round()}, '
            'максимум ${w.maxHr.round()}. Откройте «Активность» и подтвердите.');
  }
  await _save(db, pending, seen);
  return added;
}

/// Пользователь подтвердил тренировку: сохраняем её с выбранным типом.
Future<void> confirmWorkout(
    AppDatabase db, DetectedWorkout w, String type) async {
  final user = await db.getUser();
  final weights = await db.allWeights();
  double? kcal;
  if (weights.isNotEmpty && user?.birthDate != null) {
    final last =
        weights.reduce((a, b) => a.measuredAt.isAfter(b.measuredAt) ? a : b);
    kcal = workoutKcal(
        avgHr: w.avgHr,
        weightKg: last.weightKg,
        age: _age(user!.birthDate!, DateTime.now()),
        female: user.sex == 'female',
        minutes: w.minutes);
  }
  await db.upsertWorkouts([
    WorkoutsCompanion.insert(
      source: kDetectedSource,
      sourceName: const Value('По пульсу часов'),
      externalRecordId: 'det-${w.key}',
      workoutType: type,
      startTime: w.start,
      endTime: w.end,
      energyKcal: Value(kcal),
      avgHr: Value(w.avgHr),
      maxHr: Value(w.maxHr),
    )
  ]);
  await dismissWorkout(db, w);
}

/// Убирает тренировку из списка ожидающих (подтверждена или отклонена).
Future<void> dismissWorkout(AppDatabase db, DetectedWorkout w) async {
  final settings = await db.allSettings();
  final pending = pendingWorkouts(settings)..removeWhere((p) => p.key == w.key);
  final seen = _seen(settings)..add(w.key);
  await _save(db, pending, seen);
}
