import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../database/database.dart';
import '../features/dashboard/day_data.dart';
import '../features/health_integration/health_service.dart';
import '../services/health/plan_service.dart';

final dbProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

final settingsProvider = StreamProvider<Map<String, String>>(
    (ref) => ref.watch(dbProvider).watchSettings());

final userProvider =
    StreamProvider<User?>((ref) => ref.watch(dbProvider).watchUser());

final weightsProvider = StreamProvider<List<WeightEntry>>(
    (ref) => ref.watch(dbProvider).watchWeights());

final selectedDayProvider =
    StateProvider<DateTime>((ref) => dayStart(DateTime.now()));

final tabProvider = StateProvider<int>((ref) => 0);

final dayDataProvider = StreamProvider.family<DayData, String>((ref, key) {
  final db = ref.watch(dbProvider);
  return reactive(db, () => loadDayData(db, key), name: 'день $key', ignore: const {'connected_sources'});
});

final rangeStatsProvider =
    StreamProvider.family<Map<String, DayStat>, ({String from, String to})>(
        (ref, r) {
  final db = ref.watch(dbProvider);
  return reactive(db, () => computeRangeStats(db, r.from, r.to),
      name: 'статистика ${r.from}..${r.to}', ignore: const {'connected_sources'});
});

final healthServiceProvider =
    Provider<HealthService>((ref) => HealthService(ref.watch(dbProvider)));

final syncBusyProvider = StateProvider<bool>((ref) => false);

final sourceProvider = StreamProvider<ConnectedSource?>((ref) {
  final svc = ref.watch(healthServiceProvider);
  return ref.watch(dbProvider).watchSource(svc.sourceType);
});

/// Прогресс первичной загрузки справочника продуктов (null — не выполняется).
final catalogProgressProvider = StateProvider<double?>((ref) => null);

/// Расчёт норм (BMR, TDEE, КБЖУ, тренд веса, предложение адаптации).
final planProvider = StreamProvider<PlanSnapshot>((ref) {
  final db = ref.watch(dbProvider);
  return reactive(db, () => loadPlan(db, DateTime.now()), name: 'план',
      ignore: const {'connected_sources', 'activity_records', 'workouts'});
});
