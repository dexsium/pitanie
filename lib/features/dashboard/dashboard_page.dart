import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../shared/widgets.dart';
import '../activity/activity_page.dart' show defaultStepsGoal;
import '../ads/ad_slot.dart';
import '../ads/ads_models.dart';
import '../calendar/calendar_page.dart';
import '../coach/coach_card.dart';
import '../settings/settings_page.dart';
import '../water/water_page.dart';
import '../health_integration/devices_page.dart';
import '../weight/weight_page.dart';
import 'day_data.dart';

/// Размеры экрана заданы в пикселях макета (ширина 851) и масштабируются по ширине устройства.
const _mockWidth = 851.0;
const _p = Color(0xFF6F2BD8);
const _pl = Color(0xFF9145EC);

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    final key = dayKey(day);
    final data = ref.watch(dayDataProvider(key));
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final accent = dark ? _pl : _p;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? cs.onSurface, height: 1.2);

    void shift(int d) => ref.read(selectedDayProvider.notifier).state =
        DateTime(day.year, day.month, day.day + d);

    Widget topBtn(IconData i, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: s(76),
            height: s(76),
            decoration: BoxDecoration(
                color: _p.withOpacity(dark ? 0.25 : 0.10),
                borderRadius: BorderRadius.circular(s(24)),
                boxShadow: [
                  BoxShadow(
                      color: _p.withOpacity(dark ? 0 : 0.12),
                      blurRadius: s(14),
                      offset: Offset(0, s(5)))
                ]),
            child: Icon(i, size: s(42), color: accent),
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF17131F), Color(0xFF101017)]
                : const [Color(0xFFF5F5F8), Color(0xFFF5F5F8)]),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(s(20), s(16), s(20), s(28)),
        children: [
          // Шапка: календарь, день, настройки
          SizedBox(
            height: s(86),
            child: Row(children: [
              SizedBox(width: s(20)),
              topBtn(Icons.calendar_month_outlined, () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CalendarPage()))),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GestureDetector(
                      onTap: () => shift(-1),
                      child: Icon(Icons.chevron_left, size: s(48), color: cs.onSurface)),
                  SizedBox(width: s(44)),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(dayTitle(day), style: t(38, w: FontWeight.w800)),
                    Text(dayDateLine(day), style: t(21, c: cs.onSurface.withOpacity(0.8))),
                  ]),
                  SizedBox(width: s(44)),
                  GestureDetector(
                      onTap: () => shift(1),
                      child: Icon(Icons.chevron_right, size: s(48), color: cs.onSurface)),
                ]),
              ),
              topBtn(Icons.settings_outlined, () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
              SizedBox(width: s(20)),
            ]),
          ),
          SizedBox(height: s(14)),
          const HealthStatusChip(),
          SizedBox(height: s(16)),
          data.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => EmptyHint('Ошибка: $e'),
            data: (d) => _Body(d),
          ),
          const AdSlot(AdPlacement.homeBanner),
        ],
      ),
    );
  }
}

