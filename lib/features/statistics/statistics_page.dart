import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../dashboard/day_data.dart';

/// Размеры заданы в пикселях макета (ширина 851) и масштабируются по ширине устройства.
const _mockWidth = 851.0;
const _p = Color(0xFF6F2BD8);
const _pl = Color(0xFF9145EC);
const _orange = Color(0xFFFF9500);
const _blue = Color(0xFF1E8EF7);
const _green = Color(0xFF34C759);

enum _Period { day, week, month }

class _M {
  final double k;
  final bool dark;
  final ColorScheme cs;
  const _M(this.k, this.dark, this.cs);
  double s(double v) => v * k;
  Color get accent => dark ? _pl : _p;
  Color get card => dark ? const Color(0xFF1C1C26) : Colors.white;
  TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
      TextStyle(fontSize: s(px), fontWeight: w, color: c ?? cs.onSurface, height: 1.2);

  List<BoxShadow> get shadow => dark
      ? const []
      : [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: s(22), offset: Offset(0, s(8)))];

  Widget tile(IconData i, Color c, {double size = 64}) => Container(
        width: s(size),
        height: s(size),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s(size * 0.3)),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [c.withOpacity(dark ? 0.18 : 0.10), c.withOpacity(dark ? 0.32 : 0.24)]),
          boxShadow: dark
              ? null
              : [BoxShadow(color: c.withOpacity(0.14), blurRadius: s(8), offset: Offset(0, s(3)))],
        ),
        child: Icon(i, size: s(size * 0.52), color: dark ? c.withOpacity(0.95) : c),
      );

  Widget box({required Widget child, EdgeInsets? padding, double radius = 34}) => Container(
        padding: padding,
        decoration: BoxDecoration(
            color: card, borderRadius: BorderRadius.circular(s(radius)), boxShadow: shadow),
        child: child,
      );
}

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});
  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  _Period _p0 = _Period.week;

  DateTime _shiftMonth(DateTime d, int n) {
    final last = DateTime(d.year, d.month + n + 1, 0).day;
    return DateTime(d.year, d.month + n, d.day > last ? last : d.day);
  }

  void _step(int dir) {
    final d = ref.read(selectedDayProvider);
    ref.read(selectedDayProvider.notifier).state = switch (_p0) {
      _Period.day => DateTime(d.year, d.month, d.day + dir),
      _Period.week => DateTime(d.year, d.month, d.day + 7 * dir),
      _Period.month => _shiftMonth(d, dir),
    };
  }

  Future<void> _pick() async {
    final d = ref.read(selectedDayProvider);
    final r = await showDatePicker(
        context: context,
        initialDate: d,
        firstDate: DateTime(2015),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        locale: const Locale('ru'));
    if (r != null) ref.read(selectedDayProvider.notifier).state = dayStart(r);
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedDayProvider);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final m = _M(MediaQuery.sizeOf(context).width / _mockWidth, dark, cs);
    final s = m.s;

    Widget seg(_Period v, String label) {
      final on = _p0 == v;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _p0 = v),
          child: Container(
            margin: EdgeInsets.all(s(4)),
            decoration: on
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(s(40)),
                    gradient: const LinearGradient(colors: [Color(0xFF5B21C8), Color(0xFF7B3AE6)]),
                    boxShadow: [
                      BoxShadow(
                          color: _p.withOpacity(0.35),
                          blurRadius: s(14),
                          offset: Offset(0, s(6)))
                    ])
                : null,
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (on) ...[
                  Icon(Icons.check, size: s(38), color: Colors.white),
                  SizedBox(width: s(14)),
                ],
                Text(label,
                    style: m.t(30, w: on ? FontWeight.w600 : FontWeight.w500, c: on ? Colors.white : null)),
              ]),
            ),
          ),
        ),
      );
    }

    Widget topBtn(IconData i, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: s(76),
            height: s(76),
            decoration: BoxDecoration(
                color: dark ? _p.withOpacity(0.25) : Colors.white,
                borderRadius: BorderRadius.circular(s(24)),
                boxShadow: m.shadow),
            child: Icon(i, size: s(42), color: m.accent),
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
          color: dark ? const Color(0xFF101017) : const Color(0xFFF1F1F6)),
      child: ListView(
        padding: EdgeInsets.fromLTRB(s(28), s(16), s(28), s(28)),
        children: [
          Padding(
            padding: EdgeInsets.only(left: s(8), top: s(8), bottom: s(24)),
            child: Text('Статистика', style: m.t(52, w: FontWeight.w800)),
          ),
          Container(
            height: s(78),
            decoration: BoxDecoration(
                color: m.card,
                borderRadius: BorderRadius.circular(s(40)),
                border: Border.all(
                    color: dark ? Colors.white24 : const Color(0xFFD9D9E3), width: 1.5),
                boxShadow: m.shadow),
            child: Row(children: [
              seg(_Period.day, 'День'),
              seg(_Period.week, 'Неделя'),
              seg(_Period.month, 'Месяц'),
            ]),
          ),
          SizedBox(height: s(34)),
          SizedBox(
            height: s(86),
            child: Row(children: [
              topBtn(Icons.calendar_month_outlined, _pick),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(
                      onTap: () => _step(-1),
                      child: Icon(Icons.chevron_left, size: s(48), color: cs.onSurface)),
                  SizedBox(width: s(40)),
                  GestureDetector(
                    onTap: () => ref.read(selectedDayProvider.notifier).state =
                        dayStart(DateTime.now()),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(dayTitle(sel), style: m.t(38, w: FontWeight.w800)),
                      Text(dayDateLine(sel), style: m.t(24, c: cs.onSurface.withOpacity(0.6))),
                    ]),
                  ),
                  SizedBox(width: s(40)),
                  GestureDetector(
                      onTap: () => _step(1),
                      child: Icon(Icons.chevron_right, size: s(48), color: cs.onSurface)),
                ]),
              ),
              SizedBox(width: s(76)),
            ]),
          ),
          SizedBox(height: s(30)),
          switch (_p0) {
            _Period.day => _Day(m, dayKey(sel)),
            _Period.week => _Week(m, sel),
            _Period.month => _Month(m, sel, _step),
          },
        ],
      ),
    );
  }
}

