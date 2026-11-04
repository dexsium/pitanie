import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/app.dart' show notificationsProvider;
import '../../../../app/providers.dart';
import '../../../../app/theme.dart';
import '../../../../core/dates.dart';
import '../../../../shared/widgets.dart';
import '../../data/health_repository.dart';
import '../../domain/models/health_models.dart';
import '../../services/hrv_analysis_service.dart';
import '../../services/recovery_analysis_service.dart';
import '../../../wearables/heart_rate_page.dart';

String _dm(DateTime d) => DateFormat('d MMM, HH:mm', 'ru').format(d);

class HealthAnalysisPage extends ConsumerWidget {
  const HealthAnalysisPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(healthProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Анализ здоровья'), actions: [
        IconButton(
          tooltip: 'Настройки мониторинга',
          icon: const Icon(Icons.tune),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const HealthSettingsPage())),
        ),
      ]),
      body: snap == null
          ? const Center(child: CircularProgressIndicator())
          : _Body(snap),
    );
  }
}

class _Body extends ConsumerWidget {
  final HealthSnapshot s;
  const _Body(this.s);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final db = ref.read(dbProvider);
    final r = s.results;
    final restingNow = s.days.where((d) => d.resting != null).isEmpty
        ? null
        : s.days.where((d) => d.resting != null).last;