/// Карточка источника данных: Apple Health или Health Connect, состояние и время синхронизации.
class HealthStatusChip extends ConsumerWidget {
  const HealthStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final src = ref.watch(sourceProvider).valueOrNull;
    final busy = ref.watch(syncBusyProvider);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? cs.onSurface, height: 1.2);
    final svc = ref.watch(healthServiceProvider);
    final connected = src != null;
    final color = connected ? const Color(0xFF3CC24F) : const Color(0xFF9CA3AF);
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final last = src?.lastSync;

    return Container(
      height: s(248),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1C26) : Colors.white,
        borderRadius: BorderRadius.circular(s(40)),
        boxShadow: [
          BoxShadow(
              color: _p.withOpacity(dark ? 0 : 0.09), blurRadius: s(28), offset: Offset(0, s(8)))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(s(40)),
        child: InkWell(
          borderRadius: BorderRadius.circular(s(40)),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesPage())),
          child: Row(children: [
            SizedBox(width: s(68)),
            Image.asset('assets/dashboard/watch_card.png',
                width: s(188), height: s(228), fit: BoxFit.contain),
            SizedBox(width: s(42)),
            Container(width: 1, height: s(154), color: cs.onSurfaceVariant.withOpacity(0.25)),
            SizedBox(width: s(34)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: s(40)),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(svc.sourceLabel, style: t(30, w: FontWeight.w800)),
                      ),
                      SizedBox(height: s(10)),
                      Row(children: [
                        Container(
                          width: s(36),
                          height: s(36),
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          child: Icon(connected ? Icons.link : Icons.link_off,
                              size: s(24), color: Colors.white),
                        ),
                        SizedBox(width: s(14)),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                                busy
                                    ? 'Синхронизация…'
                                    : connected
                                        ? 'Подключено'
                                        : 'Не подключено',
                                style: t(26, w: FontWeight.w500, c: color)),
                          ),
                        ),
                      ]),
                      SizedBox(height: s(14)),
                      Divider(height: 1, color: cs.onSurfaceVariant.withOpacity(0.25)),
                      SizedBox(height: s(14)),
                      Row(children: [
                        Icon(Icons.sync, size: s(32), color: cs.onSurface),
                        SizedBox(width: s(8)),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                                connected
                                    ? 'Обновлено: ${last == null ? '—' : hhmm(last)}'
                                    : 'Нажмите, чтобы подключить',
                                style: t(24)),
                          ),
                        ),
                      ]),
                    ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final DayData d;
  const _Body(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eaten = d.eaten;
    final target = d.calorieTarget;
    final left = target - eaten.calories;
    final pct = target > 0 ? eaten.calories / target : 0.0;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final accent = dark ? _pl : _p;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);
    final shadow = [
      BoxShadow(
          color: _p.withOpacity(dark ? 0 : 0.09), blurRadius: s(28), offset: Offset(0, s(8)))
    ];

    Widget cardBox({required Widget child, EdgeInsets? padding, double radius = 44, VoidCallback? onTap}) =>
        Container(
          margin: EdgeInsets.symmetric(horizontal: s(2)),
          decoration: BoxDecoration(
              color: card, borderRadius: BorderRadius.circular(s(radius)), boxShadow: shadow),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(s(radius)),
            child: InkWell(
              borderRadius: BorderRadius.circular(s(radius)),
              onTap: onTap,
              child: Padding(padding: padding ?? EdgeInsets.all(s(28)), child: child),
            ),
          ),
        );

    Widget bar(double value, double goal) {
      final f = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
      return Container(
        height: s(14),
        decoration: BoxDecoration(
            color: muted.withOpacity(0.16), borderRadius: BorderRadius.circular(s(7))),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: f,
          child: Container(
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_pl, _p]),
                  borderRadius: BorderRadius.circular(s(7)))),
        ),
      );
    }

    String pctOf(double v, double g) => g <= 0 ? '0%' : '${(v / g * 100).round()}%';

    Widget macro(IconData icon, String label, double v, double goal) => Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: s(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: s(40), color: accent),
                SizedBox(width: s(12)),
                Flexible(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, style: t(30, w: FontWeight.w800)))),
              ]),
              SizedBox(height: s(8)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: fmt0(v), style: t(38, w: FontWeight.w800)),
                  TextSpan(text: ' / ${fmt0(goal)} г', style: t(26, c: muted)),
                ])),
              ),
              SizedBox(height: s(12)),
              bar(v, goal),
              SizedBox(height: s(8)),
              Align(
                  alignment: Alignment.centerRight,
                  child: Text(pctOf(v, goal), style: t(24))),
            ]),
          ),
        );

    final divider = Container(width: 1, color: muted.withOpacity(0.22));

    Widget mealRow(Meal m, {required bool last}) {
      final n = d.mealTotal(m.name);
      final green = m == Meal.lunch;
      final c = green ? const Color(0xFF3CC24F) : accent;
      final icon = switch (m) {
        Meal.breakfast => Icons.wb_twilight,
        Meal.lunch => Icons.room_service_outlined,
        Meal.dinner => Icons.nightlight_round,
        Meal.snack => Icons.apple,
      };
      return Column(children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: s(8)),
          child: Row(children: [
            Container(
              width: s(88),
              height: s(88),
              decoration: BoxDecoration(
                  color: c.withOpacity(dark ? 0.25 : 0.14),
                  borderRadius: BorderRadius.circular(s(26))),
              child: Icon(icon, size: s(48), color: c),
            ),
            SizedBox(width: s(34)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.label, style: t(32, w: FontWeight.w800)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Б: ${fmt0(n.proteins)} г    Ж: ${fmt0(n.fats)} г    У: ${fmt0(n.carbs)} г',
                      style: t(24, c: muted)),
                ),
              ]),
            ),
            Text('${fmt0(n.calories)} ккал', style: t(28, w: FontWeight.w800)),
            SizedBox(width: s(10)),
            Icon(Icons.chevron_right, size: s(40), color: ink),
          ]),
        ),
        if (!last)
          Padding(
            padding: EdgeInsets.only(left: s(122)),
            child: Divider(height: 1, color: muted.withOpacity(0.2)),
          ),
      ]);
    }

    return Column(children: [
      // Калории и макронутриенты
      cardBox(
        radius: 44,
        padding: EdgeInsets.fromLTRB(s(38), s(24), s(32), s(20)),
        child: Column(children: [
          SizedBox(
            height: s(270),
            child: Row(children: [
              SizedBox(
                width: s(280),
                height: s(270),
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                      size: Size(s(276), s(276)),
                      painter: _RingPainter(pct, s(28), dark)),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${(pct * 100).round()}%', style: t(60, w: FontWeight.w800)),
                    Text(pct > 1 ? 'превышено' : 'выполнено', style: t(24)),
                  ]),
                ]),
              ),
              SizedBox(width: s(26)),
              Container(width: 1, height: s(210), color: muted.withOpacity(0.22)),
              SizedBox(width: s(40)),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.local_fire_department, size: s(46), color: accent),
                        SizedBox(width: s(14)),
                        Text('Калории', style: t(30, w: FontWeight.w800)),
                      ]),
                      SizedBox(height: s(6)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: fmt0(eaten.calories), style: t(66, w: FontWeight.w800)),
                          TextSpan(text: '  / ${fmt0(target)} ккал', style: t(28, c: muted)),
                        ])),
                      ),
                      SizedBox(height: s(14)),
                      Container(
                        height: s(62),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: left >= 0 ? _p.withOpacity(dark ? 0.30 : 0.14) : kRed.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(s(31))),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: s(16)),
                            child: Text(
                                left >= 0
                                    ? 'Осталось: ${fmt0(left)} ккал'
                                    : 'Превышено: ${fmt0(-left)} ккал',
                                style: t(28,
                                    w: FontWeight.w800, c: left >= 0 ? accent : kRed)),
                          ),
                        ),
                      ),
                      if (d.mode.name == 'dynamic')
                        Padding(
                          padding: EdgeInsets.only(top: s(8)),
                          child: Text('Динамическая цель (база ${fmt0(d.goal.calories)})',
                              style: t(20, c: muted)),
                        ),
                    ]),
              ),
            ]),
          ),
          Divider(height: s(30), color: muted.withOpacity(0.2)),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              macro(Icons.fitness_center, 'Белки', eaten.proteins, d.goal.proteins),
              divider,
              macro(Icons.water_drop_outlined, 'Жиры', eaten.fats, d.goal.fats),
              divider,
              macro(Icons.grass, 'Углеводы', eaten.carbs, d.goal.carbs),
            ]),
          ),
        ]),
      ),
      SizedBox(height: s(22)),

      // Подсказка, чем добрать недостающие калории и БЖУ (только для сегодняшнего дня)
      CoachCard(d),

      // Приёмы пищи
      cardBox(
        radius: 44,
        onTap: () => ref.read(tabProvider.notifier).state = 1,
        padding: EdgeInsets.fromLTRB(s(32), s(22), s(26), s(14)),
        child: Column(children: [
          Padding(
            padding: EdgeInsets.only(bottom: s(10)),
            child: Row(children: [
              Icon(Icons.restaurant, size: s(48), color: accent),
              SizedBox(width: s(22)),
              Expanded(child: Text('Приёмы пищи', style: t(36, w: FontWeight.w800))),
              Text('${fmt0(eaten.calories)} ккал', style: t(28, w: FontWeight.w800)),
              SizedBox(width: s(10)),
              Icon(Icons.chevron_right, size: s(40), color: ink),
            ]),
          ),
          for (final (i, m) in Meal.values.indexed) mealRow(m, last: i == Meal.values.length - 1),
        ]),
      ),
      SizedBox(height: s(22)),

      // Вода и активность
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _WaterCard(d)),
          SizedBox(width: s(22)),
          Expanded(child: _ActivityCard(d)),
        ]),
      ),
      SizedBox(height: s(22)),
      const _WeightCard(),
    ]);
  }
}

