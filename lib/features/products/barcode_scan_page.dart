import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../database/database.dart';
import '../../shared/widgets.dart';
import 'off_api.dart';
import 'product_form_page.dart';

class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});
  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  String? _code;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Штрихкод вручную'),
        content: TextField(
            controller: c, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && mounted) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              errorBuilder: (c, e) => EmptyHint(
                  'Камера недоступна (${e.errorCode.name}). Проверьте разрешение или введите код вручную.'),
              onDetect: (capture) {
                if (_code != null) return;
                final code = capture.barcodes
                    .map((b) => b.rawValue)
                    .whereType<String>()
                    .firstOrNull;
                if (code == null || !mounted) return;
                setState(() => _code = code);
              },
            ),
          ),
          Positioned.fill(
            child: ScanOverlay(
              code: _code,
              torch: ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  if (state.torchState == TorchState.unavailable) {
                    return const SizedBox(width: 48, height: 48);
                  }
                  final on = state.torchState == TorchState.on;
                  return _GlassButton(
                      icon: on ? Icons.flashlight_off_outlined : Icons.flashlight_on_outlined,
                      active: on,
                      onTap: _controller.toggleTorch);
                },
              ),
              onClose: () => Navigator.maybePop(context),
              onManual: _manual,
              onDone: (code) {
                if (mounted) Navigator.pop(context, code);
              },
            ),
          ),
        ]),
      );
}

const _scanGreen = Color(0xFF3CC24F);
const _scanPurple = Color(0xFF9145EC);

/// Слой интерфейса поверх камеры: затемнение с «окном», уголки, бегущий лазер и анимация
/// успеха при обнаружении кода. Не зависит от камеры, поэтому проверяется тестами.
class ScanOverlay extends StatefulWidget {
  /// Распознанный штрихкод: появление значения запускает анимацию успеха.
  final String? code;
  final Widget torch;
  final VoidCallback onClose, onManual;
  final ValueChanged<String> onDone;
  const ScanOverlay({
    super.key,
    required this.code,
    required this.torch,
    required this.onClose,
    required this.onManual,
    required this.onDone,
  });

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay> with TickerProviderStateMixin {
  late final AnimationController _scan =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))
        ..repeat(reverse: true);
  late final AnimationController _found =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  Timer? _hintTimer, _doneTimer;
  bool _slowHint = false;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && widget.code == null) setState(() => _slowHint = true);
    });
    if (widget.code != null) _onFound();
  }

  @override
  void didUpdateWidget(ScanOverlay old) {
    super.didUpdateWidget(old);
    if (old.code == null && widget.code != null) _onFound();
  }

  void _onFound() {
    _scan.stop();
    _found.forward();
    HapticFeedback.mediumImpact();
    final code = widget.code!;
    _doneTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) widget.onDone(code);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _doneTimer?.cancel();
    _scan.dispose();
    _found.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final w = size.width * 0.84;
    final h = math.min(w * 0.56, size.height * 0.30);
    final window = Rect.fromCenter(
        center: Offset(size.width / 2, pad.top + (size.height - pad.top) * 0.40),
        width: w,
        height: h);
    final found = widget.code != null;

    return Stack(children: [
      Positioned.fill(
        child: AnimatedBuilder(
          animation: Listenable.merge([_scan, _found]),
          builder: (_, __) => CustomPaint(
              painter: _ScanPainter(window, _scan.value, _found.value, found,
                  _scan.status != AnimationStatus.reverse)),
        ),
      ),
      // Вспышка в момент обнаружения
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _found,
            builder: (_, __) {
              final v = _found.value;
              final a = v < 0.22 ? (0.22 - v) / 0.22 * 0.35 : 0.0;
              return ColoredBox(color: Colors.white.withOpacity(a));
            },
          ),
        ),
      ),
      // Галочка успеха
      Positioned.fromRect(
        rect: window,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _found,
            builder: (_, __) {
              final v = Curves.elasticOut.transform(((_found.value - 0.15) / 0.6).clamp(0.0, 1.0));
              return Center(
                child: Transform.scale(
                  scale: found ? v : 0,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: _scanGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: _scanGreen.withOpacity(0.55), blurRadius: 30, spreadRadius: 2)
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, size: 58, color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      // Верхняя панель
      Positioned(
        left: 16,
        right: 16,
        top: pad.top + 8,
        child: Row(children: [
          _GlassButton(icon: Icons.close_rounded, onTap: widget.onClose),
          const Expanded(
            child: Text('Сканирование',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          widget.torch,
        ]),
      ),
      // Подсказка или распознанный код
      Positioned(
        left: 24,
        right: 24,
        top: window.bottom + 28,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                  child: c)),
          child: found
              ? _Pill(
                  key: const ValueKey('found'),
                  color: _scanGreen.withOpacity(0.92),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(widget.code!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5)),
                    ]),
                  ),
                )
              : _Pill(
                  key: ValueKey(_slowHint),
                  child: Text(
                      _slowHint
                          ? 'Не считывается? Держите ровнее и включите фонарик'
                          : 'Наведите камеру на штрихкод',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                ),
        ),
      ),
      // Ввод вручную
      Positioned(
        left: 24,
        right: 24,
        bottom: pad.bottom + 22,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: found ? 0 : 1,
          child: IgnorePointer(
            ignoring: found,
            child: _Pill(
              onTap: widget.onManual,
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.keyboard_alt_outlined, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Ввести штрихкод вручную',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Стеклянная круглая кнопка поверх камеры.
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _GlassButton({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.18),
                border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
              ),
              child: Icon(icon, color: active ? Colors.black87 : Colors.white, size: 26),
            ),
          ),
        ),
      );
}

