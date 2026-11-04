import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../body/body_page.dart';

/// Размеры экрана заданы в пикселях макета (ширина 851) и масштабируются по ширине устройства.
const _mockWidth = 851.0;
const _p = Color(0xFF6F2BD8); // основной фиолетовый
const _pl = Color(0xFF9145EC); // светлый фиолетовый

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

const _monthShort = [
  'янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.', 'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'
];

String _dm(DateTime d) => '${d.day} ${_monthShort[d.month - 1]}';

class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key});

  @override
  ConsumerState<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends ConsumerState<WeightPage> {
  int _range = 0; // 0 — неделя, 1 — месяц, 2 — всё

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final user = ref.watch(userProvider).valueOrNull;
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final accent = dark ? _pl : _p;
    final tint = _p.withOpacity(dark ? 0.25 : 0.10);
    final now = DateTime.now();
    final wk = weightChange(ws, const Duration(days: 7), now);
    final mo = weightChange(ws, const Duration(days: 30), now);
    final target = user?.targetWeightKg;

    String d(double? v) => v == null ? '—' : '${v >= 0 ? '+' : ''}${fmt1(v)} кг';
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);

    final shadow = [
      BoxShadow(
          color: _p.withOpacity(dark ? 0 : 0.09),
          blurRadius: s(26),
          offset: Offset(0, s(8)))
    ];

    Widget cardBox({required Widget child, EdgeInsets? padding, double radius = 30, Color? color, VoidCallback? onTap, VoidCallback? onLongPress}) =>
        Container(
          decoration: BoxDecoration(
              color: color ?? card,
              borderRadius: BorderRadius.circular(s(radius)),
              boxShadow: shadow),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(s(radius)),
            child: InkWell(
              borderRadius: BorderRadius.circular(s(radius)),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(padding: padding ?? EdgeInsets.all(s(24)), child: child),
            ),
          ),
        );

    Widget miniCard(IconData icon, String value, String label,
            {bool highlighted = false, VoidCallback? onTap}) =>
        Expanded(
          child: cardBox(
            color: highlighted ? (dark ? const Color(0xFF2A2240) : const Color(0xFFEFE8FC)) : null,
            onTap: onTap,
            padding: EdgeInsets.symmetric(vertical: s(22), horizontal: s(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: s(46), color: accent),
              SizedBox(height: s(14)),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: t(38, w: FontWeight.w800, c: highlighted ? accent : null))),
              Text(label, style: t(24, c: highlighted ? accent.withOpacity(0.7) : muted)),
            ]),
          ),
        );

    Widget periodCard(String value, String label) => Expanded(
          child: cardBox(
            padding: EdgeInsets.symmetric(vertical: s(24), horizontal: s(28)),
            child: Row(children: [
              Container(
                  width: s(74),
                  height: s(74),
                  decoration:
                      BoxDecoration(color: tint, borderRadius: BorderRadius.circular(s(24))),
                  child: Icon(Icons.calendar_today_outlined, size: s(40), color: accent)),
              SizedBox(width: s(26)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value, style: t(34, w: FontWeight.w800))),
                  Text(label, style: t(24, c: muted)),
                ]),
              ),
            ]),
          ),
        );

    // Данные для графика
    final from = switch (_range) {
      0 => now.subtract(const Duration(days: 7)),
      1 => now.subtract(const Duration(days: 30)),
      _ => null,
    };
    final pts = [for (final w in ws) if (from == null || w.measuredAt.isAfter(from)) w];

    Widget chart() {
      if (pts.length < 2) {
        return SizedBox(
            height: s(300),
            child: Center(
                child: Text(
                    ws.length < 2
                        ? 'Добавьте минимум два замера для графика'
                        : 'За этот период меньше двух замеров',
                    textAlign: TextAlign.center,
                    style: t(24, c: muted))));
      }
      final x0 = pts.first.measuredAt.millisecondsSinceEpoch / 86400000.0;
      final xs = [for (final w in pts) w.measuredAt.millisecondsSinceEpoch / 86400000.0 - x0];
      final lo = pts.map((w) => w.weightKg).reduce(math.min);
      final hi = pts.map((w) => w.weightKg).reduce(math.max);
      var step = 0.1;
      for (final c in const [0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0]) {
        step = c;
        if ((hi - lo) / c <= 5) break;
      }
      var minY = (lo / step).floor() * step;
      var maxY = (hi / step).ceil() * step;
      if (maxY - minY < step * 2) {
        maxY = minY + step * 5;
      }
      final spots = [for (var i = 0; i < pts.length; i++) FlSpot(xs[i], pts[i].weightKg)];
      final maxX = xs.last <= 0 ? 1.0 : xs.last;
      final many = pts.length > 14;
      return SizedBox(
        height: s(330),
        child: LineChart(LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.none(),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: _p.withOpacity(dark ? 0.25 : 0.14), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF263238),
              getTooltipItems: (list) => [
                for (final sp in list)
                  LineTooltipItem('${fmt1(sp.y)} кг',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: s(86),
                interval: step,
                getTitlesWidget: (v, meta) => Padding(
                  padding: EdgeInsets.only(right: s(14)),
                  child: Text(step < 1 ? fmt1(v) : fmt0(v),
                      textAlign: TextAlign.right, style: t(24)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: s(48),
                interval: maxX,
                getTitlesWidget: (v, meta) {
                  final first = v <= 0.0001;
                  final last = (v - maxX).abs() < 0.0001;
                  if (!first && !last) return const SizedBox();
                  return Padding(
                    padding: EdgeInsets.only(top: s(14)),
                    child: Text(_dm(first ? pts.first.measuredAt : pts.last.measuredAt),
                        style: t(22, c: muted)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.15,
              preventCurveOverShooting: true,
              color: accent,
              barWidth: math.max(2.5, s(5)),
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, bar) =>
                    !many || spot == bar.spots.first || spot == bar.spots.last,
                getDotPainter: (spot, p, bar, i) => FlDotCirclePainter(
                    radius: s(11), color: accent, strokeWidth: s(2.5), strokeColor: card),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_pl.withOpacity(0.38), _pl.withOpacity(0.04)]),
              ),
            ),
          ],
        )),
      );
    }

    void openBody(WeightEntry w) => Navigator.push(
        context, MaterialPageRoute(builder: (_) => BodyCompositionPage(entry: w)));

    Future<void> editTarget() async {
      final v = await promptNumber(context, 'Целевой вес',
          initial: target, suffix: 'кг', min: 20, max: 400);
      if (v != null) await db.saveUser(UsersCompanion(targetWeightKg: Value(v)));
    }

    return Scaffold(
      backgroundColor: dark ? null : const Color(0xFFF6F2FD),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: GestureDetector(
        onTap: () => _edit(context, db, null, ws.isEmpty ? null : ws.last.weightKg),
        child: Container(
          width: s(256),
          height: s(100),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(s(50)),
            gradient: const LinearGradient(colors: [_pl, _p]),
            boxShadow: [
              BoxShadow(color: _p.withOpacity(0.35), blurRadius: s(24), offset: Offset(0, s(10)))
            ],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add, size: s(52), color: Colors.white),
            SizedBox(width: s(22)),
            Text('Замер', style: t(34, w: FontWeight.w700, c: Colors.white)),
          ]),
        ),
      ),
      body: SafeArea(
        child: ListView(padding: EdgeInsets.fromLTRB(s(28), s(14), s(28), s(150)), children: [
          // Шапка
          SizedBox(
            height: s(84),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _TopSwoosh(_p))),
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: s(74),
                    height: s(74),
                    decoration: BoxDecoration(
                        color: card.withOpacity(0.85),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: _p.withOpacity(dark ? 0 : 0.10),
                              blurRadius: s(16),
                              offset: Offset(0, s(5)))
                        ]),
                    child: Icon(Icons.chevron_left, size: s(46), color: accent),
                  ),
                ),
                SizedBox(width: s(38)),
                Expanded(child: Text('Вес', style: t(40, w: FontWeight.w800))),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, size: s(46), color: accent),
                  onSelected: (v) async {
                    if (v == 'target') await editTarget();
                    if (v == 'clear') await db.saveUser(const UsersCompanion(targetWeightKg: Value(null)));
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'target',
                        child: Text(target == null ? 'Задать целевой вес' : 'Изменить целевой вес')),
                    if (target != null)
                      const PopupMenuItem(value: 'clear', child: Text('Убрать целевой вес')),
                  ],
                ),
              ]),
            ]),
          ),
          SizedBox(height: s(22)),

          // Текущий вес (по нажатию — состав тела)
          GestureDetector(
            onTap: ws.isEmpty ? null : () => openBody(ws.last),
            child: Container(
            height: s(222),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s(40)),
              gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_pl, _p]),
              boxShadow: [
                BoxShadow(color: _p.withOpacity(0.30), blurRadius: s(26), offset: Offset(0, s(10)))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(s(40)),
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _HeroWave())),
                Padding(
                  padding: EdgeInsets.fromLTRB(s(32), s(30), s(24), s(20)),
                  child: Row(children: [
                    Container(
                      width: s(150),
                      height: s(150),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(s(38))),
                      child: Icon(Icons.monitor_weight_outlined, size: s(98), color: Colors.white),
                    ),
                    SizedBox(width: s(34)),
                    Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Текущий вес', style: t(26, c: Colors.white.withOpacity(0.92))),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text.rich(TextSpan(children: [
                                TextSpan(
                                    text: ws.isEmpty ? '—' : fmt1(ws.last.weightKg),
                                    style: t(80, w: FontWeight.w800, c: Colors.white)),
                                if (ws.isNotEmpty)
                                  TextSpan(
                                      text: ' кг', style: t(58, w: FontWeight.w800, c: Colors.white)),
                              ])),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (wk != null && wk != 0)
                                  Icon(wk > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                      size: s(30), color: Colors.white),
                                SizedBox(width: s(wk != null && wk != 0 ? 8 : 0)),
                                Text(
                                    wk == null ? 'Нет данных за неделю' : '${d(wk)} за неделю',
                                    style: t(27, c: Colors.white)),
                              ]),
                            ),
                          ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          ),
          SizedBox(height: s(24)),

          // Начальный / цель / всего
          Row(children: [
            miniCard(Icons.monitor_weight_outlined,
                ws.isEmpty ? '—' : '${fmt1(ws.first.weightKg)} кг', 'Начальный'),
            SizedBox(width: s(15)),
            miniCard(Icons.track_changes, target == null ? '—' : '${fmt1(target)} кг', 'Цель',
                highlighted: true, onTap: editTarget),
            SizedBox(width: s(13)),
            miniCard(Icons.trending_up,
                ws.length < 2 ? '—' : d(ws.last.weightKg - ws.first.weightKg), 'Всего'),
          ]),
          SizedBox(height: s(24)),
          Row(children: [
            periodCard(d(wk), 'За неделю'),
            SizedBox(width: s(18)),
            periodCard(d(mo), 'За месяц'),
          ]),
          SizedBox(height: s(24)),

          // Динамика веса
          cardBox(
            radius: 40,
            padding: EdgeInsets.fromLTRB(s(28), s(26), s(28), s(22)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Динамика веса', style: t(34, w: FontWeight.w800)))),
                Container(
                  height: s(58),
                  decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(s(29)),
                      boxShadow: [
                        BoxShadow(
                            color: _p.withOpacity(dark ? 0 : 0.14),
                            blurRadius: s(14),
                            offset: Offset(0, s(4)))
                      ]),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final (i, name) in ['Неделя', 'Месяц', 'Всё'].indexed)
                      GestureDetector(
                        onTap: () => setState(() => _range = i),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: s(26)),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: _range == i ? _p : Colors.transparent,
                              borderRadius: BorderRadius.circular(s(29))),
                          child: Text(name,
                              style: t(25,
                                  w: _range == i ? FontWeight.w700 : FontWeight.w500,
                                  c: _range == i ? Colors.white : accent)),
                        ),
                      ),
                  ]),
                ),
              ]),
              SizedBox(height: s(26)),
              chart(),
            ]),
          ),
          SizedBox(height: s(34)),

          // Записи
          Row(children: [
            Expanded(child: Text('Записи', style: t(40, w: FontWeight.w800))),
            GestureDetector(
              onTap: () {
                ref.read(tabProvider.notifier).state = 3;
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
              child: Container(
                width: s(74),
                height: s(70),
                decoration: BoxDecoration(
                    color: card, borderRadius: BorderRadius.circular(s(24)), boxShadow: shadow),
                child: Icon(Icons.bar_chart_rounded, size: s(44), color: accent),
              ),
            ),
          ]),
          SizedBox(height: s(18)),
          if (ws.isEmpty)
            cardBox(
                child: Center(child: Text('Замеров пока нет', style: t(25, c: muted)))),
          for (final w in ws.reversed)
            Padding(
              padding: EdgeInsets.only(bottom: s(6)),
              child: cardBox(
                padding: EdgeInsets.symmetric(horizontal: s(28), vertical: s(16)),
                onTap: () => openBody(w),
                onLongPress: () => _edit(context, db, w, w.weightKg),
                child: Row(children: [
                  Container(
                      width: s(74),
                      height: s(74),
                      decoration:
                          BoxDecoration(color: tint, borderRadius: BorderRadius.circular(s(24))),
                      child: Icon(Icons.monitor_weight_outlined, size: s(42), color: accent)),
                  SizedBox(width: s(30)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${fmt1(w.weightKg)} кг', style: t(36, w: FontWeight.w800)),
                      Text('${fullDate(w.measuredAt)}, ${fmtTime(w.measuredAt)}',
                          style: t(25, c: muted)),
                    ]),
                  ),
                  IconButton(
                    iconSize: s(46),
                    color: ink,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDialog(
                          context, 'Удалить замер?', '${fmt1(w.weightKg)} кг',
                          ok: 'Удалить')) {
                        await db.deleteWeight(w.id);
                      }
                    },
                  ),
                ]),
              ),
            ),
        ]),
      ),
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

/// Светлая волна в правом нижнем углу карточки текущего веса.
class _HeroWave extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.42, h)
      ..cubicTo(w * 0.62, h * 0.95, w * 0.70, h * 0.45, w, h * 0.30)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.10));
  }

  @override
  bool shouldRepaint(_HeroWave o) => false;
}

/// Мягкая фиолетовая волна в верхней части экрана.
class _TopSwoosh extends CustomPainter {
  final Color color;
  _TopSwoosh(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.55, size.height * 1.2)
      ..quadraticBezierTo(
          size.width * 0.80, size.height * 0.6, size.width * 1.05, -size.height * 0.3);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.height * 0.9
          ..color = color.withOpacity(0.05));
  }

  @override
  bool shouldRepaint(_TopSwoosh o) => o.color != color;
}
