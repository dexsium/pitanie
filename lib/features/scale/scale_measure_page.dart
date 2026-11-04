import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../shared/widgets.dart';
import '../body/body_page.dart';
import 'scale_controller.dart';

/// Размеры экрана заданы в пикселях макета (ширина 851) и масштабируются по ширине устройства.
const _mockWidth = 851.0;
const _p = Color(0xFF6F2BD8);
const _pl = Color(0xFF9145EC);

/// Окно «Измерение веса»: открывается само, когда приложение открыто и человек встаёт на весы.
/// По завершении сохраняет замер (его делает контроллер) и показывает состав тела.
class ScaleMeasurePage extends ConsumerStatefulWidget {
  const ScaleMeasurePage({super.key});

  @override
  ConsumerState<ScaleMeasurePage> createState() => _ScaleMeasurePageState();
}

class _ScaleMeasurePageState extends ConsumerState<ScaleMeasurePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Взвешивание могло завершиться ещё до построения окна.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFinish(ref.read(scaleProvider)));
  }

  /// Измерение завершено и сохранено: показываем результат (состав тела).
  void _maybeFinish(ScaleController c) {
    if (_leaving || c.phase != ScalePhase.done || c.savedEntry == null) return;
    _leaving = true;
    final entry = c.savedEntry!;
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => BodyCompositionPage(entry: entry)));
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _close({String? message}) {
    if (_leaving || !mounted) return;
    _leaving = true;
    if (message != null) toast(context, message);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ScaleController>(scaleProvider, (prev, next) {
      if (_leaving) return;
      if (next.phase == ScalePhase.done && next.savedEntry != null) {
        _maybeFinish(next);
      } else if (next.phase == ScalePhase.idle) {
        _leaving = false;
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted && ref.read(scaleProvider).phase == ScalePhase.idle) {
            _close(message: 'Измерение прервано');
          }
        });
      }
    });
    final c = ref.watch(scaleProvider);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final accent = dark ? _pl : _p;
    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: 1.2);

    final phase = c.phase;
    final step2Done = phase == ScalePhase.saving || phase == ScalePhase.done;
    final step3Done = phase == ScalePhase.done;
    final subtitle = switch (phase) {
      ScalePhase.idle => 'Встаньте на умные весы',
      ScalePhase.measuring => c.liveKg == null ? 'Встаньте на умные весы' : 'Не двигайтесь',
      ScalePhase.saving => 'Сохраняем результат',
      ScalePhase.done => 'Готово',
    };

    Widget step(int n, String title, String sub, {required bool done, required bool active}) {
      Widget mark;
      if (done) {
        mark = Container(
          width: s(62),
          height: s(62),
          decoration: const BoxDecoration(
              shape: BoxShape.circle, gradient: LinearGradient(colors: [_pl, _p])),
          child: Icon(Icons.check, size: s(38), color: Colors.white),
        );
      } else if (active) {
        mark = SizedBox(
          width: s(62),
          height: s(62),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CustomPaint(painter: _SpinnerPainter(_anim.value, s(7))),
          ),
        );
      } else {
        mark = Container(
          width: s(62),
          height: s(62),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: muted.withOpacity(0.35), width: s(5))),
        );
      }
      return Expanded(
        child: Column(children: [
          mark,
          SizedBox(height: s(16)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(title, style: t(28, w: FontWeight.w800))),
          FittedBox(fit: BoxFit.scaleDown, child: Text(sub, style: t(23, c: muted))),
        ]),
      );
    }

    final kgText = c.liveKg == null ? '—' : fmt1(c.liveKg!);

    return Scaffold(
      backgroundColor: dark ? null : const Color(0xFFF3EDFD),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _BackgroundPainter(dark))),
        SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: s(30)),
            child: Column(children: [
              SizedBox(height: s(14)),
              SizedBox(
                height: s(110),
                child: Stack(alignment: Alignment.topCenter, children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: GestureDetector(
                      onTap: () {
                        ref.read(scaleProvider).dismissed = true;
                        _close();
                      },
                      child: Container(
                        width: s(74),
                        height: s(74),
                        decoration: BoxDecoration(
                            color: (dark ? Colors.white10 : Colors.white).withOpacity(0.8),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: _p.withOpacity(dark ? 0 : 0.12),
                                  blurRadius: s(16),
                                  offset: Offset(0, s(5)))
                            ]),
                        child: Icon(Icons.close, size: s(40), color: accent),
                      ),
                    ),
                  ),
                  Column(children: [
                    Container(
                      width: s(56),
                      height: s(56),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(s(16)),
                          gradient: const LinearGradient(colors: [_pl, _p])),
                      child: Icon(Icons.monitor_weight_outlined, size: s(36), color: Colors.white),
                    ),
                    SizedBox(height: s(8)),
                    Text('Mi Body Composition Scale 2', style: t(25, w: FontWeight.w500, c: accent)),
                  ]),
                ]),
              ),
              SizedBox(height: s(26)),
              Text('Измерение веса', style: t(62, w: FontWeight.w800)),
              SizedBox(height: s(8)),
              Text(subtitle, style: t(33, c: ink.withOpacity(0.8))),
              SizedBox(height: s(36)),

              // Круг со весами
              SizedBox(
                width: s(740),
                height: s(740),
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => CustomPaint(
                    painter: _ScalePainter(_anim.value, phase != ScalePhase.measuring ? 1.0 : null,
                        dark),
                    child: Align(
                      alignment: const Alignment(0, -0.38),
                      child: Container(
                        width: s(76),
                        height: s(76),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(s(22)),
                          gradient: const LinearGradient(
                              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_pl, _p]),
                          boxShadow: [
                            BoxShadow(
                                color: _p.withOpacity(0.45),
                                blurRadius: s(26),
                                offset: Offset(0, s(10)))
                          ],
                        ),
                        child: Icon(Icons.bluetooth, size: s(46), color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: s(18)),

              // Этапы
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                step(1, 'Подключение', 'Весы найдены', done: true, active: false),
                step(2, 'Измерение', step2Done ? 'Готово' : 'Не двигайтесь…',
                    done: step2Done, active: !step2Done),
                step(3, 'Сохранение', step3Done ? 'Сохранено' : (phase == ScalePhase.saving ? 'Сохранение…' : 'В дневник'),
                    done: step3Done, active: phase == ScalePhase.saving),
              ]),
              SizedBox(height: s(30)),

              // Текущий вес
              Container(
                width: double.infinity,
                height: s(346),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s(50)),
                  color: (dark ? Colors.white10 : Colors.white).withOpacity(0.7),
                  border: Border.all(color: Colors.white.withOpacity(dark ? 0.1 : 0.9), width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: _p.withOpacity(dark ? 0 : 0.10),
                        blurRadius: s(30),
                        offset: Offset(0, s(10)))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(s(50)),
                  child: Stack(alignment: Alignment.topCenter, children: [
                    Positioned.fill(child: CustomPaint(painter: _WavePainter())),
                    Padding(
                      padding: EdgeInsets.only(top: s(24)),
                      child: Column(children: [
                        Text('Текущий вес', style: t(34, w: FontWeight.w500, c: muted)),
                        ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [_pl, Color(0xFF4B1D8F)])
                              .createShader(r),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                      text: kgText,
                                      style: t(150, w: FontWeight.w800, c: Colors.white)),
                                  if (c.liveKg != null)
                                    TextSpan(
                                        text: ' кг',
                                        style: t(96, w: FontWeight.w800, c: Colors.white)),
                                ]),
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              SizedBox(height: s(34)),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: s(40), vertical: s(24)),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s(46)),
                  color: (dark ? Colors.white10 : Colors.white).withOpacity(0.7),
                  boxShadow: [
                    BoxShadow(
                        color: _p.withOpacity(dark ? 0 : 0.08),
                        blurRadius: s(20),
                        offset: Offset(0, s(6)))
                  ],
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: s(52), color: accent),
                  SizedBox(width: s(26)),
                  Expanded(
                      child: Text('Не сходите с весов до завершения измерения', style: t(30))),
                ]),
              ),
              SizedBox(height: s(40)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  final double t;
  final double stroke;
  _SpinnerPainter(this.t, this.stroke);

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
          ..color = _p.withOpacity(0.18));
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2 + t * 2 * math.pi,
        math.pi * 1.1,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = _p);
  }

  @override
  bool shouldRepaint(_SpinnerPainter o) => o.t != t;
}