    Widget stat(String label, String value, {String? sub}) => Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 2),
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800))),
            if (sub != null)
              Text(sub, style: TextStyle(fontSize: 11, color: muted)),
          ]),
        );

    Widget title(String t, IconData i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(i, color: kPrimary, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
        );

    final recLevel = r.recovery.level;
    final recTitle = switch (recLevel) {
      RecoveryLevel.insufficient => 'Недостаточно данных',
      RecoveryLevel.normal => 'Близко к привычному уровню',
      RecoveryLevel.lighter => 'Рассмотрите более лёгкую нагрузку',
      RecoveryLevel.focus => 'Уделите внимание восстановлению',
    };
    final sleepNight = s.sleepToday.night;
    final nap = s.sleepToday.nap;
    String dur(int m) => '${m ~/ 60} ч ${m % 60} мин';
    final hrvLatest = r.hrv.available && r.hrv.latest != null
        ? '${fmt0(r.hrv.latest!)} мс'
        : null;

    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                'Оздоровительный мониторинг по данным часов, не медицинская диагностика. '
                'Выводы строятся относительно вашей личной нормы.',
                style: TextStyle(fontSize: 12.5, color: muted)),
          ),
          AppCard(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HeartRatePage())),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title('Сегодня', Icons.monitor_heart_outlined),
              Row(children: [
                stat('Последний пульс',
                    s.lastHr == null ? '—' : '${fmt0(s.lastHr!.v)} уд/мин',
                    sub: s.lastHr == null ? null : _dm(s.lastHr!.at)),
                stat(
                    'Пульс в покое',
                    restingNow?.resting == null
                        ? '—'
                        : '${fmt0(restingNow!.resting!)} уд/мин',
                    sub: restingNow == null
                        ? 'нет данных'
                        : '${s.restingFromWatch ? 'часы' : 'расчёт'}, ${DateFormat('d MMM', 'ru').format(restingNow.day)}'),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                stat('HRV', hrvLatest ?? 'нет данных',
                    sub: hrvLatest == null
                        ? 'часы не передают'
                        : hrvMetricLabel(r.hrv.metric!)),
                stat('SpO₂',
                    r.spo2.latest == null ? '—' : '${fmt0(r.spo2.latest!.v)} %',
                    sub: r.spo2.latest == null ? null : _dm(r.spo2.latest!.at)),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                stat('Стресс',
                    s.stressLast == null ? 'нет данных' : fmt0(s.stressLast!.v),
                    sub: s.stressLast == null
                        ? 'включите мониторинг в настройках часов'
                        : _dm(s.stressLast!.at)),
                stat(
                    'Дыхание во сне',
                    s.respLast == null
                        ? 'нет данных'
                        : '${fmt0(s.respLast!.v)} вдохов/мин',
                    sub: s.respLast == null ? null : _dm(s.respLast!.at)),
              ]),
              const SizedBox(height: 10),
              Text(
                  s.lastData == null
                      ? 'Данных от часов ещё нет: подключите часы и дождитесь синхронизации.'
                      : 'Обновлено: ${_dm(s.lastData!)}',
                  style: TextStyle(fontSize: 12, color: muted)),
            ]),
          ),
          const SizedBox(height: 14),
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title('Восстановление', Icons.self_improvement_outlined),
              Text(recTitle,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(r.recovery.recommendation),
              if (r.recovery.factors.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final f in r.recovery.factors)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• $f', style: TextStyle(color: muted)),
                  ),
              ],
              const SizedBox(height: 10),
              Text('Самочувствие сегодня',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final (n, label) in const [
                  (1, 'Хорошее'),
                  (2, 'Обычное'),
                  (3, 'Плохое')
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: s.feeling == n,
                    onSelected: (_) =>
                        db.setSetting(kHmFeel, '${dayKey(DateTime.now())}|$n'),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Использовано: ${r.recovery.used.isEmpty ? '—' : r.recovery.used.join(', ')}. '
                  '${r.recovery.hrvUsed ? '' : 'HRV не используется. '}'
                  'Это внутренняя экспериментальная оценка приложения, а не медицинский показатель.',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ]),
          ),
          const SizedBox(height: 14),
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title('Сон', Icons.nightlight_outlined),
              if (sleepNight == null)
                Text('Данных о ночном сне за сегодня нет.',
                    style: TextStyle(color: muted))
              else ...[
                Row(children: [
                  stat('Ночной сон', dur(sleepNight.sleepMin),
                      sub:
                          '${fmtTime(sleepNight.start)}–${fmtTime(sleepNight.end)}'),
                  stat(
                      'Ночной пульс',
                      s.days
                              .where((d) =>
                                  d.night != null &&
                                  d.day == dayStart(DateTime.now()))
                              .isEmpty
                          ? '—'
                          : '${fmt0(s.days.firstWhere((d) => d.night != null && d.day == dayStart(DateTime.now())).night!)} уд/мин'),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  stat('Дневной сон', nap == null ? 'нет' : dur(nap.sleepMin),
                      sub: nap == null
                          ? null
                          : '${fmtTime(nap.start)}–${fmtTime(nap.end)}'),
                  stat('Ночная HRV', hrvLatest ?? 'нет данных'),
                ]),
              ],
              const SizedBox(height: 8),
              Text(
                  '${r.sleep.note}. Стадии сна определяются часами приблизительно.',
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ]),
          ),
          const SizedBox(height: 14),
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title('Выводы и рекомендации', Icons.lightbulb_outline),
              if (s.insights.isEmpty)
                Text(
                    'Сейчас устойчивых отклонений от вашей личной нормы нет. '
                    '${r.hr.baseline == null ? r.hr.note : ''}',
                    style: TextStyle(color: muted)),
              for (final i in s.insights) _InsightTile(i),
              if (s.history.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('История уведомлений',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final h in s.history.reversed.take(10))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _InsightTile(h.insight,
                        sentAt: h.sentAt, compact: true),
                  ),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          _ChartCard(
              title: 'Пульс в покое, 30 дней',
              unit: 'уд/мин',
              points: [
                for (final d in s.days)
                  if (d.resting != null && s.now.difference(d.day).inDays <= 30)
                    (d.day, d.resting!)
              ],
              note:
                  'Расчёт по минутным значениям пульса вне движения и тренировок.'),
          const SizedBox(height: 14),
          _ChartCard(
              title: 'HRV, 30 дней',
              unit: 'мс',
              points: [
                for (final d in s.hrvDaily)
                  if (s.now.difference(d.day).inDays <= 30) (d.day, d.v)
              ],
              note: 'Часы по текущему каналу HRV не передают.'),
          const SizedBox(height: 14),
          _ChartCard(
              title: 'SpO₂',
              unit: '%',
              points: [
                for (final p
                    in s.spo2.where((p) => s.now.difference(p.at).inDays <= 14))
                  (p.at, p.v)
              ],
              note:
                  'Одиночные измерения часов недостоверны: смотрите на повторяющиеся значения.'),
          const SizedBox(height: 14),
          _ChartCard(
              title: 'Продолжительность сна, 14 дней',
              unit: 'ч',
              bars: true,
              points: [
                for (final n in r.sleep.nights)
                  if (s.now.difference(n.day).inDays <= 14)
                    (n.day, n.sleepMin / 60)
              ],
              note: 'Ночной сон по данным часов.'),
          const SizedBox(height: 14),
          _ChartCard(
              title: 'Нагрузка: шаги, 14 дней',
              unit: '',
              bars: true,
              points: [
                for (final d in s.stepsDaily)
                  if (s.now.difference(d.day).inDays <= 14) (d.day, d.v)
              ],
              note: 'Тренировки по этому каналу часы не передают.'),
          const SizedBox(height: 14),
          AppCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title('Какие данные доступны', Icons.watch_outlined),
              for (final c in s.capabilities)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            switch (c.state) {
                              Availability.available =>
                                Icons.check_circle_outline,
                              Availability.stale => Icons.history,
                              Availability.awaitingSync => Icons.sync,
                              Availability.unsupported => Icons.block,
                            },
                            size: 20,
                            color: c.state == Availability.unsupported
                                ? muted
                                : kPrimary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${c.label} — ${switch (c.state) {
                                      Availability.available => 'доступен',
                                      Availability.stale => 'данные устарели',
                                      Availability.awaitingSync =>
                                        'ожидается синхронизация',
                                      Availability.unsupported => 'недоступен',
                                    }}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '${c.detail}${c.last == null ? '' : ' Последние: ${_dm(c.last!)}.'}',
                                    style: TextStyle(
                                        fontSize: 11.5, color: muted)),
                              ]),
                        ),
                      ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          Text(
              'При тяжёлых симптомах (одышка, боль в груди, спутанность сознания) не ориентируйтесь на '
              'часы: вызовите скорую помощь.',
              style: TextStyle(fontSize: 12, color: muted)),
        ]);
  }
}

