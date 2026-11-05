import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../calendar/calendar_page.dart';
import 'pending_workouts.dart';
import '../health_analysis/presentation/pages/health_analysis_page.dart';
import '../sleep/sleep_page.dart';
import '../wearables/heart_rate_page.dart';

/// Размеры экрана заданы в пикселях макета (ширина 852) и масштабируются по ширине устройства.
const _mockWidth = 852.0;
const defaultStepsGoal = 10000.0;
const _stepsGoalKey = 'steps_goal';
const _p = Color(0xFF6F2BD8);
const _pl = Color(0xFF9145EC);
const _pd = Color(0xFF4F1CB0);

class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final key = dayKey(day);
    final a = ref.watch(dayDataProvider(key)).valueOrNull?.activity;
    final week = ref
        .watch(rangeStatsProvider((from: dayKey(day.subtract(const Duration(days: 6))), to: key)))
        .valueOrNull;
    final goal = double.tryParse(
            ref.watch(settingsProvider).valueOrNull?[_stepsGoalKey] ?? '') ??
        defaultStepsGoal;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final db = ref.read(dbProvider);

    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final hasData = a != null && (a.hasData || a.sleepMinutes > 0);

    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);

    final shadow = [
      BoxShadow(
          color: Colors.black.withOpacity(dark ? 0 : 0.07),
          blurRadius: s(26),
          offset: Offset(0, s(8)))
    ];

    void shift(int d) => ref.read(selectedDayProvider.notifier).state =
        DateTime(day.year, day.month, day.day + d);

    Future<void> editGoal() async {
      final v = await promptNumber(context, 'Цель по шагам',
          initial: goal, suffix: 'шагов', min: 1000, max: 100000);
      if (v != null) await db.setSetting(_stepsGoalKey, '${v.round()}');
    }

    Widget cardBox({required Widget child, EdgeInsets? padding, double radius = 30, VoidCallback? onTap}) =>
        Container(
          decoration: BoxDecoration(
              color: card, borderRadius: BorderRadius.circular(s(radius)), boxShadow: shadow),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(s(radius)),
            child: InkWell(
              borderRadius: BorderRadius.circular(s(radius)),
              onTap: onTap,
              child: Padding(padding: padding ?? EdgeInsets.all(s(24)), child: child),
            ),
          ),
        );

    Widget topButton(IconData i, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: s(66),
            height: s(82),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s(24)),
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [const Color(0xFF2A2440), const Color(0xFF221D36)]
                      : [Colors.white, const Color(0xFFE9E1FA)]),
              boxShadow: [
                BoxShadow(
                    color: _p.withOpacity(dark ? 0 : 0.25),
                    blurRadius: s(18),
                    offset: Offset(0, s(6)))
              ],
            ),
            child: Icon(i, size: s(40), color: _p),
          ),
        );

    Widget metric(IconData icon, Color color, String value, String label, IconData mark,
            {VoidCallback? onTap}) =>
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
            height: s(150),
            decoration: BoxDecoration(
                color: card, borderRadius: BorderRadius.circular(s(30)), boxShadow: shadow),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(s(30)),
              child: Stack(children: [
                Positioned(
                    right: s(18),
                    top: s(18),
                    bottom: s(10),
                    child: Icon(mark, size: s(96), color: muted.withOpacity(0.14))),
                Padding(
                  padding: EdgeInsets.fromLTRB(s(34), s(16), s(14), s(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, size: s(46), color: color),
                    const Spacer(),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(value, style: t(36, w: FontWeight.w800))),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: t(24))),
                  ]),
                ),
              ]),
            ),
          ),
          ),
        );

    final steps = hasData ? a.steps : 0.0;
    final pct = goal <= 0 ? 0.0 : (steps / goal).clamp(0.0, 1.0);
    final sleepTxt = !hasData || a.sleepMinutes <= 0
        ? '—'
        : '${a.sleepMinutes ~/ 60} ч ${(a.sleepMinutes % 60).round()} м';

    // Шаги по дням недели для диаграммы
    final days = [for (var i = 0; i < 7; i++) day.subtract(Duration(days: 6 - i))];
    final stepsByDay = [
      for (final d in days) week?[dayKey(d)]?.act.steps ?? 0.0,
    ];
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (stepsByDay[i] > stepsByDay[best]) best = i;
    }
    final maxStep = stepsByDay.reduce((x, y) => x > y ? x : y);
    final maxY = [goal, (maxStep / 2500).ceil() * 2500.0, 10000.0].reduce((x, y) => x > y ? x : y);
    const wd = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    return ColoredBox(
      color: dark ? Colors.transparent : const Color(0xFFF1F1F6),
      child: ListView(padding: EdgeInsets.fromLTRB(s(22), s(20), s(22), s(24)), children: [
        // Шапка
        SizedBox(
          height: s(96),
          child: Stack(children: [
            Row(children: [
              topButton(Icons.calendar_month_outlined, () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CalendarPage()))),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(
                      onTap: () => shift(-1),
                      child: Icon(Icons.chevron_left, size: s(46), color: ink)),
                  SizedBox(width: s(30)),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(dayTitle(day), style: t(40, w: FontWeight.w800)),
                    Text(dayDateLine(day), style: t(22, c: muted)),
                  ]),
                  SizedBox(width: s(30)),
                  GestureDetector(
                      onTap: () => shift(1),
                      child: Icon(Icons.chevron_right, size: s(46), color: ink)),
                ]),
              ),
              SizedBox(width: s(66)),
            ]),
          ]),
        ),
        SizedBox(height: s(14)),

        // Кольцо шагов и цель
        cardBox(
          radius: 40,
          padding: EdgeInsets.fromLTRB(s(24), s(10), s(30), s(10)),
          child: SizedBox(
            height: s(220),
            child: Row(children: [
              SizedBox(
                width: s(240),
                height: s(220),
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                      width: s(226),
                      height: s(226),
                      child: CustomPaint(painter: _RingPainter(pct, s(18), dark))),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.directions_walk, size: s(44), color: _p),
                    SizedBox(
                      width: s(150),
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(hasData ? fmt0(steps) : '—', style: t(54, w: FontWeight.w800))),
                    ),
                    Text('шагов', style: t(23)),
                  ]),
                ]),
              ),
              SizedBox(width: s(18)),
              Container(width: 1, height: s(180), color: muted.withOpacity(0.25)),
              SizedBox(width: s(44)),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: editGoal,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      Icon(Icons.bar_chart_rounded, size: s(54), color: _p),
                      SizedBox(width: s(22)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('Цель по шагам', style: t(22))),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(fmt0(goal), style: t(38, w: FontWeight.w800))),
                        ]),
                      ),
                      SizedBox(width: s(10)),
                      Container(
                        width: s(78),
                        height: s(78),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(s(22)),
                          gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_p.withOpacity(0.10), _p.withOpacity(0.24)]),
                        ),
                        child: Icon(Icons.gps_fixed, size: s(44), color: _p),
                      ),
                    ]),
                    SizedBox(height: s(24)),
                    LayoutBuilder(builder: (context, box) {
                      final w = box.maxWidth;
                      final fill = (w * pct).clamp(s(18), w);
                      return SizedBox(
                        height: s(22),
                        child: Stack(alignment: Alignment.centerLeft, children: [
                          Container(
                              height: s(14),
                              decoration: BoxDecoration(
                                  color: muted.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(s(7)))),
                          Container(
                              width: fill,
                              height: s(14),
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [_p, _pl]),
                                  borderRadius: BorderRadius.circular(s(7)))),
                          Positioned(
                              left: 0,
                              child: Container(
                                  width: s(20),
                                  height: s(20),
                                  decoration: const BoxDecoration(
                                      color: _p, shape: BoxShape.circle))),
                        ]),
                      );
                    }),
                    SizedBox(height: s(16)),
                    Text('${(pct * 100).floor()} %', style: t(29)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        SizedBox(height: s(20)),

        // Показатели
        Row(children: [
          metric(Icons.location_on, _p, hasData ? '${fmt1(a.distanceKm)} км' : '—',
              'Расстояние', Icons.route),
          SizedBox(width: s(20)),
          metric(Icons.local_fire_department, kOrange,
              hasData && a.activeKcal > 0 ? '${fmt0(a.activeKcal)} ккал' : '—',
              'Активные калории', Icons.local_fire_department),
        ]),
        SizedBox(height: s(19)),
        Row(children: [
          metric(Icons.schedule, kBlue, hasData ? '${fmt0(a.workoutMinutes)} мин' : '—',
              'Тренировки', Icons.fitness_center),
          SizedBox(width: s(20)),
          metric(Icons.nightlight_round, kViolet, sleepTxt, 'Сон', Icons.bed_outlined,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SleepPage(day: day)))),
        ]),
        SizedBox(height: s(19)),
        Row(children: [
          metric(
              Icons.favorite,
              kRed,
              hasData && a.avgHr != null ? '${fmt0(a.avgHr!)} / ${fmt0(a.maxHr!)}' : '—',
              'Пульс (средний / макс.)',
              Icons.monitor_heart_outlined),
          SizedBox(width: s(20)),
          metric(Icons.add_circle_outline, kBlue,
              hasData && a.spo2 != null ? '${fmt0(a.spo2!)} %' : '—',
              'SpO₂ (последнее)', Icons.water_drop),
        ]),
        SizedBox(height: s(20)),

        if (hasData && a.sleepStart != null && a.sleepMinutes > 0)
          Padding(
            padding: EdgeInsets.only(bottom: s(24)),
            child: cardBox(
              padding: EdgeInsets.symmetric(horizontal: s(26), vertical: s(18)),
              child: Row(children: [
                Icon(Icons.info_outline, size: s(46), color: _p),
                SizedBox(width: s(20)),
                Expanded(
                  child: Text(
                      'Сон: ${fmtTime(a.sleepStart!)} — ${fmtTime(a.sleepEnd!)}. Фазы (приблизительно): '
                      'глубокий ${fmt0(a.sleepDeepMin)} мин, REM ${fmt0(a.sleepRemMin)} мин, '
                      'лёгкий ${fmt0(a.sleepLightMin)} мин. Разбивка по фазам — оценка по данным '
                      'часов, а не точное измерение.',
                      style: t(20)),
                ),
              ]),
            ),
          ),

        // График пульса
        GestureDetector(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const HeartRatePage())),
          child: Container(
            height: s(84),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s(42)),
              gradient: const LinearGradient(colors: [Color(0xFF5B21C8), Color(0xFF7B3AE6)]),
              boxShadow: [
                BoxShadow(
                    color: _p.withOpacity(0.30),
                    blurRadius: s(18),
                    offset: Offset(0, s(8)))
              ],
            ),
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                  child: Padding(
                padding: EdgeInsets.only(left: s(480), right: s(80)),
                child: CustomPaint(painter: _EcgPainter()),
              )),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: s(40)),
                child: Row(children: [
                  Icon(Icons.show_chart, size: s(48), color: Colors.white),
                  SizedBox(width: s(22)),
                  Text('График пульса', style: t(31, w: FontWeight.w700, c: Colors.white)),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: s(44), color: Colors.white),
                ]),
              ),
            ]),
          ),
        ),
        SizedBox(height: s(20)),
        cardBox(
          radius: 40,
          padding: EdgeInsets.symmetric(horizontal: s(34), vertical: s(24)),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const HealthAnalysisPage())),
          child: Row(children: [
            Icon(Icons.insights_outlined, size: s(52), color: _p),
            SizedBox(width: s(24)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Анализ здоровья', style: t(31, w: FontWeight.w800)),
                Text('Пульс покоя, сон, SpO₂, восстановление', style: t(22, c: muted)),
              ]),
            ),
            Icon(Icons.chevron_right, size: s(44), color: muted),
          ]),
        ),
        SizedBox(height: s(26)),

        // Тренировки
        const PendingWorkouts(),
        _Workouts(
          workouts: a?.workouts ?? const [],
          card: card,
          shadow: shadow,
          s: s,
          t: t,
          muted: muted,
        ),
        SizedBox(height: s(24)),

        // Шаги за 7 дней
        cardBox(
          radius: 36,
          padding: EdgeInsets.fromLTRB(s(30), s(24), s(30), s(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.bar_chart_rounded, size: s(54), color: _p),
              SizedBox(width: s(18)),
              Text('Шаги за 7 дней', style: t(34, w: FontWeight.w800)),
            ]),
            SizedBox(height: s(14)),
            SizedBox(
              height: s(200),
              child: BarChart(BarChartData(
                maxY: maxY,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(
                    show: true,
                    border: Border(bottom: BorderSide(color: muted.withOpacity(0.35)))),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF263238),
                    getTooltipItem: (g, gi, r, ri) => BarTooltipItem('${fmt0(r.toY)} шагов',
                        const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: s(96),
                      interval: maxY / 4,
                      getTitlesWidget: (v, meta) => Padding(
                        padding: EdgeInsets.only(right: s(14)),
                        child: Text(fmt0(v),
                            textAlign: TextAlign.right, style: t(21, c: muted)),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: s(44),
                      getTitlesWidget: (v, _) => Padding(
                        padding: EdgeInsets.only(top: s(10)),
                        child: Text(wd[days[v.toInt()].weekday - 1], style: t(22)),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < 7; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: stepsByDay[i],
                        width: s(62),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(s(16))),
                        gradient: (i == best && stepsByDay[i] > 0) || i == 6
                            ? const LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [_p, _pl])
                            : null,
                        color: (i == best && stepsByDay[i] > 0) || i == 6
                            ? null
                            : _p.withOpacity(dark ? 0.30 : 0.16),
                      ),
                    ]),
                ],
              )),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Workouts extends StatefulWidget {
  final List<Workout> workouts;
  final Color card, muted;
  final List<BoxShadow> shadow;
  final double Function(double) s;
  final TextStyle Function(double, {FontWeight w, Color? c}) t;
  const _Workouts(
      {required this.workouts,
      required this.card,
      required this.shadow,
      required this.s,
      required this.t,
      required this.muted});

  @override
  State<_Workouts> createState() => _WorkoutsState();
}

