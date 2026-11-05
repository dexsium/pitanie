import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import 'strength_math.dart';
import 'training_repo.dart';

enum _Metric { maxWeight, volume, est1Rm, reps }

/// Прогресс по упражнению за неделю, месяц, три месяца и год.
class StrengthProgressPage extends ConsumerStatefulWidget {
  const StrengthProgressPage({super.key});
  @override
  ConsumerState<StrengthProgressPage> createState() =>
      _StrengthProgressPageState();
}

class _StrengthProgressPageState extends ConsumerState<StrengthProgressPage> {
  List<LiftExercise> _ex = [];
  int? _exId;
  int _days = 90;
  _Metric _metric = _Metric.maxWeight;
  List<ExercisePoint> _pts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = TrainingRepo(ref.read(dbProvider));
    final all = await repo.exercises();
    // Только упражнения, по которым есть записи.
    final sets =
        await ref.read(dbProvider).select(ref.read(dbProvider).liftSets).get();
    final used = sets.map((s) => s.exerciseId).toSet();
    _ex = all.where((e) => used.contains(e.id)).toList();
    _exId = _ex.isEmpty ? null : _ex.first.id;
    await _reload();
  }

  Future<void> _reload() async {
    if (_exId != null) {
      _pts = await TrainingRepo(ref.read(dbProvider))
          .progress(_exId!, DateTime.now().subtract(Duration(days: _days)));
    }
    if (mounted) setState(() => _loading = false);
  }

  double? _value(ExercisePoint p) => switch (_metric) {
        _Metric.maxWeight => p.maxWeight,
        _Metric.volume => p.volume > 0 ? p.volume : null,
        _Metric.est1Rm => p.est1Rm,
        _Metric.reps => p.reps.toDouble(),
      };

  String get _unit => _metric == _Metric.reps ? 'повт.' : 'кг';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final from = DateTime.now().subtract(Duration(days: _days));
    final spots = <FlSpot>[];
    final values = <double>[];
    for (final p in _pts) {
      final v = _value(p);
      if (v == null) continue;
      spots.add(FlSpot(p.date.difference(from).inHours / 24.0, v));
      values.add(v);
    }
    final change = changePercent(values);
    return Scaffold(
      appBar: AppBar(title: const Text('Прогресс силы')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ex.isEmpty
              ? const EmptyHint(
                  'Пока нет сохранённых тренировок. Прогресс появится после первой.')
              : ListView(padding: const EdgeInsets.all(16), children: [
                  DropdownButtonFormField<int>(
                    value: _exId,
                    decoration: const InputDecoration(labelText: 'Упражнение'),
                    items: [
                      for (final e in _ex)
                        DropdownMenuItem(value: e.id, child: Text(e.name))
                    ],
                    onChanged: (v) async {
                      _exId = v;
                      await _reload();
                    },
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('Нед.')),
                      ButtonSegment(value: 30, label: Text('Мес.')),
                      ButtonSegment(value: 90, label: Text('3 мес.')),
                      ButtonSegment(value: 365, label: Text('Год')),
                    ],
                    selected: {_days},
                    onSelectionChanged: (s) async {
                      _days = s.first;
                      await _reload();
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    for (final m in _Metric.values)
                      ChoiceChip(
                        label: Text(switch (m) {
                          _Metric.maxWeight => 'Макс. вес',
                          _Metric.volume => 'Объём',
                          _Metric.est1Rm => '1ПМ (оценка)',
                          _Metric.reps => 'Повторения',
                        }),
                        selected: _metric == m,
                        onSelected: (_) => setState(() => _metric = m),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  AppCard(
                    child: spots.length < 2
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                                child: Text(
                                    spots.isEmpty
                                        ? 'Нет данных по этому показателю за период'
                                        : 'Нужно минимум две тренировки, чтобы показать динамику',
                                    textAlign: TextAlign.center,
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant))))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                SizedBox(
                                  height: 220,
                                  child: LineChart(LineChartData(
                                    minX: 0,
                                    maxX: _days.toDouble(),
                                    gridData: const FlGridData(
                                        drawVerticalLine: false),
                                    borderData: FlBorderData(show: false),
                                    titlesData: FlTitlesData(
                                      topTitles: const AxisTitles(),
                                      rightTitles: const AxisTitles(),
                                      leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 44,
                                              getTitlesWidget: (v, m) => Text(
                                                  fmt0(v),
                                                  style: const TextStyle(
                                                      fontSize: 11)))),
                                      bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: true,
                                              interval: _days / 4,
                                              reservedSize: 24,
                                              getTitlesWidget: (v, m) =>
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 6),
                                                    child: Text(
                                                        DateFormat('d.MM').format(
                                                            from.add(Duration(
                                                                hours: (v * 24)
                                                                    .round()))),
                                                        style: const TextStyle(
                                                            fontSize: 11)),
                                                  ))),
                                    ),
                                    lineBarsData: [
                                      LineChartBarData(
                                          spots: spots,
                                          color: kPrimary,
                                          barWidth: 3,
                                          dotData: const FlDotData(show: true)),
                                    ],
                                  )),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    'Первое значение ${fmtAuto(values.first)} $_unit, последнее ${fmtAuto(values.last)} $_unit'
                                    '${change == null ? '' : ' (${change >= 0 ? '+' : ''}${fmt1(change)}%)'}. '
                                    'Точек: ${values.length}.',
                                    style: const TextStyle(fontSize: 13)),
                              ]),
                  ),
                  const SizedBox(height: 10),
                  Text(
                      'Макс. вес — фактический рабочий вес. 1ПМ — оценка по формуле Эпли '
                      '(вес × (1 + повторения / 30)), считается только для подходов 1–12 повторений '
                      'с внешним весом и не является измерением.',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
    );
  }
}