/// Мягкий фиолетовый фон с волнами сверху слева и внизу.
class _BackgroundPainter extends CustomPainter {
  final bool dark;
  _BackgroundPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? [const Color(0xFF17131F), const Color(0xFF101017)]
                  : [const Color(0xFFEFE6FD), const Color(0xFFF8F4FF)]).createShader(Offset.zero & size));
    final top = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.34, 0)
      ..quadraticBezierTo(w * 0.22, h * 0.07, 0, h * 0.13)
      ..close();
    canvas.drawPath(top, Paint()..color = _p.withOpacity(dark ? 0.12 : 0.07));
    final bottom = Path()
      ..moveTo(0, h * 0.94)
      ..quadraticBezierTo(w * 0.35, h * 0.90, w * 0.65, h * 0.96)
      ..quadraticBezierTo(w * 0.85, h, w, h * 0.93)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(bottom, Paint()..color = _pl.withOpacity(dark ? 0.18 : 0.20));
  }

  @override
  bool shouldRepaint(_BackgroundPainter o) => o.dark != dark;
}

/// Стеклянный круг с дугой измерения, волнами и рисунком весов.
class _ScalePainter extends CustomPainter {
  final double t;
  final double? fixedProgress; // null — идёт измерение (дуга вращается), иначе заполнена
  final bool dark;
  _ScalePainter(this.t, this.fixedProgress, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 8;
    // стеклянная подложка
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withOpacity(dark ? 0.06 : 0.85),
            _pl.withOpacity(dark ? 0.10 : 0.12),
          ]).createShader(Rect.fromCircle(center: c, radius: r)));
    // волны от Bluetooth
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      canvas.drawCircle(
          c.translate(0, -size.height * 0.10),
          r * (0.28 + phase * 0.55),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _p.withOpacity((1 - phase) * 0.16));
    }
    // дорожка и дуга
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = _p.withOpacity(0.14));
    final start = fixedProgress != null ? -math.pi / 2 : -math.pi / 2 + t * 2 * math.pi;
    final sweep = fixedProgress != null ? 2 * math.pi : math.pi * 0.78;
    canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 14
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: 2 * math.pi,
            transform: GradientRotation(start),
            colors: const [_pl, _p, Color(0xFF4B1D8F), _pl],
            stops: const [0.0, 0.5, 0.78, 1.0],
          ).createShader(rect));
    // яркая точка на конце дуги
    final end = start + sweep;
    final dot = c + Offset(math.cos(end), math.sin(end)) * r;
    canvas.drawCircle(dot, 12, Paint()..color = Colors.white);
    canvas.drawCircle(
        dot,
        20,
        Paint()
          ..color = _pl.withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // весы
    final cx = c.dx, top = c.dy + r * 0.03;
    final sw = r * 1.55, sh = r * 0.58;
    final body = Path()
      ..moveTo(cx - sw * 0.40, top)
      ..lineTo(cx + sw * 0.40, top)
      ..quadraticBezierTo(cx + sw * 0.46, top + sh * 0.05, cx + sw * 0.50, top + sh * 0.90)
      ..quadraticBezierTo(cx + sw * 0.50, top + sh, cx + sw * 0.42, top + sh)
      ..lineTo(cx - sw * 0.42, top + sh)
      ..quadraticBezierTo(cx - sw * 0.50, top + sh, cx - sw * 0.50, top + sh * 0.90)
      ..quadraticBezierTo(cx - sw * 0.46, top + sh * 0.05, cx - sw * 0.40, top)
      ..close();
    // свечение под весами
    canvas.drawPath(
        body.shift(Offset(0, sh * 0.10)),
        Paint()
          ..color = _p.withOpacity(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    canvas.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, const Color(0xFFE9DEFB)])
              .createShader(body.getBounds()));
    canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withOpacity(0.9));
    // электроды
    final metal = Paint()
      ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF4F4F8), Color(0xFFB9BBC6)])
          .createShader(Offset.zero & size);
    void electrode(double dx, double dy, double rx, double ry) {
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx + dx * sw, top + dy * sh), width: rx * sw, height: ry * sh),
          metal);
    }

    electrode(-0.20, 0.17, 0.17, 0.12);
    electrode(0.20, 0.17, 0.17, 0.12);
    electrode(-0.29, 0.62, 0.21, 0.20);
    electrode(0.29, 0.62, 0.21, 0.20);
  }

  @override
  bool shouldRepaint(_ScalePainter o) => o.t != t || o.fixedProgress != fixedProgress || o.dark != dark;
}

/// Фиолетовые волны внизу карточки текущего веса.
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final a = Path()
      ..moveTo(0, h * 0.78)
      ..quadraticBezierTo(w * 0.25, h * 0.62, w * 0.5, h * 0.80)
      ..quadraticBezierTo(w * 0.78, h * 0.98, w, h * 0.70)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(a, Paint()..color = _pl.withOpacity(0.20));
    final b = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.3, h * 0.74, w * 0.55, h * 0.88)
      ..quadraticBezierTo(w * 0.8, h * 1.0, w, h * 0.82)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(b, Paint()..color = _p.withOpacity(0.14));
  }

  @override
  bool shouldRepaint(_WavePainter o) => false;
}