class _InsightTile extends StatelessWidget {
  final Insight i;
  final DateTime? sentAt;
  final bool compact;
  const _InsightTile(this.i, {this.sentAt, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              switch (i.severity) {
                Severity.info => Icons.info_outline,
                Severity.advice => Icons.lightbulb_outline,
                Severity.attention => Icons.priority_high,
                Severity.urgent => Icons.warning_amber_rounded,
              },
              size: 18,
              color: kPrimary),
          const SizedBox(width: 6),
          Expanded(
              child: Text(i.title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 13.5 : 15))),
          if (sentAt != null)
            Text(DateFormat('d.MM HH:mm').format(sentAt!),
                style: TextStyle(fontSize: 11, color: muted)),
        ]),
        if (!compact) ...[
          const SizedBox(height: 2),
          Text(i.body),
        ],
        Text(
            '${severityLabel(i.severity)} · ${categoryLabel(i.category)} · основание: ${i.basis.join(', ')} · '
            'период: ${i.period} · достоверность: ${i.confidence}',
            style: TextStyle(fontSize: 11, color: muted)),
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title, unit, note;
  final List<(DateTime, double)> points;
  final bool bars;
  const _ChartCard(
      {required this.title,
      required this.unit,
      required this.points,
      required this.note,
      this.bars = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final pts = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    final t0 = pts.isEmpty ? DateTime.now() : pts.first.$1;
    double x(DateTime d) => d.difference(t0).inMinutes / 1440.0;
    final ys = pts.map((p) => p.$2);
    final lo = ys.isEmpty ? 0.0 : ys.reduce((a, b) => a < b ? a : b);
    final hi = ys.isEmpty ? 1.0 : ys.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo).abs() < 1 ? 1.0 : (hi - lo) * 0.15;
    final minY = bars ? 0.0 : lo - pad, maxY = hi + pad;
    final span = pts.isEmpty ? 1.0 : (x(pts.last.$1)).clamp(1.0, 400.0);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (pts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: Text('Нет данных', style: TextStyle(color: muted))),
          )
        else
          SizedBox(
            height: 150,
            child: bars
                ? BarChart(BarChartData(
                    minY: minY,
                    maxY: maxY,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: _titles(muted, t0, span, x),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF263238),
                        getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                            '${fmt1(r.toY)} $unit'.trim(),
                            const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                    ),
                    barGroups: [
                      for (final p in pts)
                        BarChartGroupData(x: x(p.$1).round(), barRods: [
                          BarChartRodData(
                              toY: p.$2,
                              width: 10,
                              color: kPrimary,
                              borderRadius: BorderRadius.circular(4))
                        ])
                    ],
                  ))
                : LineChart(LineChartData(
                    minY: minY,
                    maxY: maxY,
                    minX: 0,
                    maxX: span,
                    gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: muted.withOpacity(0.18),
                            strokeWidth: 1,
                            dashArray: [4, 4])),
                    borderData: FlBorderData(show: false),
                    titlesData: _titles(muted, t0, span, x),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => const Color(0xFF263238),
                        getTooltipItems: (spots) => [
                          for (final sp in spots)
                            LineTooltipItem(
                                '${fmt1(sp.y)} $unit'.trim(),
                                const TextStyle(
                                    color: Colors.white, fontSize: 12))
                        ],
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [for (final p in pts) FlSpot(x(p.$1), p.$2)],
                        isCurved: false,
                        color: kPrimary,
                        barWidth: 2.5,
                        dotData: FlDotData(show: pts.length < 40),
                      ),
                    ],
                  )),
          ),
        const SizedBox(height: 6),
        Text(note, style: TextStyle(fontSize: 11.5, color: muted)),
      ]),
    );
  }

  FlTitlesData _titles(
          Color muted, DateTime t0, double span, double Function(DateTime) x) =>
      FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            getTitlesWidget: (v, meta) => v == meta.max || v == meta.min
                ? const SizedBox()
                : Text(v >= 100 ? fmt0(v) : fmt1(v).replaceAll(',0', ''),
                    style: TextStyle(fontSize: 10, color: muted)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: (span / 4).ceilToDouble().clamp(1, 100),
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  DateFormat('d.MM').format(t0.add(Duration(days: v.round()))),
                  style: TextStyle(fontSize: 10, color: muted)),
            ),
          ),
        ),
      );
}