class _WorkoutsState extends State<_Workouts> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.s, t = widget.t;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: s(12), vertical: s(8)),
          child: Row(children: [
            Icon(Icons.fitness_center, size: s(46), color: _p),
            SizedBox(width: s(22)),
            Expanded(child: Text('Тренировки', style: t(34, w: FontWeight.w800))),
            Icon(_open ? Icons.expand_more : Icons.chevron_right, size: s(44)),
          ]),
        ),
      ),
      if (_open) ...[
        SizedBox(height: s(10)),
        if (widget.workouts.isEmpty)
          Container(
            height: s(84),
            decoration: BoxDecoration(
                color: widget.card,
                borderRadius: BorderRadius.circular(s(30)),
                boxShadow: widget.shadow),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.directions_run, size: s(64), color: widget.muted.withOpacity(0.45)),
              SizedBox(width: s(34)),
              Text('Тренировок за день нет', style: t(25)),
            ]),
          ),
        for (final w in widget.workouts)
          Padding(
            padding: EdgeInsets.only(bottom: s(12)),
            child: Container(
              padding: EdgeInsets.all(s(22)),
              decoration: BoxDecoration(
                  color: widget.card,
                  borderRadius: BorderRadius.circular(s(30)),
                  boxShadow: widget.shadow),
              child: Row(children: [
                Icon(Icons.directions_run, size: s(48), color: _p),
                SizedBox(width: s(20)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(workoutLabel(w.workoutType), style: t(27, w: FontWeight.w700)),
                    Text(
                      '${fmtTime(w.startTime)}–${fmtTime(w.endTime)} · ${fmt0(w.endTime.difference(w.startTime).inMinutes)} мин'
                      '${w.energyKcal != null ? ' · ${fmt0(w.energyKcal!)} ккал' : ''}'
                      '${w.distanceM != null ? ' · ${fmt1(w.distanceM! / 1000)} км' : ''}'
                      '${w.avgHr != null ? ' · пульс ${fmt0(w.avgHr!)}/${fmt0(w.maxHr!)}' : ''}',
                      style: t(21, c: widget.muted),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// Кольцо прогресса шагов: бледная дорожка и фиолетовая дуга по фактическому проценту цели.
class _RingPainter extends CustomPainter {
  final double progress, stroke;
  final bool dark;
  _RingPainter(this.progress, this.stroke, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = dark ? const Color(0xFF2E2E3A) : const Color(0xFFE8E0FA));
    // Даже при очень малом проценте рисуется точка-скругление, чтобы начало было видно.
    final sweep = (2 * 3.141592653589793 * progress).clamp(0.02, 2 * 3.141592653589793);
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -3.141592653589793 / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..shader = SweepGradient(
            startAngle: -3.141592653589793 / 2,
            endAngle: 3 * 3.141592653589793 / 2,
            colors: const [_pl, _p, _pd],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.stroke != stroke || o.dark != dark;
}

/// Бледная линия ЭКГ на кнопке «График пульса».
class _EcgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, w = size.width;
    final p = Path()
      ..moveTo(0, h * 0.55)
      ..lineTo(w * 0.22, h * 0.55)
      ..lineTo(w * 0.30, h * 0.70)
      ..lineTo(w * 0.38, h * 0.40)
      ..lineTo(w * 0.46, h * 0.55)
      ..lineTo(w * 0.52, h * 0.15)
      ..lineTo(w * 0.60, h * 0.95)
      ..lineTo(w * 0.68, h * 0.5)
      ..lineTo(w * 0.78, h * 0.62)
      ..lineTo(w * 0.86, h * 0.50)
      ..lineTo(w, h * 0.55);
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withOpacity(0.35));
  }

  @override
  bool shouldRepaint(_EcgPainter o) => false;
}
