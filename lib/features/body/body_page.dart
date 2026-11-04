import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../scale/scale_controller.dart';
import '../weight/weight_page.dart' show weightChange;
import 'body_metrics.dart';

/// Размеры экрана заданы в пикселях макета (ширина 852) и масштабируются по ширине устройства.
const _mockWidth = 852.0;
const _p = Color(0xFF6F2BD8);
const _pl = Color(0xFF9145EC);
const _good = Color(0xFF3CC24F);
const _warn = Color(0xFFF59E0B);

const _genMonths = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
];

String _years(int n) {
  final r = n % 100;
  if (r >= 11 && r <= 14) return '$n лет';
  return switch (n % 10) { 1 => '$n год', 2 || 3 || 4 => '$n года', _ => '$n лет' };
}

/// Метрики для записи веса: нужны импеданс и данные анкеты (рост, дата рождения, пол).
BodyMetrics? metricsFor(WeightEntry w, User? u) {
  if (w.impedance == null || u == null || u.heightCm == null || u.birthDate == null) return null;
  return BodyMetrics.compute(BodyInput(
      weight: w.weightKg,
      height: u.heightCm!,
      age: ageOn(u.birthDate!, w.measuredAt),
      female: u.sex == 'female',
      impedance: w.impedance!));
}

class BodyCompositionPage extends ConsumerWidget {
  final WeightEntry entry;
  const BodyCompositionPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(userProvider).valueOrNull;
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final scale = ref.watch(scaleProvider);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final accent = dark ? _pl : _p;
    final tint = _p.withOpacity(dark ? 0.25 : 0.10);

    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);

    final shadow = [
      BoxShadow(
          color: _p.withOpacity(dark ? 0 : 0.09),
          blurRadius: s(26),
          offset: Offset(0, s(8)))
    ];

    final m = metricsFor(entry, u);
    final bmi = m?.bmi ?? bmiOf(entry.weightKg, u?.heightCm);
    final wk = weightChange(
        [for (final w in ws) if (!w.measuredAt.isAfter(entry.measuredAt)) w],
        const Duration(days: 7),
        entry.measuredAt);
    final age = u?.birthDate == null ? null : ageOn(u!.birthDate!, entry.measuredAt);

    String why() {
      if (u == null || u.heightCm == null || u.birthDate == null) {
        return 'Заполните рост и дату рождения в анкете (Профиль → Анкета): без них состав тела не рассчитать.';
      }
      if (entry.impedance == null) {
        return 'У этого замера нет импеданса, поэтому состав тела не рассчитан. '
            'Встаньте на весы босиком, пока приложение открыто.';
      }
      return 'Значения вне диапазона формул (рост, вес, возраст или импеданс).';
    }

    Widget cardBox({required Widget child, EdgeInsets? padding, double radius = 34, VoidCallback? onTap}) =>
        Container(
          decoration:
              BoxDecoration(color: card, borderRadius: BorderRadius.circular(s(radius)), boxShadow: shadow),
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

    Widget tile(IconData i, {double size = 78, double icon = 44}) => Container(
          width: s(size),
          height: s(size),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(s(26))),
          child: Icon(i, size: s(icon), color: accent),
        );

    Widget chip(String text, Color c) => Container(
          padding: EdgeInsets.symmetric(horizontal: s(20), vertical: s(4)),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(s(24))),
          child: Text(text, style: t(26, w: FontWeight.w600, c: Colors.white)),
        );

    Color levelColor(Level l) => l == Level.normal ? _good : _warn;

    // Карточка показателя с полосой положения относительно нормы
    Widget metric(IconData icon, String label, double? v, String unit, Range? range,
        {int decimals = 1}) {
      final text = v == null ? '—' : v.toStringAsFixed(decimals).replaceAll('.', ',');
      final lvl = v == null || range == null ? null : range.of(v);
      final width = range == null ? 1.0 : (range.hi - range.lo);
      final fill = v == null || range == null
          ? 0.0
          : ((v - (range.lo - width * 0.5)) / (width * 2)).clamp(0.04, 1.0);
      String nr(double x) => x.toStringAsFixed(decimals).replaceAll('.', ',');
      return Expanded(
        child: cardBox(
          radius: 34,
          padding: EdgeInsets.fromLTRB(s(24), s(18), s(24), s(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              tile(icon, size: 78, icon: 42),
              SizedBox(width: s(16)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: t(23), maxLines: 2),
                  SizedBox(height: s(4)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: text, style: t(36, w: FontWeight.w800)),
                      TextSpan(text: ' $unit', style: t(24)),
                    ])),
                  ),
                ]),
              ),
            ]),
            SizedBox(height: s(10)),
            Container(
              height: s(13),
              decoration: BoxDecoration(
                  color: muted.withOpacity(0.18), borderRadius: BorderRadius.circular(s(7))),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fill,
                child: Container(
                    decoration: BoxDecoration(
                        color: lvl == null ? Colors.transparent : levelColor(lvl),
                        borderRadius: BorderRadius.circular(s(7)))),
              ),
            ),
            SizedBox(height: s(8)),
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                    range == null
                        ? ' '
                        : 'Норма (${nr(range.lo)} – ${nr(range.hi)} ${unit.trim()})',
                    style: t(23, c: muted)),
              ),
            ),
          ]),
        ),
      );
    }

    List<String> outOfNorm() {
      if (m == null) return const [];
      return [
        if (m.fatRange.of(m.fat) != Level.normal) 'жир',
        if (m.muscleRange.of(m.muscle) == Level.low) 'мышцы',
        if (m.waterRange.of(m.water) == Level.low) 'вода',
        if (m.boneRange.of(m.bone) == Level.low) 'кости',
        if (m.proteinRange.of(m.protein) == Level.low) 'белок',
        if (m.visceral > 9) 'висцеральный жир',
        if (m.bmi < 18.5 || m.bmi >= 25) 'ИМТ',
      ];
    }

    String scoreText() {
      final sc = m!.score;
      if (sc >= 90) {
        return 'Отличные показатели. Продолжайте поддерживать текущую активность и питание.';
      }
      if (sc >= 80) return 'Хорошие показатели. Небольшие улучшения ещё возможны.';
      final bad = outOfNorm();
      return 'Вне нормы: ${bad.isEmpty ? 'небольшие отклонения' : bad.join(', ')}. '
          'Обратите внимание на питание и активность.';
    }

    void explain() => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Как считается состав тела'),
              content: const SingleChildScrollView(
                child: Text(
                    'Весы передают только вес и импеданс (сопротивление тела). Остальное приложение '
                    'рассчитывает по формулам, восстановленным из Mi Fit (проект xiaomi_mi_scale, MIT), '
                    'с учётом роста, возраста и пола.\n\n'
                    'Это оценка, а не медицинское измерение: значения могут отличаться от Zepp и от '
                    'профессиональных приборов.\n\n'
                    '• Возраст тела и оценка состояния — тоже расчёт по этим формулам.\n'
                    '• Оценка — это 100 баллов минус штрафы за показатели вне нормы.\n'
                    '• Нормы зависят от пола, возраста, роста и веса.'),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))
              ],
            ));

    final d = entry.measuredAt;
    final bodyType = m == null ? '—' : BodyMetrics.bodyTypeNames[m.bodyType];
    final bmiColor = bmi == null
        ? muted
        : (bmi < 18.5 || bmi >= 25 ? _warn : _good);

    return Scaffold(
      backgroundColor: dark ? null : const Color(0xFFF6F2FD),
      body: SafeArea(
        child: ListView(padding: EdgeInsets.fromLTRB(s(26), s(12), s(26), s(30)), children: [
          // Шапка
          SizedBox(
            height: s(100),
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
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Состав тела', style: t(36, w: FontWeight.w800))),
                        FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('Mi Body Composition Scale 2', style: t(24, c: muted))),
                      ]),
                ),
                GestureDetector(
                  onTap: explain,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: s(22), vertical: s(14)),
                    decoration: BoxDecoration(
                        color: card.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(s(34)),
                        boxShadow: [
                          BoxShadow(
                              color: _p.withOpacity(dark ? 0 : 0.10),
                              blurRadius: s(14),
                              offset: Offset(0, s(4)))
                        ]),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.bluetooth, size: s(34), color: accent),
                      SizedBox(width: s(10)),
                      Icon(scale.enabled ? Icons.check : Icons.close,
                          size: s(30), color: scale.enabled ? _good : muted),
                      SizedBox(width: s(10)),
                      Text(scale.enabled ? 'Включён' : 'Выключен', style: t(23, c: accent)),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
          SizedBox(height: s(18)),

          // Измерение
          Container(
            height: s(301),
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
                Positioned(
                    right: s(120),
                    bottom: s(10),
                    child: Icon(Icons.accessibility_new,
                        size: s(250), color: Colors.white.withOpacity(0.32))),
                Positioned(
                    right: s(24),
                    bottom: s(26),
                    child: Icon(Icons.monitor_weight_outlined,
                        size: s(140), color: Colors.white.withOpacity(0.85))),
                Padding(
                  padding: EdgeInsets.fromLTRB(s(42), s(28), s(24), s(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Измерение от ${d.day} ${_genMonths[d.month - 1]}, ${fmtTime(d)}',
                          style: t(27, c: Colors.white)),
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: fmt1(entry.weightKg),
                            style: t(112, w: FontWeight.w800, c: Colors.white)
                                .copyWith(height: 1.0)),
                        TextSpan(
                            text: ' кг',
                            style: t(70, w: FontWeight.w800, c: Colors.white).copyWith(height: 1.0)),
                      ])),
                    ),
                    SizedBox(height: s(10)),
                    Container(
                      padding: EdgeInsets.fromLTRB(s(10), s(8), s(26), s(8)),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(s(36))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: s(54),
                          height: s(54),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                          child: Icon(
                              wk == null || wk >= 0
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: s(40),
                              color: Colors.white),
                        ),
                        SizedBox(width: s(16)),
                        Text(
                            wk == null
                                ? 'Нет данных за неделю'
                                : '${wk >= 0 ? '+' : '−'}${fmt1(wk.abs())} кг за неделю',
                            style: t(30, w: FontWeight.w500, c: Colors.white)),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          SizedBox(height: s(20)),

          // ИМТ и телосложение
          cardBox(
            radius: 36,
            padding: EdgeInsets.symmetric(horizontal: s(28), vertical: s(20)),
            child: IntrinsicHeight(
              child: Row(children: [
                tile(Icons.calendar_today_outlined, size: 86, icon: 46),
                SizedBox(width: s(26)),
                Expanded(
                  flex: 5,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ИМТ', style: t(27)),
                    Row(children: [
                      Flexible(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(bmi == null ? '—' : fmt1(bmi),
                                style: t(56, w: FontWeight.w800))),
                      ),
                      SizedBox(width: s(14)),
                      if (bmi != null) chip(bmiCategory(bmi), bmiColor),
                    ]),
                  ]),
                ),
                VerticalDivider(width: s(40), color: muted.withOpacity(0.25)),
                tile(Icons.fitness_center, size: 86, icon: 46),
                SizedBox(width: s(22)),
                Expanded(
                  flex: 6,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Телосложение', style: t(27)),
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(bodyType, style: t(44, w: FontWeight.w800))),
                  ]),
                ),
              ]),
            ),
          ),
          SizedBox(height: s(34)),

          Padding(
            padding: EdgeInsets.only(left: s(8), bottom: s(18)),
            child: Text('Показатели состава тела', style: t(38, w: FontWeight.w800)),
          ),
          if (m == null)
            Padding(
              padding: EdgeInsets.only(bottom: s(16)),
              child: cardBox(
                  child: Row(children: [
                Icon(Icons.info_outline, size: s(44), color: accent),
                SizedBox(width: s(20)),
                Expanded(child: Text(why(), style: t(24))),
              ])),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            metric(Icons.water_drop_outlined, 'Жир', m?.fat, '%', m?.fatRange),
            SizedBox(width: s(16)),
            metric(Icons.fitness_center, 'Мышечная масса', m?.muscle, 'кг', m?.muscleRange),
          ]),
          SizedBox(height: s(14)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            metric(Icons.water_drop_outlined, 'Вода', m?.water, '%', m?.waterRange),
            SizedBox(width: s(16)),
            metric(Icons.accessibility_new, 'Костная масса', m?.bone, 'кг', m?.boneRange),
          ]),
          SizedBox(height: s(14)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            metric(Icons.hub_outlined, 'Белок', m?.protein, '%', m?.proteinRange),
            SizedBox(width: s(16)),
            Expanded(
              child: cardBox(
                radius: 34,
                padding: EdgeInsets.fromLTRB(s(24), s(18), s(24), s(16)),
                child: Row(children: [
                  tile(Icons.local_fire_department_outlined, size: 78, icon: 42),
                  SizedBox(width: s(18)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Основной обмен', style: t(23)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: m == null ? '—' : fmt0(m.bmr),
                              style: t(40, w: FontWeight.w800)),
                          TextSpan(text: ' ккал/сут', style: t(25)),
                        ])),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
          SizedBox(height: s(14)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            metric(Icons.air, 'Висцеральный жир', m?.visceral, 'ур.', m?.visceralRange,
                decimals: 0),
            SizedBox(width: s(16)),
            Expanded(
              child: cardBox(
                radius: 34,
                padding: EdgeInsets.fromLTRB(s(24), s(18), s(24), s(16)),
                child: Row(children: [
                  tile(Icons.hourglass_empty, size: 78, icon: 42),
                  SizedBox(width: s(18)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Биологический возраст', style: t(23), maxLines: 2),
                      FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(m == null ? '—' : _years(m.bodyAge.round()),
                              style: t(36, w: FontWeight.w800))),
                      if (m != null && age != null) ...[
                        SizedBox(height: s(6)),
                        chip(m.bodyAge.round() <= age ? 'Соответствует' : 'Старше возраста',
                            m.bodyAge.round() <= age ? _good : _warn),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
          SizedBox(height: s(26)),

          // Оценка состояния тела
          cardBox(
            radius: 38,
            onTap: m == null ? explain : explain,
            padding: EdgeInsets.fromLTRB(s(30), s(24), s(26), s(24)),
            child: Row(children: [
              SizedBox(
                width: s(152),
                height: s(152),
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                      size: Size(s(152), s(152)),
                      painter: _ScoreRing((m?.score ?? 0) / 100, s(16), dark)),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(m == null ? '—' : '${m.score.round()}', style: t(60, w: FontWeight.w800)),
                    Text('из 100', style: t(22)),
                  ]),
                ]),
              ),
              SizedBox(width: s(26)),
              Container(width: 1, height: s(120), color: muted.withOpacity(0.25)),
              SizedBox(width: s(30)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Оценка состояния тела', style: t(32, w: FontWeight.w800)),
                  SizedBox(height: s(6)),
                  Text(m == null ? 'Нет данных для оценки.' : scoreText(),
                      style: t(24, c: muted)),
                ]),
              ),
              Icon(Icons.chevron_right, size: s(44), color: ink),
            ]),
          ),
          SizedBox(height: s(18)),

          // Динамика изменений
          cardBox(
            radius: 34,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const BodyDynamicsPage())),
            padding: EdgeInsets.symmetric(horizontal: s(30), vertical: s(18)),
            child: Row(children: [
              tile(Icons.bar_chart_rounded, size: 76, icon: 44),
              SizedBox(width: s(30)),
              Expanded(child: Text('Динамика изменений', style: t(34, w: FontWeight.w700))),
              Icon(Icons.chevron_right, size: s(44), color: ink),
            ]),
          ),
          SizedBox(height: s(26)),

          // Сохранить результат
          GestureDetector(
            onTap: () {
              toast(context, 'Измерение уже сохранено в записях веса');
              Navigator.maybePop(context);
            },
            child: Container(
              height: s(82),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s(41)),
                gradient: const LinearGradient(colors: [_pl, _p]),
                boxShadow: [
                  BoxShadow(color: _p.withOpacity(0.35), blurRadius: s(22), offset: Offset(0, s(8)))
                ],
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check, size: s(46), color: Colors.white),
                SizedBox(width: s(24)),
                Text('Сохранить результат', style: t(34, w: FontWeight.w500, c: Colors.white)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Динамика показателей по замерам с импедансом.
class BodyDynamicsPage extends ConsumerStatefulWidget {
  const BodyDynamicsPage({super.key});

  @override
  ConsumerState<BodyDynamicsPage> createState() => _BodyDynamicsPageState();
}

class _BodyDynamicsPageState extends ConsumerState<BodyDynamicsPage> {
  int _sel = 0;

  static const _names = ['Вес', 'Жир', 'Мышцы', 'Вода', 'Висцеральный жир', 'Возраст тела', 'Оценка'];
  static const _units = ['кг', '%', 'кг', '%', 'ур.', 'лет', ''];

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final u = ref.watch(userProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    final rows = <(DateTime, double)>[];
    for (final w in ws) {
      final m = metricsFor(w, u);
      if (_sel == 0) {
        if (w.impedance != null) rows.add((w.measuredAt, w.weightKg));
        continue;
      }
      if (m == null) continue;
      final v = switch (_sel) {
        1 => m.fat,
        2 => m.muscle,
        3 => m.water,
        4 => m.visceral,
        5 => m.bodyAge,
        _ => m.score,
      };
      rows.add((w.measuredAt, v));
    }
    String f(double v) => _sel == 4 || _sel == 5 || _sel == 6 ? fmt0(v) : fmt1(v);

    Widget chart() {
      if (rows.length < 2) {
        return const SizedBox(
            height: 220,
            child: EmptyHint('Нужно минимум два замера на весах с импедансом'));
      }
      final x0 = rows.first.$1.millisecondsSinceEpoch / 86400000.0;
      final spots = [for (final r in rows) FlSpot(r.$1.millisecondsSinceEpoch / 86400000.0 - x0, r.$2)];
      final lo = rows.map((r) => r.$2).reduce(math.min);
      final hi = rows.map((r) => r.$2).reduce(math.max);
      final pad = math.max(0.5, (hi - lo) * 0.2);
      return SizedBox(
        height: 240,
        child: LineChart(LineChartData(
          minY: lo - pad,
          maxY: hi + pad,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (v, m) => Text(f(v), style: const TextStyle(fontSize: 11))),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF263238),
              getTooltipItems: (list) => [
                for (final sp in list)
                  LineTooltipItem('${f(sp.y)} ${_units[_sel]}',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.15,
              preventCurveOverShooting: true,
              color: _p,
              barWidth: 3,
              dotData: FlDotData(show: rows.length <= 20),
              belowBarData: BarAreaData(show: true, color: _pl.withOpacity(0.15)),
            ),
          ],
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Динамика изменений')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (var i = 0; i < _names.length; i++)
            ChoiceChip(
              label: Text(_names[i]),
              selected: _sel == i,
              selectedColor: _p,
              labelStyle: TextStyle(color: _sel == i ? Colors.white : null),
              onSelected: (_) => setState(() => _sel = i),
            ),
        ]),
        const SizedBox(height: 14),
        AppCard(child: chart()),
        const SizedBox(height: 10),
        if (rows.isNotEmpty)
          Text(
              'Замеров: ${rows.length}. Последнее: ${f(rows.last.$2)} ${_units[_sel]}. '
              'Минимум ${f(rows.map((r) => r.$2).reduce(math.min))}, '
              'максимум ${f(rows.map((r) => r.$2).reduce(math.max))}.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text('Состав тела рассчитывается по формулам (оценка), а не измеряется.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _ScoreRing extends CustomPainter {
  final double progress, stroke;
  final bool dark;
  _ScoreRing(this.progress, this.stroke, this.dark);

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
          ..shader = const SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: 3 * math.pi / 2,
            colors: [_pl, _p, Color(0xFF4B1D8F)],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_ScoreRing o) => o.progress != progress || o.stroke != stroke || o.dark != dark;
}

class _HeroWave extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.30, h)
      ..cubicTo(w * 0.52, h * 0.95, w * 0.62, h * 0.45, w, h * 0.30)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.10));
  }

  @override
  bool shouldRepaint(_HeroWave o) => false;
}

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