class _RingPainter extends CustomPainter {
  final double progress, stroke;
  final bool dark;
  _RingPainter(this.progress, this.stroke, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = dark ? const Color(0xFF2E2E3A) : const Color(0xFFE8E8EC));
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        math.max(0.02, 2 * math.pi * p),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..shader = const SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: 3 * math.pi / 2,
            colors: [Color(0xFF4F2BE0), Color(0xFF7A2CF0), Color(0xFFA32AF0)],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.stroke != stroke || o.dark != dark;
}

/// Маленькая карточка со значением, полосой и кнопкой «+» (вода, активность).
class _MiniCard extends StatelessWidget {
  final IconData icon;
  final String title, value, unit;
  final double fraction;
  final VoidCallback onTap, onPlus;
  const _MiniCard(
      {required this.icon,
      required this.title,
      required this.value,
      required this.unit,
      required this.fraction,
      required this.onTap,
      required this.onPlus});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final accent = dark ? _pl : _p;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? cs.onSurface, height: 1.2);
    return Container(
      decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(s(40)),
          boxShadow: [
            BoxShadow(
                color: _p.withOpacity(dark ? 0 : 0.09), blurRadius: s(28), offset: Offset(0, s(8)))
          ]),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(s(40)),
        child: InkWell(
          borderRadius: BorderRadius.circular(s(40)),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(s(36), s(26), s(26), s(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: s(46), color: accent),
                SizedBox(width: s(18)),
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(title, style: t(32, w: FontWeight.w800)))),
                GestureDetector(
                  onTap: onPlus,
                  child: Container(
                    width: s(56),
                    height: s(56),
                    decoration: BoxDecoration(
                        color: _p.withOpacity(dark ? 0.30 : 0.12), shape: BoxShape.circle),
                    child: Icon(Icons.add, size: s(38), color: accent),
                  ),
                ),
              ]),
              SizedBox(height: s(14)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: value, style: t(48, w: FontWeight.w800)),
                  TextSpan(text: ' $unit', style: t(28, c: cs.onSurfaceVariant)),
                ])),
              ),
              SizedBox(height: s(14)),
              Container(
                height: s(14),
                decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(s(7))),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  child: Container(
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_pl, _p]),
                          borderRadius: BorderRadius.circular(s(7)))),
                ),
              ),
              SizedBox(height: s(6)),
              Align(
                  alignment: Alignment.centerRight,
                  child: Text('${(fraction * 100).round()}%', style: t(24))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _WaterCard extends ConsumerWidget {
  final DayData d;
  const _WaterCard(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final ml = d.plainWaterMl;
    final goal = d.goal.waterMl;
    final pct = goal > 0 ? ml / goal : 0.0;

    Future<void> add(double v) async {
      if (!await guardPast(context, d.key)) return;
      await db.addWater(d.key, v);
    }

    void plus() => showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Добавить воды',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final v in [100, 200, 250, 500])
                      ActionChip(
                        label: Text('+$v мл'),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await add(v.toDouble());
                        },
                      ),
                    ActionChip(
                      label: const Text('Другой объём…'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const WaterPage()));
                      },
                    ),
                  ]),
                ]),
              ),
            ));

    return _MiniCard(
      icon: Icons.water_drop_outlined,
      title: 'Вода',
      value: fmt1(ml / 1000),
      unit: '/ ${fmtAuto(goal / 1000)} л',
      fraction: pct,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WaterPage())),
      onPlus: plus,
    );
  }
}

