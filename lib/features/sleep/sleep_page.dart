import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../dashboard/day_data.dart';
import 'sleep_data.dart';

/// Размеры экрана заданы в пикселях макета (ширина 852) и масштабируются по ширине устройства.
const _mockWidth = 852.0;

// Фиолетовая гамма раздела сна.
const kSleep = Color(0xFF7C2FDF);
const _sleepLight = Color(0xFF9B4DF0);
const _deep = Color(0xFF5B21B6);
const _rem = Color(0xFF9B4DF0);
const _lightSleep = Color(0xFFCDBBF6);
const _awake = Color(0xFFEFEAFB);

/// Норма для кольца: 8 часов (типичная рекомендация для взрослых), а не персональная цель.
const _sleepNormMin = 480;

String _hm(int min) {
  final h = min ~/ 60, m = min % 60;
  return h == 0 ? '$m м' : '$h ч $m м';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _times(int n) {
  final r = n % 100;
  if (r >= 11 && r <= 14) return '$n раз';
  return switch (n % 10) { 1 => '$n раз', 2 || 3 || 4 => '$n раза', _ => '$n раз' };
}

class _Bar {
  final DateTime date;
  final int? minutes;
  final String top, bottom;
  const _Bar(this.date, this.minutes, this.top, this.bottom);
}

class _SleepData {
  final SleepDay day;
  final List<_Bar> bars;
  final List<int> values; // ночи с данными в выбранном периоде
  const _SleepData(this.day, this.bars, this.values);
}

class SleepPage extends ConsumerStatefulWidget {
  final DateTime day;
  const SleepPage({super.key, required this.day});

  @override
  ConsumerState<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends ConsumerState<SleepPage> {
  late DateTime _day = dayStart(widget.day);
  int _range = 0; // 0 — 7 дней, 1 — 30 дней, 2 — год
  Future<_SleepData>? _future;
  String? _futureKey;

  static const _wd = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  static const _months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];

  String _dd(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  Future<_SleepData> _load() async {
    final db = ref.read(dbProvider);
    const six = Duration(hours: 6);
    final recs = singleSource(await db.sleepRecordsBetween(
        dayStart(_day).subtract(six), dayEnd(_day).subtract(six)));
    final sleepDay = analyzeSleepDay(recs, _day);

    final days = _range == 0 ? 7 : (_range == 1 ? 30 : 365);
    final first = dayStart(_day).subtract(Duration(days: days - 1));
    final srecs = singleSource(await db.sleepRecordsBetween(
        first.subtract(six), dayEnd(_day).subtract(six),
        stages: false));
    final byDay = nightMinutesByDay(srecs);
    final bars = <_Bar>[];
    if (_range == 2) {
      for (var i = 11; i >= 0; i--) {
        final m = DateTime(_day.year, _day.month - i);
        final vals = [
          for (final e in byDay.entries)
            if (e.key.year == m.year && e.key.month == m.month) e.value
        ];
        bars.add(_Bar(m, vals.isEmpty ? null : (vals.reduce((a, b) => a + b) / vals.length).round(),
            _months[m.month - 1], '${m.year}'));
      }
    } else {
      for (var i = 0; i < days; i++) {
        final d = first.add(Duration(days: i));
        bars.add(_Bar(d, byDay[dayStart(d)], _wd[d.weekday - 1], _dd(d)));
      }
    }
    final values = [
      for (final e in byDay.entries)
        if (!e.key.isBefore(first) && !e.key.isAfter(_day)) e.value
    ];
    return _SleepData(sleepDay, bars, values);
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
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final tint = kSleep.withOpacity(dark ? 0.22 : 0.10);

    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);

    final shadow = [
      BoxShadow(
          color: Colors.black.withOpacity(dark ? 0 : 0.07),
          blurRadius: s(26),
          offset: Offset(0, s(8)))
    ];

    // Перерисовка при поступлении новых записей.
    final marker = ref.watch(dayDataProvider(dayKey(_day))).valueOrNull?.activity.sleepMinutes;
    final key = '${dayKey(_day)}-$_range-$marker';
    if (_futureKey != key) {
      _futureKey = key;
      _future = _load();
    }

    Widget cardBox({required Widget child, EdgeInsets? padding, double radius = 30}) => Container(
          decoration: BoxDecoration(
              color: card, borderRadius: BorderRadius.circular(s(radius)), boxShadow: shadow),
          padding: padding ?? EdgeInsets.all(s(24)),
          child: child,
        );

    Widget roundBtn(IconData i, VoidCallback onTap, {Color? color}) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: s(82),
            height: s(82),
            decoration: BoxDecoration(color: card, shape: BoxShape.circle, boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(dark ? 0 : 0.10),
                  blurRadius: s(18),
                  offset: Offset(0, s(6)))
            ]),
            child: Icon(i, size: s(42), color: color ?? ink),
          ),
        );

    void info() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Как считается сон'),
              content: const Text(
                  'Данные берутся из минутных записей часов по Bluetooth.\n\n'
                  '• В постели — от первой до последней минуты сна.\n'
                  '• Эффективность — доля сна от времени в постели.\n'
                  '• Пробуждения — паузы в записи сна от 5 минут внутри ночи.\n'
                  '• Фазы (глубокий, быстрый, лёгкий) — приблизительная оценка по правилам '
                  'Gadgetbridge, а не точное измерение.\n'
                  '• Латентность (время засыпания) часы по Bluetooth не передают.\n'
                  '• Кольцо показывает долю от 8 часов — это типичная норма, а не ваша цель.\n'
                  '• Сон относится ко дню пробуждения.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))
              ],
            ));

    Widget iconTile(IconData i, {double size = 46}) => Icon(i, size: s(size), color: kSleep);

    Widget smallCard(IconData i, String label, String value, {Widget? sub}) => Expanded(
          child: cardBox(
            radius: 30,
            padding: EdgeInsets.symmetric(horizontal: s(38), vertical: s(14)),
            child: Row(children: [
              iconTile(i, size: 50),
              SizedBox(width: s(34)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: t(21)),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value, style: t(34, w: FontWeight.w800))),
                ]),
              ),
            ]),
          ),
        );

    return Scaffold(
      backgroundColor: dark ? null : const Color(0xFFF8F6FD),
      body: SafeArea(
        child: FutureBuilder<_SleepData>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            final night = data?.day.night;
            final nap = data?.day.nap;
            final bars = data?.bars ?? const <_Bar>[];
            final values = data?.values ?? const <int>[];

            String dyn(int? v) => v == null ? '—' : _hm(v);
            final avg = values.isEmpty ? null : (values.reduce((a, b) => a + b) / values.length).round();
            final best = values.isEmpty ? null : values.reduce(math.max);
            final worst = values.isEmpty ? null : values.reduce(math.min);

            final maxMin = bars.fold<int>(0, (m, b) => math.max(m, b.minutes ?? 0));
            final maxH = math.max(10, (maxMin / 60 / 2).ceil() * 2);
            final chartH = s(130);

            return ListView(padding: EdgeInsets.fromLTRB(s(22), s(14), s(22), s(28)), children: [
              // Шапка
              SizedBox(
                height: s(88),
                child: Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: _TopSwoosh(kSleep))),
                  Row(children: [
                    roundBtn(Icons.chevron_left, () => Navigator.maybePop(context)),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('Сон', style: t(40, w: FontWeight.w800)),
                        Text('${dayTitle(_day)}, ${dayDateLine(_day)}', style: t(22)),
                      ]),
                    ),
                    roundBtn(Icons.calendar_month_outlined, _pickDay, color: kSleep),
                  ]),
                ]),
              ),
              SizedBox(height: s(22)),

              // Кольцо и итоги
              cardBox(
                radius: 40,
                padding: EdgeInsets.fromLTRB(s(30), s(12), s(24), s(12)),
                child: SizedBox(
                  height: s(262),
                  child: Row(children: [
                    SizedBox(
                      width: s(262),
                      height: s(262),
                      child: Stack(alignment: Alignment.center, children: [
                        CustomPaint(
                            size: Size(s(262), s(262)),
                            painter: _RingPainter(
                                night == null ? 0 : night.sleepMin / _sleepNormMin, s(22), dark)),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Stack(children: [
                            Icon(Icons.bedtime, size: s(56), color: kSleep),
                            Positioned(
                                right: 0,
                                top: 0,
                                child: Text('z', style: t(22, w: FontWeight.w800, c: kSleep))),
                          ]),
                          SizedBox(
                            width: s(190),
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(night == null ? '—' : _hm(night.sleepMin),
                                    style: t(58, w: FontWeight.w800))),
                          ),
                          Text('Общий сон', style: t(24)),
                        ]),
                      ]),
                    ),
                    SizedBox(width: s(24)),
                    Container(width: 1, height: s(214), color: muted.withOpacity(0.25)),
                    SizedBox(width: s(32)),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Row(children: [
                          iconTile(Icons.bed_outlined, size: 56),
                          SizedBox(width: s(26)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('В постели', style: t(22)),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(night == null ? '—' : _hm(night.inBedMin),
                                      style: t(36, w: FontWeight.w800))),
                            ]),
                          ),
                          GestureDetector(
                              onTap: info,
                              child: Icon(Icons.info_outline, size: s(42), color: kSleep)),
                        ]),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: s(16)),
                          child: Divider(height: 1, color: muted.withOpacity(0.25)),
                        ),
                        Row(children: [
                          iconTile(Icons.nightlight_round, size: 56),
                          SizedBox(width: s(26)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Эффективность сна', style: t(22)),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                      night == null
                                          ? '—'
                                          : '${(night.efficiency * 100).round()} %',
                                      style: t(38, w: FontWeight.w800))),
                            ]),
                          ),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
              SizedBox(height: s(20)),

              // Фазы сна
              cardBox(
                radius: 40,
                padding: EdgeInsets.fromLTRB(s(24), s(22), s(24), s(24)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    SizedBox(width: s(4)),
                    Icon(Icons.layers_outlined, size: s(52), color: kSleep),
                    SizedBox(width: s(20)),
                    Text('Фазы сна', style: t(32, w: FontWeight.w800)),
                  ]),
                  SizedBox(height: s(34)),
                  if (night == null)
                    SizedBox(
                      height: s(120),
                      child: Center(
                          child: Text(
                              snap.connectionState == ConnectionState.waiting
                                  ? 'Загрузка…'
                                  : 'Нет данных о сне за этот день.\nДанные появляются после загрузки истории с часов.',
                              textAlign: TextAlign.center,
                              style: t(23, c: muted))),
                    )
                  else ...[
                    SizedBox(
                      height: s(84),
                      child: CustomPaint(
                          size: Size.infinite, painter: _TimelinePainter(night)),
                    ),
                    SizedBox(height: s(12)),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_hhmm(night.start), style: t(22)),
                      Text(_hhmm(night.end), style: t(22)),
                    ]),
                    SizedBox(height: s(22)),
                    ...[
                      (_deep, 'Глубокий сон', night.deepMin, night.deepMin / night.sleepMin),
                      (_rem, 'Быстрый (REM)', night.remMin, night.remMin / night.sleepMin),
                      (_lightSleep, 'Лёгкий сон', night.lightMin, night.lightMin / night.sleepMin),
                      (_awake, 'Бодрствование', night.awakeMin,
                          night.inBedMin == 0 ? 0.0 : night.awakeMin / night.inBedMin),
                    ].indexed.map((e) {
                      final (c, name, min, share) = e.$2;
                      return Column(children: [
                        if (e.$1 > 0) Divider(height: s(12), color: muted.withOpacity(0.18)),
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: s(3)),
                          child: Row(children: [
                            SizedBox(width: s(10)),
                            Container(
                                width: s(26),
                                height: s(26),
                                decoration: BoxDecoration(
                                    color: c, borderRadius: BorderRadius.circular(s(6)))),
                            SizedBox(width: s(26)),
                            Expanded(flex: 5, child: Text(name, style: t(24))),
                            Expanded(
                                flex: 4,
                                child: Text(_hm(min), style: t(24, w: FontWeight.w800))),
                            SizedBox(
                                width: s(90),
                                child: Text('${(share * 100).round()} %',
                                    textAlign: TextAlign.right, style: t(24))),
                            SizedBox(width: s(8)),
                          ]),
                        ),
                      ]);
                    }),
                  ],
                ]),
              ),
              SizedBox(height: s(18)),

              // Засыпание / пробуждение / латентность / пробуждения
              Row(children: [
                smallCard(Icons.bed_outlined, 'Засыпание', night == null ? '—' : _hhmm(night.start)),
                SizedBox(width: s(20)),
                smallCard(Icons.wb_twilight, 'Пробуждение', night == null ? '—' : _hhmm(night.end)),
              ]),
              SizedBox(height: s(14)),
              Row(children: [
                smallCard(Icons.hourglass_empty, 'Латентность', '—'),
                SizedBox(width: s(20)),
                smallCard(Icons.sync, 'Пробуждения', night == null ? '—' : _times(night.wakeups)),
              ]),
              SizedBox(height: s(14)),

              // Ночной и дневной сон
              cardBox(
                radius: 30,
                padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(10)),
                child: IntrinsicHeight(
                  child: Row(children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: s(28), vertical: s(8)),
                        child: Row(children: [
                          iconTile(Icons.nightlight_round, size: 56),
                          SizedBox(width: s(30)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Ночной сон', style: t(20)),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                      night == null
                                          ? '—'
                                          : '${_hhmm(night.start)} – ${_hhmm(night.end)}',
                                      style: t(32, w: FontWeight.w800))),
                              Text(night == null ? '' : '(${_hm(night.sleepMin)})',
                                  style: t(21, c: kSleep)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                    VerticalDivider(width: 1, color: muted.withOpacity(0.25)),
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.all(s(4)),
                        padding: EdgeInsets.symmetric(horizontal: s(24), vertical: s(8)),
                        decoration: BoxDecoration(
                            color: tint, borderRadius: BorderRadius.circular(s(26))),
                        child: Row(children: [
                          iconTile(Icons.wb_twilight, size: 54),
                          SizedBox(width: s(24)),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Дневной сон', style: t(20)),
                              FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                      nap == null ? '—' : '${_hhmm(nap.start)} – ${_hhmm(nap.end)}',
                                      style: t(32, w: FontWeight.w800))),
                              Text(nap == null ? 'нет' : '(${_hm(nap.sleepMin)})',
                                  style: t(21, c: kSleep)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              SizedBox(height: s(18)),

              // Динамика сна
              cardBox(
                radius: 40,
                padding: EdgeInsets.fromLTRB(s(20), s(18), s(20), s(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    SizedBox(width: s(6)),
                    Icon(Icons.bar_chart_rounded, size: s(54), color: kSleep),
                    SizedBox(width: s(18)),
                    Expanded(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Динамика сна', style: t(32, w: FontWeight.w800)))),
                    Container(
                      height: s(44),
                      decoration: BoxDecoration(
                          color: tint, borderRadius: BorderRadius.circular(s(22))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final (i, name) in ['7 дней', '30 дней', 'Год'].indexed)
                          GestureDetector(
                            onTap: () => setState(() => _range = i),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: s(26)),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: _range == i ? kSleep : Colors.transparent,
                                  borderRadius: BorderRadius.circular(s(22))),
                              child: Text(name,
                                  style: t(23,
                                      w: _range == i ? FontWeight.w700 : FontWeight.w400,
                                      c: _range == i ? Colors.white : ink)),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                  SizedBox(height: s(26)),
                  SizedBox(
                    height: chartH + s(104),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: s(76),
                        height: chartH + s(14),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var h = maxH; h >= 0; h -= maxH ~/ 5 == 0 ? 2 : (maxH / 5).ceil())
                                Text(h == 0 ? '0' : '$h ч',
                                    softWrap: false,
                                    overflow: TextOverflow.visible,
                                    style: t(21, c: muted).copyWith(height: 1.0)),
                            ]),
                      ),
                      Expanded(
                        child: Column(children: [
                          SizedBox(
                            height: chartH + s(14),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              for (var i = 0; i < bars.length; i++)
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: bars.length > 12 ? s(1.5) : s(10)),
                                    child: Container(
                                      height: bars[i].minutes == null
                                          ? s(3)
                                          : math.max(s(3), chartH * bars[i].minutes! / 60 / maxH),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(s(bars.length > 12 ? 4 : 14))),
                                        gradient: bars[i].minutes == null
                                            ? null
                                            : LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: i == bars.length - 1
                                                    ? const [Color(0xFF5B1DB5), Color(0xFF8A3FE0)]
                                                    : const [Color(0xFFA66CEB), Color(0xFFC9A7F5)]),
                                        color: bars[i].minutes == null
                                            ? muted.withOpacity(0.15)
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                          Container(height: 1, color: muted.withOpacity(0.25)),
                          SizedBox(height: s(10)),
                          Row(children: [
                            for (var i = 0; i < bars.length; i++)
                              Expanded(
                                child: bars.length > 12 && i % 5 != 0 && i != bars.length - 1
                                    ? const SizedBox()
                                    : Column(children: [
                                        if (bars.length <= 12)
                                          Text(bars[i].top,
                                              style: t(22,
                                                  w: i == bars.length - 1
                                                      ? FontWeight.w800
                                                      : FontWeight.w400)),
                                        Text(bars[i].bottom,
                                            maxLines: 1,
                                            overflow: TextOverflow.visible,
                                            softWrap: false,
                                            style: t(bars.length > 12 ? 17 : 20, c: muted)),
                                      ]),
                              ),
                          ]),
                        ]),
                      ),
                    ]),
                  ),
                  SizedBox(height: s(10)),
                  Row(children: [
                    _stat(s, t, card, muted, Icons.nightlight_round, kSleep, 'Средний сон', dyn(avg)),
                    SizedBox(width: s(14)),
                    _stat(s, t, card, muted, Icons.trending_up, kSleep, 'Лучший сон', dyn(best)),
                    SizedBox(width: s(14)),
                    _stat(s, t, card, muted, Icons.trending_down, kSleep, 'Худший сон', dyn(worst)),
                  ]),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _stat(double Function(double) s, TextStyle Function(double, {FontWeight w, Color? c}) t,
          Color card, Color muted, IconData icon, Color color, String label, String value) =>
      Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: s(16), vertical: s(14)),
          decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(s(26)),
              border: Border.all(color: muted.withOpacity(0.18))),
          child: Row(children: [
            Icon(icon, size: s(40), color: color),
            SizedBox(width: s(12)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: t(20))),
                FittedBox(
                    fit: BoxFit.scaleDown, child: Text(value, style: t(32, w: FontWeight.w800))),
              ]),
            ),
          ]),
        ),
      );
}

