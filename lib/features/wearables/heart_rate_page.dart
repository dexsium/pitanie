import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../dashboard/day_data.dart' show kBleSource, sourceLabel, singleSource;
import 'heart_zones_page.dart';
import '../health_integration/devices_page.dart';

/// Размеры экрана заданы в пикселях макета (ширина 852) и масштабируются по ширине устройства.
const _mockWidth = 852.0;
const _p = Color(0xFF6F2BD8);
const _pl = Color(0xFF9145EC);

/// Суточный график пульса. Точки берутся из локальной базы приложения, поэтому
/// график строится и за прошлые дни, даже если часы столько не хранят.
class HeartRatePage extends ConsumerStatefulWidget {
  const HeartRatePage({super.key});
  @override
  ConsumerState<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends ConsumerState<HeartRatePage> {
  late DateTime _day = dayStart(DateTime.now());

  Future<List<ActivityRecord>> _load() async {
    final db = ref.read(dbProvider);
    final recs = await db.activityBetween(_day, dayEnd(_day));
    final hr = recs.where((r) => r.type == 'heartRate').toList();
    // Один источник (с наибольшим числом точек), без суммирования данных разных приложений.
    return singleSource(hr);
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _day,
        firstDate: DateTime(2020),
        lastDate: dayStart(DateTime.now()));
    if (d != null) setState(() => _day = dayStart(d));
  }