class _ActivityCard extends ConsumerWidget {
  final DayData d;
  const _ActivityCard(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = d.activity;
    final goal = double.tryParse(ref.watch(settingsProvider).valueOrNull?['steps_goal'] ?? '') ??
        defaultStepsGoal;
    final pct = goal > 0 ? a.steps / goal : 0.0;
    void open() => ref.read(tabProvider.notifier).state = 2;
    return _MiniCard(
      icon: Icons.directions_run,
      title: 'Активность',
      value: fmt0(a.steps),
      unit: '/ ${fmt0(goal)} шагов',
      fraction: pct,
      onTap: open,
      onPlus: open,
    );
  }
}

class _WeightCard extends ConsumerWidget {
  const _WeightCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final user = ref.watch(userProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final accent = dark ? _pl : _p;
    final cur = ws.isEmpty ? null : ws.last.weightKg;
    final delta = ws.length < 2 ? null : ws.last.weightKg - ws.first.weightKg;
    final recent = ws.length > 12 ? ws.sublist(ws.length - 12) : ws;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? cs.onSurface, height: 1.2);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: s(2)),
      decoration: BoxDecoration(
          color: dark ? const Color(0xFF1C1C26) : Colors.white,
          borderRadius: BorderRadius.circular(s(40)),
          boxShadow: [
            BoxShadow(
                color: _p.withOpacity(dark ? 0 : 0.09), blurRadius: s(28), offset: Offset(0, s(8)))
          ]),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(s(40)),
        child: InkWell(
          borderRadius: BorderRadius.circular(s(40)),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const WeightPage())),
          child: Padding(
            padding: EdgeInsets.fromLTRB(s(36), s(26), s(30), s(26)),
            child: Row(children: [
              Expanded(
                flex: 4,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.monitor_weight_outlined, size: s(46), color: accent),
                    SizedBox(width: s(18)),
                    Text('Вес', style: t(32, w: FontWeight.w800)),
                  ]),
                  SizedBox(height: s(10)),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(cur == null ? '— кг' : '${fmt1(cur)} кг',
                          style: t(48, w: FontWeight.w800))),
                  if (delta != null)
                    Text('${delta >= 0 ? '+' : ''}${fmt1(delta)} кг с начала',
                        style: t(24, w: FontWeight.w600, c: accent)),
                  if (user?.targetWeightKg != null)
                    Text('Цель: ${fmt1(user!.targetWeightKg!)} кг',
                        style: t(24, c: cs.onSurfaceVariant)),
                ]),
              ),
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: s(160),
                  child: recent.length < 2
                      ? Center(
                          child: Text('Добавьте замеры', style: t(24, c: cs.onSurfaceVariant)))
                      : LineChart(LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: const LineTouchData(enabled: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < recent.length; i++)
                                  FlSpot(i.toDouble(), recent[i].weightKg)
                              ],
                              isCurved: true,
                              preventCurveOverShooting: true,
                              color: accent,
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData:
                                  BarAreaData(show: true, color: _pl.withOpacity(0.15)),
                            ),
                          ],
                        )),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