// ───────────────────────── День ─────────────────────────

class _Day extends ConsumerWidget {
  final _M m;
  final String keyStr;
  const _Day(this.m, this.keyStr);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(dayDataProvider(keyStr)).valueOrNull;
    if (d == null) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    final s = m.s;
    final n = d.eaten;
    final a = d.activity;

    Widget row(IconData i, Color c, String l, String v) => SizedBox(
          height: s(58),
          child: Row(children: [
            m.tile(i, c, size: 54),
            SizedBox(width: s(22)),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(l, style: m.t(28)))),
            SizedBox(width: s(12)),
            Flexible(
              flex: 2,
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(v, style: m.t(28, w: FontWeight.w700))),
            ),
          ]),
        );
    Widget divider() => Padding(
          padding: EdgeInsets.symmetric(vertical: s(10)),
          child: Divider(height: 1, thickness: 1.2, color: m.cs.onSurface.withOpacity(0.12)),
        );

    return m.box(
      radius: 36,
      child: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(s(28), s(20), s(28), s(16)),
          decoration: BoxDecoration(
              color: m.accent.withOpacity(m.dark ? 0.10 : 0.04),
              borderRadius: BorderRadius.vertical(top: Radius.circular(s(36)))),
          child: Row(children: [
            m.tile(Icons.event_note_outlined, _p, size: 66),
            SizedBox(width: s(22)),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(fullDate(parseDayKey(keyStr)), style: m.t(36, w: FontWeight.w800)))),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(s(26), s(6), s(26), s(26)),
          child: Column(children: [
            row(Icons.local_fire_department_outlined, _orange, 'Калории',
                '${fmt0(n.calories)} / ${fmt0(d.calorieTarget)} ккал'),
            row(Icons.fitness_center, _p, 'Белки', '${fmt0(n.proteins)} / ${fmt0(d.goal.proteins)} г'),
            row(Icons.water_drop_outlined, _orange, 'Жиры', '${fmt0(n.fats)} / ${fmt0(d.goal.fats)} г'),
            row(Icons.grass, _orange, 'Углеводы', '${fmt0(n.carbs)} / ${fmt0(d.goal.carbs)} г'),
            divider(),
            row(Icons.restaurant, _p, Meal.breakfast.label, '${fmt0(d.mealTotal('breakfast').calories)} ккал'),
            row(Icons.ramen_dining_outlined, _p, Meal.lunch.label, '${fmt0(d.mealTotal('lunch').calories)} ккал'),
            row(Icons.room_service_outlined, _p, Meal.dinner.label, '${fmt0(d.mealTotal('dinner').calories)} ккал'),
            row(Icons.apple_outlined, _p, Meal.snack.label, '${fmt0(d.mealTotal('snack').calories)} ккал'),
            divider(),
            row(Icons.water_drop_outlined, _p, 'Вода', '${fmt0(d.plainWaterMl)} / ${fmt0(d.goal.waterMl)} мл'),
            row(Icons.directions_run, _p, 'Шаги', fmt0(a.steps)),
            row(Icons.bolt_outlined, _p, 'Активные калории', '${fmt0(a.activeKcal)} ккал'),
            row(Icons.fitness_center, _p, 'Тренировки',
                a.workouts.isEmpty ? 'нет' : '${a.workouts.length} (${fmt0(a.workoutMinutes)} мин)'),
            row(Icons.monitor_weight_outlined, _p, 'Вес', d.weight == null ? '—' : '${fmt1(d.weight!)} кг'),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Неделя ─────────────────────────

class _Week extends ConsumerWidget {
  final _M m;
  final DateTime end;
  const _Week(this.m, this.end);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = end.subtract(const Duration(days: 6));
    final stats = ref.watch(rangeStatsProvider((from: dayKey(start), to: dayKey(end)))).valueOrNull;
    if (stats == null) {
      return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
    }
    final list = [for (var i = 0; i < 7; i++) stats[dayKey(start.add(Duration(days: i)))]!];
    final labels = [for (final s in list) DateFormat('E', 'ru').format(parseDayKey(s.key))];
    final g = list.last.goal;
    Widget card(String title, IconData icon, String unit, Color c, List<double> v, {double? goal}) =>
        Padding(
          padding: EdgeInsets.only(bottom: m.s(26)),
          child: _SeriesCard(m,
              title: title, icon: icon, unit: unit, color: c, values: v, labels: labels, goal: goal),
        );
    return Column(children: [
      card('Калории', Icons.local_fire_department_outlined, 'ккал', _orange,
          [for (final s in list) s.n.calories], goal: g.calories),
      card('Белки', Icons.fitness_center, 'г', _blue, [for (final s in list) s.n.proteins],
          goal: g.proteins),
      card('Жиры', Icons.water_drop_outlined, 'г', _orange, [for (final s in list) s.n.fats],
          goal: g.fats),
      card('Углеводы', Icons.grass, 'г', _p, [for (final s in list) s.n.carbs], goal: g.carbs),
      card('Вода', Icons.water_drop_outlined, 'мл', _blue, [for (final s in list) s.waterMl],
          goal: g.waterMl),
      card('Шаги', Icons.directions_run, '', _p, [for (final s in list) s.act.steps]),
      card('Активные калории', Icons.bolt_outlined, 'ккал', _green,
          [for (final s in list) s.act.activeKcal]),
    ]);
  }
}

class _SeriesCard extends StatelessWidget {
  final _M m;
  final String title, unit;
  final IconData icon;
  final Color color;
  final List<double> values;
  final List<String> labels;
  final double? goal;
  const _SeriesCard(this.m,
      {required this.title,
      required this.icon,
      required this.unit,
      required this.color,
      required this.values,
      required this.labels,
      this.goal});

  @override
  Widget build(BuildContext context) {
    final s = m.s;
    final withData = values.where((v) => v > 0).toList();
    final avg = withData.isEmpty ? 0.0 : withData.reduce((a, b) => a + b) / withData.length;
    final avgText = fmt0(avg);
    final maxV = [...values, goal ?? 0].reduce((a, b) => a > b ? a : b);
    final top = maxV <= 0 ? 1.0 : maxV * 1.08;
    final areaH = s(150);
    final pale = _p.withOpacity(m.dark ? 0.28 : 0.13);
    final u = unit.isEmpty ? '' : ' $unit';

    return m.box(
      radius: 34,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(34)),
        child: Stack(children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: CustomPaint(
                size: Size(s(250), s(120)),
                painter: _WavePainter(color.withOpacity(m.dark ? 0.12 : 0.13))),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(s(28), s(22), s(28), s(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                m.tile(icon, color, size: 70),
                SizedBox(width: s(24)),
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(title, style: m.t(36, w: FontWeight.w800)))),
                SizedBox(width: s(10)),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: s(26), vertical: s(14)),
                    decoration: BoxDecoration(
                        color: pale, borderRadius: BorderRadius.circular(s(34))),
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('среднее: $avgText$u', style: m.t(26, w: FontWeight.w500))),
                  ),
                ),
              ]),
              SizedBox(height: s(14)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 36,
                  child: Padding(
                    padding: EdgeInsets.only(top: s(20)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: avgText, style: m.t(60, w: FontWeight.w800)),
                          if (unit.isNotEmpty)
                            TextSpan(text: ' $unit', style: m.t(40, w: FontWeight.w800)),
                        ])),
                      ),
                      SizedBox(height: s(6)),
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Среднее за неделю',
                              style: m.t(26, c: m.cs.onSurface.withOpacity(0.6)))),
                    ]),
                  ),
                ),
                SizedBox(width: s(14)),
                Expanded(
                  flex: 64,
                  child: Column(children: [
                    SizedBox(
                      height: areaH,
                      child: Stack(children: [
                        if (goal != null && goal! > 0)
                          Positioned.fill(
                            child: CustomPaint(
                                painter: _DashPainter(
                                    y: areaH * (1 - goal! / top),
                                    color: color,
                                    unit: m.k)),
                          ),
                        Row(children: [
                          for (var i = 0; i < values.length; i++)
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: values[i] <= 0
                                    ? Container(
                                        width: s(44),
                                        height: s(14),
                                        decoration: BoxDecoration(
                                            color: pale,
                                            borderRadius: BorderRadius.circular(s(8))))
                                    : Container(
                                        width: s(46),
                                        height: (values[i] / top * areaH).clamp(s(14), areaH),
                                        decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(s(12)),
                                            gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [color, color.withOpacity(0.78)])),
                                      ),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                    SizedBox(height: s(8)),
                    Row(children: [
                      for (var i = 0; i < labels.length; i++)
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(labels[i],
                                  softWrap: false,
                                  style: m.t(26,
                                      w: i == labels.length - 1 ? FontWeight.w700 : FontWeight.w400,
                                      c: i == labels.length - 1
                                          ? null
                                          : m.cs.onSurface.withOpacity(0.55))),
                            ),
                          ),
                        ),
                    ]),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final double y, unit;
  final Color color;
  _DashPainter({required this.y, required this.color, required this.unit});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.4 * unit.clamp(0.6, 1.4)
      ..strokeCap = StrokeCap.round;
    final dash = 13 * unit, gap = 10 * unit;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.y != y || o.color != color || o.unit != unit;
}

class _WavePainter extends CustomPainter {
  final Color color;
  _WavePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.15)
      ..cubicTo(size.width * 0.25, size.height * 0.15, size.width * 0.5, size.height * 0.6,
          size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(colors: [color, color.withOpacity(0)])
              .createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.color != color;
}

// ───────────────────────── Месяц ─────────────────────────

class _Month extends ConsumerWidget {
  final _M m;
  final DateTime sel;
  final void Function(int) step;
  const _Month(this.m, this.sel, this.step);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = m.s;
    final first = DateTime(sel.year, sel.month, 1);
    final last = DateTime(sel.year, sel.month + 1, 0);
    final stats = ref.watch(rangeStatsProvider((from: dayKey(first), to: dayKey(last)))).valueOrNull;
    final days = stats?.values.toList() ?? const <DayStat>[];
    final withFood = days.where((d) => d.hasFood).toList();
    final weights = days.where((d) => d.weight != null).toList();
    final met = withFood.where((d) => d.met).length;
    double avg(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    final today = dayStart(DateTime.now());
    final lead = first.weekday - 1;
    final cells = <DateTime?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= last.day; d++) DateTime(sel.year, sel.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final grey = m.cs.onSurface.withOpacity(0.55);

    Widget cell(DateTime? d) {
      if (d == null) return const Expanded(child: SizedBox());
      final st = stats?[dayKey(d)];
      final isSel = isSameDay(d, sel);
      final isToday = isSameDay(d, today);
      final Color? bg = st == null
          ? null
          : st.met
              ? _green.withOpacity(m.dark ? 0.30 : 0.25)
              : st.hasFood
                  ? _orange.withOpacity(m.dark ? 0.30 : 0.28)
                  : null;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(selectedDayProvider.notifier).state = d,
          child: Center(
            child: Container(
              width: s(82),
              height: s(82),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg,
                  border: isSel || isToday
                      ? Border.all(color: isSel ? m.accent : m.accent.withOpacity(0.45), width: s(4))
                      : null),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${d.day}',
                    style: m.t(30,
                        w: isSel || isToday || (st?.hasFood ?? false)
                            ? FontWeight.w700
                            : FontWeight.w500)),
              ),
            ),
          ),
        ),
      );
    }

    Widget navBtn(IconData i, int dir) => GestureDetector(
          onTap: () => step(dir),
          child: Container(
            width: s(62),
            height: s(62),
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: m.accent.withOpacity(m.dark ? 0.22 : 0.10)),
            child: Icon(i, size: s(38), color: m.cs.onSurface),
          ),
        );

    Widget stat(IconData i, Color c, String l, String v) => SizedBox(
          height: s(62),
          child: Row(children: [
            m.tile(i, c, size: 56),
            SizedBox(width: s(22)),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(l, style: m.t(27)))),
            SizedBox(width: s(10)),
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(8)),
                  decoration: BoxDecoration(
                      color: m.accent.withOpacity(m.dark ? 0.22 : 0.08),
                      borderRadius: BorderRadius.circular(s(26))),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(v, style: m.t(29, w: FontWeight.w700))),
                ),
              ),
            ),
          ]),
        );
    Widget line() => Divider(height: 1, thickness: 1, color: m.cs.onSurface.withOpacity(0.10));

    final delta = weights.length < 2 ? null : weights.last.weight! - weights.first.weight!;
    final monthName = toBeginningOfSentenceCase(DateFormat('LLLL yyyy', 'ru').format(first));

    return Column(children: [
      m.box(
        radius: 36,
        padding: EdgeInsets.fromLTRB(s(32), s(26), s(32), s(26)),
        child: Column(children: [
          Row(children: [
            Icon(Icons.calendar_month_outlined, size: s(46), color: m.accent),
            SizedBox(width: s(22)),
            Expanded(
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(monthName, style: m.t(36, w: FontWeight.w800)))),
            navBtn(Icons.chevron_left, -1),
            SizedBox(width: s(22)),
            navBtn(Icons.chevron_right, 1),
          ]),
          SizedBox(height: s(26)),
          Row(children: [
            for (final w in ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
              Expanded(
                  child: Center(
                      child: FittedBox(
                          fit: BoxFit.scaleDown, child: Text(w, style: m.t(26, c: grey))))),
          ]),
          SizedBox(height: s(16)),
          for (var r = 0; r < cells.length ~/ 7; r++)
            SizedBox(
              height: s(78),
              child: Row(children: [for (var c = 0; c < 7; c++) cell(cells[r * 7 + c])]),
            ),
        ]),
      ),
      SizedBox(height: s(26)),
      m.box(
        radius: 36,
        padding: EdgeInsets.fromLTRB(s(26), s(14), s(26), s(14)),
        child: Column(children: [
          stat(Icons.calendar_month_outlined, _p, 'Дней с записями', '${withFood.length} из ${days.length}'),
          line(),
          stat(Icons.local_fire_department_outlined, _orange, 'Среднесуточная калорийность',
              '${fmt0(avg(withFood.map((d) => d.n.calories)))} ккал'),
          line(),
          stat(Icons.fitness_center, _p, 'Среднее количество белка',
              '${fmt0(avg(withFood.map((d) => d.n.proteins)))} г'),
          line(),
          stat(Icons.water_drop_outlined, _p, 'Среднее количество жиров',
              '${fmt0(avg(withFood.map((d) => d.n.fats)))} г'),
          line(),
          stat(Icons.grass, _orange, 'Среднее количество углеводов',
              '${fmt0(avg(withFood.map((d) => d.n.carbs)))} г'),
          line(),
          stat(Icons.monitor_weight_outlined, _p, 'Изменение веса',
              delta == null ? '—' : '${delta >= 0 ? '+' : ''}${fmt1(delta)} кг'),
          line(),
          stat(Icons.track_changes, _p, 'Дней с выполненной нормой',
              withFood.isEmpty ? '—' : '${(met * 100 / withFood.length).round()}% ($met)'),
        ]),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(s(12), s(18), s(12), 0),
        child: Text('Норма выполнена, если калории в пределах 90–110% цели дня.',
            style: m.t(22, c: grey)),
      ),
    ]);
  }
}
