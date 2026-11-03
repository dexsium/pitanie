import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

/// Изменение веса за период: разница между последним замером и последним
/// замером на момент начала периода (или первым замером внутри периода).
double? weightChange(List<WeightEntry> ws, Duration period, DateTime now) {
  if (ws.length < 2) return null;
  final start = now.subtract(period);
  final before = ws.where((w) => !w.measuredAt.isAfter(start)).toList();
  final base = before.isNotEmpty
      ? before.last
      : ws.firstWhere((w) => w.measuredAt.isAfter(start), orElse: () => ws.first);
  if (identical(base, ws.last)) return null;
  return ws.last.weightKg - base.weightKg;
}

class WeightPage extends ConsumerWidget {
  const WeightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final user = ref.watch(userProvider).valueOrNull;
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final wk = weightChange(ws, const Duration(days: 7), now);
    final mo = weightChange(ws, const Duration(days: 30), now);
    String d(double? v) => v == null ? '—' : '${v >= 0 ? '+' : ''}${fmt1(v)} кг';

    Widget stat(String l, String v) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Вес')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, db, null, ws.isEmpty ? null : ws.last.weightKg),
        icon: const Icon(Icons.add),
        label: const Text('Замер'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        AppCard(
          child: Column(children: [
            Row(children: [
              stat('Начальный', ws.isEmpty ? '—' : '${fmt1(ws.first.weightKg)} кг'),
              stat('Текущий', ws.isEmpty ? '—' : '${fmt1(ws.last.weightKg)} кг'),
              stat('Цель', user?.targetWeightKg == null ? '—' : '${fmt1(user!.targetWeightKg!)} кг'),
            ]),
            const Divider(height: 24),
            Row(children: [
              stat('Всего', ws.length < 2 ? '—' : d(ws.last.weightKg - ws.first.weightKg)),
              stat('За неделю', d(wk)),
              stat('За месяц', d(mo)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: SizedBox(
            height: 200,
            child: ws.length < 2
                ? const EmptyHint('Добавьте минимум два замера для графика')
                : LineChart(LineChartData(
                    gridData: const FlGridData(drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, m) => Text(fmtAuto(v), style: const TextStyle(fontSize: 10)))),
                      bottomTitles: const AxisTitles(),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < ws.length; i++) FlSpot(i.toDouble(), ws[i].weightKg)
                        ],
                        isCurved: true,
                        color: kPrimary,
                        barWidth: 3,
                        belowBarData: BarAreaData(show: true, color: kPrimary.withOpacity(0.12)),
                      ),
                    ],
                    extraLinesData: user?.targetWeightKg == null
                        ? null
                        : ExtraLinesData(horizontalLines: [
                            HorizontalLine(
                                y: user!.targetWeightKg!,
                                color: kGreen,
                                dashArray: [6, 4],
                                strokeWidth: 1.5)
                          ]),
                  )),
          ),
        ),
        const SizedBox(height: 14),
        if (ws.isEmpty) const EmptyHint('Замеров пока нет'),
        for (final w in ws.reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${fmt1(w.weightKg)} кг'),
            subtitle: Text('${fullDate(w.measuredAt)}, ${fmtTime(w.measuredAt)}'),
            onTap: () => _edit(context, db, w, w.weightKg),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmDialog(context, 'Удалить замер?', '${fmt1(w.weightKg)} кг', ok: 'Удалить')) {
                  await db.deleteWeight(w.id);
                }
              },
            ),
          ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, AppDatabase db, WeightEntry? e, double? initial) async {
    final ctrl = TextEditingController(text: initial == null ? '' : fmtAuto(initial));
    var at = e?.measuredAt ?? DateTime.now();
    final form = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(e == null ? 'Новый замер' : 'Изменить замер'),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(suffixText: 'кг'),
                validator: numValidator(min: 20, max: 400, allowZero: false),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${shortDate(at)}  ${fmtTime(at)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: ctx, initialDate: at, firstDate: DateTime(2000), lastDate: DateTime.now());
                  if (d == null) return;
                  final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(at));
                  set(() => at = DateTime(d.year, d.month, d.day, t?.hour ?? at.hour, t?.minute ?? at.minute));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final kg = parseNum(ctrl.text)!;
                if (e == null) {
                  await db.addWeight(at, kg);
                } else {
                  await db.updateWeight(e.id, at, kg);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