/// Настройки мониторинга: категории уведомлений, тихие часы, пороги, приватность.
class HealthSettingsPage extends ConsumerWidget {
  const HealthSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(settingsProvider).valueOrNull ?? {};
    final p = parsePrefs(st);
    final db = ref.read(dbProvider);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    Future<void> pickQuiet(bool from) async {
      final cur = from ? p.quietFromMin : p.quietToMin;
      final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
      if (t == null) return;
      final v = t.hour * 60 + t.minute;
      await db.setSetting(kHmQuiet,
          '${fmtHm(from ? v : p.quietFromMin)}|${fmtHm(from ? p.quietToMin : v)}');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки мониторинга')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Автоматический анализ'),
              subtitle: const Text(
                  'Проверка после синхронизации часов, при запуске и возврате в приложение. '
                  'Фоновых задач нет: при закрытом приложении анализ не выполняется.'),
              value: p.auto,
              onChanged: (v) async {
                await db.setSetting(kHmAuto, v ? '1' : '0');
                if (v)
                  await ref.read(notificationsProvider).requestPermission();
              },
            ),
            for (final c in HealthCategory.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Уведомления: ${categoryLabel(c).toLowerCase()}'),
                value: p.enabled(c),
                onChanged: p.auto
                    ? (v) => db.setSetting(hmCatKey(c), v ? '1' : '0')
                    : null,
              ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Частота информационных уведомлений',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Раз в день')),
                ButtonSegment(value: 7, label: Text('Раз в неделю')),
              ],
              selected: {p.infoEveryDays},
              onSelectionChanged: (v) =>
                  db.setSetting(kHmInfoDays, '${v.first}'),
            ),
            const Divider(height: 28),
            const Text('Тихие часы',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
                'В это время обычные уведомления откладываются. Срочные рекомендации показываются всегда.',
                style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => pickQuiet(true),
                      child: Text('С ${fmtHm(p.quietFromMin)}'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => pickQuiet(false),
                      child: Text('До ${fmtHm(p.quietToMin)}'))),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Приватный режим'),
              subtitle: const Text('Без подробностей на экране блокировки'),
              value: p.privacy,
              onChanged: (v) => db.setSetting(kHmPrivacy, v ? '1' : '0'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Персональные пороги',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Повышение пульса покоя: от ${p.hrMinDelta.round()} уд/мин над вашей нормой'),
            Slider(
              min: 3,
              max: 15,
              divisions: 12,
              value: p.hrMinDelta,
              onChanged: (v) => db.setSetting(kHmHrDelta, '$v'),
            ),
            Text('Достаточный сон: от ${fmt1(p.sleepMinHours)} ч'),
            Slider(
              min: 4,
              max: 9,
              divisions: 10,
              value: p.sleepMinHours,
              onChanged: (v) => db.setSetting(kHmSleepH, '$v'),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: _NotesField(
              initial: st[kHmNotes] ?? '',
              onSave: (v) => db.setSetting(kHmNotes, v)),
        ),
        const SizedBox(height: 14),
        Text(
            'Все данные анализа хранятся только на этом устройстве и никуда не отправляются. '
            'Это оздоровительный мониторинг, не медицинская диагностика.',
            style: TextStyle(fontSize: 12, color: muted)),
      ]),
    );
  }
}

class _NotesField extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onSave;
  const _NotesField({required this.initial, required this.onSave});

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Заметки для интерпретации (необязательно)',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            'Например: приём препаратов, влияющих на пульс, ограничения нагрузки, рекомендации врача. '
            'Хранится только на устройстве; расчёты по этой записи не меняются.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          maxLines: 3,
          onChanged: widget.onSave,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ]);
}
