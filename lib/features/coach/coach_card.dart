// Карточка «Чем добрать норму» на главном экране: показывается только для сегодняшнего дня,
// когда в дневнике уже есть записи и до нормы ещё что-то не хватает.
// Оформление по макету: оранжевая шапка, три плашки остатка, рекомендации и кнопка.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../ai/ai_advice.dart';
import '../dashboard/day_data.dart';
import 'goal_coach.dart';
import 'goal_service.dart';

const _mockWidth = 851.0;
const _purple = Color(0xFF6F2BD8);
const _orange = Color(0xFFFF8A1F);

/// Сколько продуктов можно показать, чтобы закрыть весь остаток (при большом остатке одного мало).
const _maxItems = 5;

class CoachCard extends ConsumerStatefulWidget {
  final DayData d;
  const CoachCard(this.d, {super.key});

  @override
  ConsumerState<CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends ConsumerState<CoachCard> {
  String _sig = '';
  Future<List<FoodSuggestion>>? _future;
  List<FoodSuggestion> _shown = const [];

  /// Уже показанные порции («продукт|граммы»): кнопка «Подобрать другие продукты» их исключает,
  /// тот же продукт в другой порции показать можно.
  final Set<String> _exclude = {};

  void _load(Nutrients r, GoalValues goal) {
    _future = suggestionsFor(ref.read(dbProvider), r, goal, skip: _exclude, max: _maxItems);
  }

  /// Следующая подборка; если других продуктов нет, круг начинается заново.
  void _next(Nutrients r, GoalValues goal) {
    for (final x in _shown) {
      _exclude.add(x.key);
    }
    final db = ref.read(dbProvider);
    _future = suggestionsFor(db, r, goal, skip: _exclude, max: _maxItems).then((v) {
      if (v.isNotEmpty) return v;
      _exclude.clear();
      return suggestionsFor(db, r, goal, max: _maxItems);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    if (d.key != dayKey(DateTime.now()) || d.food.isEmpty) {
      return const SizedBox.shrink();
    }
    final r = remainingTo(d.eaten, d.goal, d.calorieTarget);
    if (!hasGap(r)) return const SizedBox.shrink();
    final sig = '${r.calories.round()}|${r.proteins.round()}|${r.fats.round()}|'
        '${r.carbs.round()}';
    if (sig != _sig) {
      _sig = sig;
      _exclude.clear();
      _load(r, d.goal);
    }
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final accent = dark ? const Color(0xFF9145EC) : _purple;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);

    Widget chip(Color bg, Color fg, IconData icon, String value, String? label) {
      return Expanded(
        child: Container(
          height: s(80),
          padding: EdgeInsets.symmetric(horizontal: s(14)),
          decoration: BoxDecoration(
              color: bg.withOpacity(dark ? 0.22 : 1),
              borderRadius: BorderRadius.circular(s(26))),
          child: Row(children: [
            Icon(icon, size: s(40), color: fg),
            SizedBox(width: s(10)),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: t(28, w: FontWeight.w800))),
                    if (label != null) Text(label, style: t(19, c: muted)),
                  ]),
            ),
          ]),
        ),
      );
    }

    String g(double v) => fmt0(v);

    Widget suggestionTile(FoodSuggestion x) {
      final tot = x.total;
      return Container(
        margin: EdgeInsets.only(bottom: s(10)),
        padding: EdgeInsets.all(s(12)),
        decoration: BoxDecoration(
            color: dark ? Colors.white10 : const Color(0xFFF6F3FC),
            borderRadius: BorderRadius.circular(s(28))),
        child: Row(children: [
          Container(
            width: s(86),
            height: s(70),
            decoration: BoxDecoration(
                color: accent.withOpacity(dark ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(s(22))),
            child: Icon(x.food.liquid ? Icons.local_drink_outlined : Icons.restaurant,
                size: s(38), color: accent),
          ),
          SizedBox(width: s(16)),
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.food.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t(23, w: FontWeight.w800)),
              SizedBox(height: s(2)),
              Text(x.quantity, style: t(20, c: muted)),
            ]),
          ),
          SizedBox(width: s(8)),
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('+${g(tot.calories)} ккал', style: t(25, w: FontWeight.w800)),
              SizedBox(height: s(2)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                    'Б ${g(tot.proteins)} г   Ж ${g(tot.fats)} г   У ${g(tot.carbs)} г',
                    style: t(19, c: muted)),
              ),
            ]),
          ),
        ]),
      );
    }

    void showInfo(List<FoodSuggestion> sug) {
      final note = sug.isEmpty ? null : overflowNote(r, sug);
      final src = sug.any((x) => x.food.approximate)
          ? 'Подбор примерный: часть значений взята из общего справочника, а не из ваших продуктов.'
          : 'Подбор из ваших продуктов, порции примерные.';
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Как подбираются продукты'),
          content: Text('$src${note == null ? '' : ' $note'} '
              'Это расчёт порций под недостающие значения, а не рекомендация врача или диетолога.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Понятно'))
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: s(22)),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: s(2)),
        decoration: BoxDecoration(
            color: dark ? const Color(0xFF1C1C26) : Colors.white,
            borderRadius: BorderRadius.circular(s(44)),
            boxShadow: [
              BoxShadow(
                  color: _purple.withOpacity(dark ? 0 : 0.09),
                  blurRadius: s(28),
                  offset: Offset(0, s(8)))
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(s(44)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Шапка: персиковый фон, оранжевая дуга справа.
            SizedBox(
              height: s(96),
              child: CustomPaint(
                painter: _HeaderPainter(dark),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: s(28)),
                  child: Row(children: [
                    Container(
                      width: s(66),
                      height: s(66),
                      decoration:
                          const BoxDecoration(color: _orange, shape: BoxShape.circle),
                      child: Icon(Icons.lightbulb_outline,
                          size: s(38), color: Colors.white),
                    ),
                    SizedBox(width: s(22)),
                    Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Чем добрать норму', style: t(31, w: FontWeight.w800)),
                            SizedBox(height: s(2)),
                            Text('Осталось на сегодня', style: t(21, c: muted)),
                          ]),
                    ),
                    Icon(Icons.track_changes, size: s(50), color: Colors.white),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(s(20), s(14), s(20), s(22)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  chip(const Color(0xFFEFE9FB), accent, Icons.local_fire_department,
                      '${g(r.calories)} ккал', null),
                  SizedBox(width: s(12)),
                  chip(const Color(0xFFE6F1FD), const Color(0xFF2F7DE1),
                      Icons.fitness_center, '+${g(r.proteins)} г', 'Белка'),
                  SizedBox(width: s(12)),
                  chip(const Color(0xFFFFF0DD), _orange, Icons.grass,
                      '+${g(r.carbs)} г', 'Углеводов'),
                ]),
                FutureBuilder<List<FoodSuggestion>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.hasData) _shown = snap.data!;
                    final sug = snap.data ?? _shown;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(s(8), s(22), s(4), s(10)),
                        child: Row(children: [
                          Text('Рекомендации', style: t(27, w: FontWeight.w800)),
                          const Spacer(),
                          Flexible(
                            child: Text('Подбираем под вашу цель',
                                overflow: TextOverflow.ellipsis,
                                style: t(19, c: muted)),
                          ),
                          SizedBox(width: s(8)),
                          GestureDetector(
                            onTap: () => showInfo(sug),
                            child: Icon(Icons.info_outline, size: s(34), color: accent),
                          ),
                        ]),
                      ),
                      if (sug.isEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(s(8), 0, s(8), s(10)),
                          child: Text('Подходящих продуктов не нашлось.',
                              style: t(21, c: muted)),
                        )
                      else
                        for (final x in sug) suggestionTile(x),
                    ]);
                  },
                ),
                SizedBox(height: s(2)),
                Material(
                  color: accent.withOpacity(dark ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(s(32)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(s(32)),
                    onTap: () => setState(() => _next(r, d.goal)),
                    child: SizedBox(
                      height: s(66),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.tune, size: s(34), color: accent),
                        SizedBox(width: s(14)),
                        Text('Подобрать другие продукты',
                            style: t(23, w: FontWeight.w800, c: accent)),
                      ]),
                    ),
                  ),
                ),
                AiAdvice(key: ValueKey(sig), d: d, remaining: r, accent: accent),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Фон шапки: светлый персиковый слева и оранжевая дуга справа.
class _HeaderPainter extends CustomPainter {
  final bool dark;
  _HeaderPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bg = Paint()
      ..shader = LinearGradient(colors: [
        dark ? const Color(0xFF3A2A1C) : const Color(0xFFFFF2E4),
        dark ? const Color(0xFF1C1C26) : Colors.white,
      ]).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bg);
    final arc = Path()
      ..moveTo(w * 0.80, 0)
      ..quadraticBezierTo(w * 0.72, h * 0.55, w * 0.69, h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(
        arc,
        Paint()
          ..shader = const LinearGradient(
                  colors: [Color(0xFFFFB066), _orange],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight)
              .createShader(Rect.fromLTWH(w * 0.69, 0, w * 0.31, h)));
  }

  @override
  bool shouldRepaint(_HeaderPainter old) => old.dark != dark;
}