/// Кольцо: серая дорожка и фиолетовая дуга (доля сна от 8 часов).
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
          ..color = dark ? const Color(0xFF2E2E3A) : const Color(0xFFE9E7EE));
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
          ..shader = SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: 3 * math.pi / 2,
            colors: const [_sleepLight, kSleep, _deep],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.stroke != stroke || o.dark != dark;
}

/// Ночная диаграмма фаз: сегменты по времени, высота зависит от фазы.
class _TimelinePainter extends CustomPainter {
  final SleepSession session;
  _TimelinePainter(this.session);

  @override
  void paint(Canvas canvas, Size size) {
    final total = session.end.difference(session.start).inSeconds;
    if (total <= 0) return;
    for (final seg in session.segments) {
      final x0 = size.width * seg.start.difference(session.start).inSeconds / total;
      final x1 = size.width * seg.end.difference(session.start).inSeconds / total;
      final (color, h) = switch (seg.kind) {
        SleepKind.deep => (_deep, 0.62),
        SleepKind.rem => (_rem, 0.62),
        SleepKind.light => (_lightSleep, 1.0),
        SleepKind.awake => (_awake, 1.0),
      };
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(x0, size.height * (1 - h), math.max(x1, x0 + 1), size.height),
              const Radius.circular(2)),
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter o) => o.session != session;
}

/// Мягкая фиолетовая дуга в верхней части экрана.
class _TopSwoosh extends CustomPainter {
  final Color color;
  _TopSwoosh(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 1.05)
      ..quadraticBezierTo(
          size.width * 0.40, size.height * 0.55, size.width * 0.54, -size.height * 0.30);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.height * 0.16
          ..shader = LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: [color.withOpacity(0.0), color.withOpacity(0.55)],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_TopSwoosh o) => o.color != color;
}