/// Стеклянная плашка (подсказка, код, кнопка).
class _Pill extends StatelessWidget {
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  const _Pill({super.key, required this.child, this.color, this.onTap});

  @override
  Widget build(BuildContext context) => Center(
        child: GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                decoration: BoxDecoration(
                  color: color ?? Colors.black.withOpacity(0.38),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
}

class _ScanPainter extends CustomPainter {
  final Rect window;
  final double t; // положение лазера 0..1 (туда-обратно)
  final double found; // 0..1 анимация успеха
  final bool isFound;
  final bool down; // лазер движется вниз (шлейф сверху) или вверх (шлейф снизу)
  _ScanPainter(this.window, this.t, this.found, this.isFound, this.down);

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 28.0;
    // «Дыхание» рамки при поиске и «защёлкивание» при успехе
    final pulse = isFound ? 0.0 : (math.sin(t * math.pi) * 5);
    final snap = isFound ? -math.sin(found.clamp(0.0, 0.5) / 0.5 * math.pi) * 10 : 0.0;
    final rect = window.inflate(pulse + snap);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(radius));

    // Затемнение с вырезом
    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(rrect),
    );
    canvas.drawPath(overlay, Paint()..color = Colors.black.withOpacity(0.50 + 0.12 * found));

    // Лазер со световым шлейфом (только при поиске)
    if (!isFound) {
      canvas.save();
      canvas.clipRRect(rrect);
      final eased = Curves.easeInOut.transform(t);
      final y = rect.top + rect.height * eased;
      final dirDown = down;
      final trail = rect.height * 0.35;
      final trailRect = dirDown
          ? Rect.fromLTRB(rect.left, y - trail, rect.right, y)
          : Rect.fromLTRB(rect.left, y, rect.right, y + trail);
      canvas.drawRect(
        trailRect,
        Paint()
          ..shader = LinearGradient(
            begin: dirDown ? Alignment.topCenter : Alignment.bottomCenter,
            end: dirDown ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [_scanPurple.withOpacity(0.0), _scanPurple.withOpacity(0.38)],
          ).createShader(trailRect),
      );
      final lineRect = Rect.fromLTRB(rect.left + 12, y - 1.5, rect.right - 12, y + 1.5);
      canvas.drawRect(
          lineRect.inflate(4),
          Paint()
            ..color = _scanPurple.withOpacity(0.7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawRRect(
        RRect.fromRectAndRadius(lineRect, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.white.withOpacity(0.0),
            Colors.white,
            Colors.white,
            Colors.white.withOpacity(0.0),
          ], stops: const [0.0, 0.2, 0.8, 1.0])
              .createShader(lineRect),
      );
      canvas.restore();
    } else {
      // Заливка окна и расходящееся кольцо
      canvas.drawRRect(
          rrect, Paint()..color = _scanGreen.withOpacity(0.16 * Curves.easeOut.transform(found)));
      final ring = RRect.fromRectAndRadius(
          window.inflate(found * 70), Radius.circular(radius + found * 40));
      canvas.drawRRect(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = _scanGreen.withOpacity((1 - found) * 0.8));
    }

    // Угловые скобки
    final color = Color.lerp(Colors.white, _scanGreen, Curves.easeOut.transform(found))!;
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6
      ..color = color;
    if (isFound) {
      canvas.drawRRect(
          rrect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12
            ..color = _scanGreen.withOpacity(0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    const len = 38.0;
    void corner(Offset c, double dx, double dy) {
      final path = Path()
        ..moveTo(c.dx, c.dy + dy * len)
        ..lineTo(c.dx, c.dy + dy * radius)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + dx * radius, c.dy)
        ..lineTo(c.dx + dx * len, c.dy);
      canvas.drawPath(path, bracket);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_ScanPainter o) =>
      o.t != t || o.found != found || o.isFound != isFound || o.window != window || o.down != down;
}

/// Полный сценарий: сканирование → локальная база → (с согласия) онлайн-API
/// → форма ручного ввода с заполненным штрихкодом.
Future<Product?> scanProduct(BuildContext context, AppDatabase db) async {
  final code = await Navigator.push<String>(
      context, MaterialPageRoute(builder: (_) => const BarcodeScanPage()));
  if (code == null || !context.mounted) return null;

  final local = await db.productByBarcode(code);
  if (local != null) return local;

  OffResult? off;
  final ask = await confirmDialog(
      context,
      'Продукт не найден в базе',
      'Поискать штрихкод $code в Open Food Facts? '
          'В интернет будет отправлен только штрихкод.',
      ok: 'Искать');
  if (ask) {
    off = await lookupOpenFoodFacts(code);
    if (off == null && context.mounted) {
      toast(context, 'В онлайн-базе ничего не найдено или нет сети');
    }
  }
  if (!context.mounted) return null;

  if (off != null && !off.usable && off.complete && context.mounted) {
    toast(context, 'Данные Open Food Facts для этого штрихкода неправдоподобны и не используются');
  }
  if (off != null && off.usable) {
    final ok = await confirmDialog(
        context,
        off.name!,
        'Найдено (на 100 г): ${off.kcal!.round()} ккал, '
            'Б ${off.proteins}, Ж ${off.fats}, У ${off.carbs}.\nСохранить в свою базу?',
        ok: 'Сохранить');
    if (ok) {
      final id = await db.insertProduct(ProductsCompanion.insert(
        name: off.name!,
        brand: Value(off.brand),
        calories: off.kcal!,
        proteins: off.proteins!,
        fats: off.fats!,
        carbohydrates: off.carbs!,
        barcode: Value(code),
        source: const Value('Open Food Facts (ODbL)'),
        sourceId: Value(code),
      ));
      return db.productById(id);
    }
  }
  if (!context.mounted) return null;
  toast(context, 'Заполните данные продукта вручную');
  return Navigator.push<Product>(
      context,
      MaterialPageRoute(
          builder: (_) => ProductFormPage(
              initialBarcode: code, initialName: off?.name, initialBrand: off?.brand)));
}