  @override
  Widget build(BuildContext context) {
    // Перерисовка при поступлении новых записей.
    ref.watch(dayDataProvider(dayKey(_day)));
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isToday = dayStart(DateTime.now()) == _day;
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
          color: _p.withOpacity(dark ? 0 : 0.08),
          blurRadius: s(26),
          offset: Offset(0, s(8)))
    ];

    Widget roundBtn(IconData i, VoidCallback? onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: s(68),
            height: s(68),
            decoration: BoxDecoration(
                color:
                    _p.withOpacity(onTap == null ? 0.05 : (dark ? 0.25 : 0.11)),
                shape: BoxShape.circle),
            child: Icon(i,
                size: s(40),
                color: onTap == null ? muted.withOpacity(0.5) : accent),
          ),
        );

    Widget stat(String label, double? v, IconData icon, Color c) => Expanded(
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: s(46),
                height: s(46),
                decoration: BoxDecoration(
                    color: c.withOpacity(dark ? 0.28 : 0.18),
                    shape: BoxShape.circle),
                child: Icon(icon, size: s(30), color: c),
              ),
              SizedBox(width: s(14)),
              Text(label, style: t(26, w: FontWeight.w500)),
            ]),
            SizedBox(height: s(6)),
            Text(v == null ? '—' : fmt0(v), style: t(54, w: FontWeight.w800)),
            Text('уд/мин', style: t(24)),
          ]),
        );

    return Scaffold(
      backgroundColor: dark ? null : const Color(0xFFF6F3FD),
      body: SafeArea(
        child: FutureBuilder<List<ActivityRecord>>(
          future: _load(),
          builder: (context, snap) {
            final recs = snap.data ?? const <ActivityRecord>[];
            // Только точки выбранных суток и не из будущего: иначе запись соседнего дня
            // (в графике группируется по времени суток) тянет линию к краю графика.
            final nextDay = _day.add(const Duration(days: 1));
            final now = DateTime.now();
            final pts = recs
                .map((r) => (r.startTime.toLocal(), r.value))
                .where((p) =>
                    p.$2 >= 30 &&
                    p.$2 <= 230 &&
                    !p.$1.isBefore(_day) &&
                    p.$1.isBefore(nextDay) &&
                    !p.$1.isAfter(now))
                .toList()
              ..sort((a, b) => a.$1.compareTo(b.$1));
            // Точки по минутам (среднее внутри минуты). Пятиминутное усреднение срезало
            // пики: максимум 147 в статистике, а линия графика доходила только до 120.
            final bins = <int, List<double>>{};
            for (final p in pts) {
              final m = p.$1.hour * 60 + p.$1.minute;
              bins.putIfAbsent(m, () => []).add(p.$2);
            }
            final spots = [
              for (final e
                  in (bins.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key))))
                FlSpot(e.key.toDouble(),
                    e.value.reduce((a, b) => a + b) / e.value.length)
            ];
            final values = pts.map((p) => p.$2).toList();
            final min =
                values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
            final max =
                values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
            final avg = values.isEmpty
                ? null
                : values.reduce((a, b) => a + b) / values.length;
            final src = recs.isEmpty
                ? null
                : sourceLabel(recs.first.source == kBleSource
                    ? kBleSource
                    : (recs.first.sourceName.isEmpty
                        ? recs.first.source
                        : recs.first.sourceName));

            return ListView(
                padding: EdgeInsets.fromLTRB(s(22), s(14), s(22), s(28)),
                children: [
                  // Заголовок
                  SizedBox(
                    height: s(78),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.maybePop(context),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: s(20)),
                          child:
                              Icon(Icons.chevron_left, size: s(56), color: ink),
                        ),
                      ),
                      SizedBox(width: s(22)),
                      Text('Пульс', style: t(42, w: FontWeight.w800)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HeartZonesPage())),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: s(20)),
                          child: Icon(Icons.tune, size: s(44), color: accent),
                        ),
                      ),
                    ]),
                  ),
                  SizedBox(height: s(12)),

                  // Фиолетовая плашка
                  Container(
                    height: s(154),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(s(42)),
                      gradient: const LinearGradient(
                          colors: [Color(0xFF8A4BE8), Color(0xFF6A2BD6)]),
                      boxShadow: [
                        BoxShadow(
                            color: _p.withOpacity(0.28),
                            blurRadius: s(24),
                            offset: Offset(0, s(10)))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(s(42)),
                      child: Stack(children: [
                        Positioned(
                          right: 0,
                          top: s(18),
                          bottom: s(18),
                          width: s(300),
                          child: CustomPaint(painter: _EcgPainter()),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: s(44)),
                          child: Row(children: [
                            Container(
                              width: s(94),
                              height: s(94),
                              decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(s(28))),
                              child: Icon(Icons.monitor_heart,
                                  size: s(64), color: _pl),
                            ),
                            SizedBox(width: s(40)),
                            Expanded(
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Пульс',
                                        style: t(40,
                                            w: FontWeight.w800,
                                            c: Colors.white)),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                          'Частота сердечных сокращений',
                                          style: t(24,
                                              c: Colors.white
                                                  .withOpacity(0.92))),
                                    ),
                                  ]),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  SizedBox(height: s(28)),

                  // Выбор дня
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: s(104)),
                    child: Row(children: [
                      roundBtn(
                          Icons.chevron_left,
                          () => setState(() =>
                              _day = _day.subtract(const Duration(days: 1)))),
                      SizedBox(width: s(12)),
                      Expanded(
                        child: GestureDetector(
                          onTap: _pickDay,
                          child: Container(
                            height: s(98),
                            decoration: BoxDecoration(
                                color: _p.withOpacity(dark ? 0.18 : 0.07),
                                borderRadius: BorderRadius.circular(s(49))),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(dayTitle(_day),
                                      style: t(34, w: FontWeight.w800)),
                                  Text(dayDateLine(_day),
                                      style: t(22, c: muted)),
                                ]),
                          ),
                        ),
                      ),
                      SizedBox(width: s(12)),
                      roundBtn(
                          Icons.chevron_right,
                          isToday
                              ? null
                              : () => setState(() =>
                                  _day = _day.add(const Duration(days: 1)))),
                    ]),
                  ),
                  SizedBox(height: s(26)),

                  // Мин / средний / макс
                  Container(
                    height: s(196),
                    decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(s(40)),
                        boxShadow: shadow),
                    padding:
                        EdgeInsets.symmetric(vertical: s(18), horizontal: s(6)),
                    child: Row(children: [
                      stat('Мин.', min, Icons.arrow_downward,
                          const Color(0xFF3CC24F)),
                      Container(
                          width: 1,
                          height: s(112),
                          color: muted.withOpacity(0.22)),
                      stat('Средний', avg, Icons.favorite, _pl),
                      Container(
                          width: 1,
                          height: s(112),
                          color: muted.withOpacity(0.22)),
                      stat('Макс.', max, Icons.arrow_upward,
                          const Color(0xFFF0658A)),
                    ]),
                  ),
                  SizedBox(height: s(24)),

                  // График
                  Container(
                    decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(s(44)),
                        boxShadow: shadow),
                    padding: EdgeInsets.fromLTRB(s(22), s(34), s(30), s(24)),
                    child: spots.length < 2
                        ? SizedBox(
                            height: s(380),
                            child: Center(
                                child: Text('Нет данных о пульсе за этот день',
                                    textAlign: TextAlign.center,
                                    style: t(26, c: muted))))
                        : SizedBox(
                            height: s(480),
                            child: LineChart(LineChartData(
                              minX: 0,
                              maxX: 1440,
                              minY: ((min ?? 50) - 10)
                                  .floorToDouble()
                                  .clamp(30, 200),
                              maxY: ((max ?? 120) + 10)
                                  .ceilToDouble()
                                  .clamp(60, 230),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (_) => FlLine(
                                    color: _p.withOpacity(dark ? 0.30 : 0.18),
                                    strokeWidth: 1.2,
                                    dashArray: [7, 7]),
                              ),
                              borderData: FlBorderData(
                                  show: true,
                                  border: Border(
                                      bottom: BorderSide(
                                          color: muted.withOpacity(0.30),
                                          width: 1))),
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (_) =>
                                      const Color(0xFF263238),
                                  getTooltipItems: (list) => [
                                    for (final sp in list)
                                      LineTooltipItem(
                                          '${fmt0(sp.y)} уд/мин, '
                                          '${(sp.x ~/ 60).toString().padLeft(2, '0')}:${(sp.x % 60).toInt().toString().padLeft(2, '0')}',
                                          const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(),
                                rightTitles: const AxisTitles(),
                                leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: s(76),
                                        getTitlesWidget: (v, _) => Padding(
                                              padding:
                                                  EdgeInsets.only(right: s(12)),
                                              child: Text(v.toInt().toString(),
                                                  textAlign: TextAlign.right,
                                                  style: t(23)
                                                      .copyWith(height: 1.0)),
                                            ))),
                                bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: s(48),
                                        interval: 360,
                                        getTitlesWidget: (v, _) => Padding(
                                              padding:
                                                  EdgeInsets.only(top: s(14)),
                                              child: Text(
                                                  '${(v / 60).round().toString().padLeft(2, '0')}:00',
                                                  style: t(23)),
                                            ))),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  curveSmoothness: 0.15,
                                  preventCurveOverShooting: true,
                                  color: kRed,
                                  barWidth: math.max(2.5, s(5)),
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                      show: true,
                                      color: kRed.withOpacity(0.10)),
                                ),
                              ],
                            )),
                          ),
                  ),
                  SizedBox(height: s(22)),

                  // Источник данных
                  Container(
                    decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(s(36)),
                        boxShadow: shadow),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(s(36)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(s(36)),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DevicesPage())),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: s(26), vertical: s(22)),
                          child: Row(children: [
                            Container(
                              width: s(72),
                              height: s(72),
                              decoration: BoxDecoration(
                                  color: _p.withOpacity(dark ? 0.25 : 0.11),
                                  borderRadius: BorderRadius.circular(s(22))),
                              child: Icon(Icons.watch_outlined,
                                  size: s(42), color: accent),
                            ),
                            SizedBox(width: s(26)),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                          src == null
                                              ? 'Источник пока не определён'
                                              : 'Источник: $src',
                                          style: t(28, w: FontWeight.w800)),
                                    ),
                                    Text(
                                        src == null
                                            ? 'Данные накапливаются при подключении часов'
                                            : 'Точек: ${fmt0(pts.length)} · История хранится в приложении',
                                        style: t(23, c: muted),
                                        maxLines: 2),
                                  ]),
                            ),
                            Icon(Icons.chevron_right,
                                size: s(40), color: muted),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]);
          },
        ),
      ),
    );
  }
}

/// Крупная бледная линия ЭКГ справа на фиолетовой плашке.
class _EcgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.62)
      ..lineTo(w * 0.34, h * 0.62)
      ..cubicTo(w * 0.42, h * 0.62, w * 0.46, h * 0.04, w * 0.55, h * 0.04)
      ..cubicTo(w * 0.64, h * 0.04, w * 0.66, h * 0.98, w * 0.76, h * 0.98)
      ..cubicTo(w * 0.86, h * 0.98, w * 0.88, h * 0.50, w, h * 0.50);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withOpacity(0.28));
  }

  @override
  bool shouldRepaint(_EcgPainter o) => false;
}
