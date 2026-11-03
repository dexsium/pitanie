import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/theme.dart';
import '../core/dates.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const AppCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF1C1C26) : Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: dark ? 0 : 1.5,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.icon, this.color, this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        if (icon != null) ...[
          Icon(icon, color: color ?? kPrimary, size: 24),
          const SizedBox(width: 8),
        ],
        Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        if (trailing != null) trailing!,
      ]);
}

class RingPainter extends CustomPainter {
  final double progress;
  final Color color, track;
  RingPainter(this.progress, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 16.0;
    final rect = Offset(w / 2, w / 2) & Size(size.width - w, size.height - w);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * p, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(RingPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}

class CalorieRing extends StatelessWidget {
  final double progress;
  final Widget center;
  final double size;
  const CalorieRing(
      {super.key, required this.progress, required this.center, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final over = progress > 1;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: RingPainter(v, over ? kRed : kGreen,
              Theme.of(context).colorScheme.onSurface.withOpacity(0.08)),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class MacroBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value, goal;
  final Color color;
  const MacroBar(
      {super.key,
      required this.label,
      required this.icon,
      required this.value,
      required this.goal,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = goal > 0 ? value / goal : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 4),
        Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      ]),
      const SizedBox(height: 6),
      Text.rich(TextSpan(children: [
        TextSpan(
            text: fmt0(value),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        TextSpan(
            text: ' / ${fmt0(goal)} г',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            backgroundColor: color.withOpacity(0.18)),
      ),
      const SizedBox(height: 2),
      Align(
          alignment: Alignment.centerRight,
          child: Text('${(pct * 100).round()}%',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant))),
    ]);
  }
}

/// Переключатель дня: предыдущий / следующий / календарь.
class DayBar extends ConsumerWidget {
  final VoidCallback? onCalendar;
  final Widget? trailing;
  const DayBar({super.key, this.onCalendar, this.trailing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDayProvider);
    void shift(int d) => ref.read(selectedDayProvider.notifier).state =
        DateTime(day.year, day.month, day.day + d);
    return Row(children: [
      IconButton.filledTonal(
          onPressed: onCalendar, icon: const Icon(Icons.calendar_month_rounded)),
      const Spacer(),
      IconButton(onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
      GestureDetector(
        onTap: () => ref.read(selectedDayProvider.notifier).state =
            dayStart(DateTime.now()),
        child: Column(children: [
          Text(dayTitle(day),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(dayDateLine(day),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
      IconButton(onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
      const Spacer(),
      trailing ?? const SizedBox(width: 48),
    ]);
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirmDialog(BuildContext context, String title, String text,
    {String ok = 'Да'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Изменение записей прошлых дней требует подтверждения.
Future<bool> guardPast(BuildContext context, String key) async {
  if (key.compareTo(dayKey(DateTime.now())) >= 0) return true;
  return confirmDialog(context, 'Прошедший день',
      'Вы изменяете данные за $key. Продолжить?');
}

Future<double?> promptNumber(BuildContext context, String title,
    {double? initial, String suffix = '', double min = 0, double? max, bool allowZero = false}) {
  final ctrl = TextEditingController(text: initial == null ? '' : fmtAuto(initial));
  final form = GlobalKey<FormState>();
  return showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: suffix),
          validator: numValidator(min: min, max: max, allowZero: allowZero),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, parseNum(ctrl.text));
            },
            child: const Text('OK')),
      ],
    ),
  );
}

FormFieldValidator<String> numValidator(
        {double min = 0, double? max, bool allowZero = true, bool required = true}) =>
    (v) {
      if (v == null || v.trim().isEmpty) return required ? 'Введите значение' : null;
      final n = parseNum(v);
      if (n == null) return 'Некорректное число';
      if (n < min || (!allowZero && n == 0)) return 'Значение слишком мало';
      if (max != null && n > max) return 'Максимум ${fmtAuto(max)}';
      return null;
    };

final numFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

class NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool required;
  final double min;
  final double? max;
  final bool allowZero;
  const NumField(
      {super.key,
      required this.controller,
      required this.label,
      this.suffix,
      this.required = true,
      this.min = 0,
      this.max,
      this.allowZero = true});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: numFormatters,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: numValidator(
            min: min, max: max, allowZero: allowZero, required: required),
      );
}

class EmptyHint extends StatelessWidget {
  final String text;
  const EmptyHint(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
      );
}
