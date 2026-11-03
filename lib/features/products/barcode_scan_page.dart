import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
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
  bool _done = false;

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
        appBar: AppBar(title: const Text('Сканер штрихкода'), actions: [
          IconButton(
              onPressed: () => _controller.toggleTorch(),
              icon: const Icon(Icons.flashlight_on_outlined)),
        ]),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            errorBuilder: (c, e) => EmptyHint(
                'Камера недоступна (${e.errorCode.name}). Проверьте разрешение или введите код вручную.'),
            onDetect: (capture) {
              if (_done) return;
              final code = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .firstOrNull;
              if (code == null) return;
              _done = true;
              Navigator.pop(context, code);
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: FilledButton.tonal(
                onPressed: _manual, child: const Text('Ввести штрихкод вручную')),
          ),
        ]),
      );
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

  if (off != null && off.complete) {
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
        source: const Value('Open Food Facts'),
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
