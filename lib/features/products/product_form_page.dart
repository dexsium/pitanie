import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

class ProductFormPage extends ConsumerStatefulWidget {
  final Product? product;
  final String? initialName, initialBarcode, initialBrand;
  const ProductFormPage(
      {super.key, this.product, this.initialName, this.initialBarcode, this.initialBrand});
  @override
  ConsumerState<ProductFormPage> createState() => _State();
}

class _State extends ConsumerState<ProductFormPage> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.product?.name ?? widget.initialName ?? '');
  late final brand = TextEditingController(text: widget.product?.brand ?? widget.initialBrand ?? '');
  late final kcal = TextEditingController(text: _n(widget.product?.calories));
  late final prot = TextEditingController(text: _n(widget.product?.proteins));
  late final fat = TextEditingController(text: _n(widget.product?.fats));
  late final carb = TextEditingController(text: _n(widget.product?.carbohydrates));
  late final portion = TextEditingController(text: _n(widget.product?.portionSize));
  late final piece = TextEditingController(text: _n(widget.product?.pieceWeight));
  late final barcode = TextEditingController(text: widget.product?.barcode ?? widget.initialBarcode ?? '');
  late String category = widget.product?.category ?? 'Прочее';
  late String unit = widget.product?.measurementUnit ?? 'g';

  String _n(double? v) => v == null ? '' : fmtAuto(v);

  bool get _editing => widget.product != null;
  bool get _locked => _editing && !widget.product!.isCustom;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final p = parseNum(prot.text)!, f = parseNum(fat.text)!, c = parseNum(carb.text)!;
    if (p + f + c > 100.5) {
      toast(context, 'Сумма белков, жиров и углеводов на 100 г не может превышать 100');
      return;
    }
    final db = ref.read(dbProvider);
    final code = barcode.text.trim();
    if (code.isNotEmpty) {
      final dup = await db.productByBarcode(code);
      if (dup != null && dup.id != widget.product?.id) {
        toast(context, 'Продукт с таким штрихкодом уже есть: ${dup.name}');
        return;
      }
    }
    final comp = ProductsCompanion(
      name: Value(name.text.trim()),
      brand: Value(brand.text.trim().isEmpty ? null : brand.text.trim()),
      category: Value(category),
      calories: Value(parseNum(kcal.text)!),
      proteins: Value(p),
      fats: Value(f),
      carbohydrates: Value(c),
      measurementUnit: Value(unit),
      portionSize: Value(parseNum(portion.text)),
      pieceWeight: Value(parseNum(piece.text)),
      barcode: Value(code.isEmpty ? null : code),
    );
    int id;
    if (_editing) {
      id = widget.product!.id;
      await db.updateProduct(id, comp);
    } else {
      id = await db.insertProduct(comp.copyWith(
          source: const Value('Пользователь'), isCustom: const Value(true)));
    }
    final saved = await db.productById(id);
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, 'Удалить продукт?',
        'Записи дневника сохранятся, изменится только каталог.',
        ok: 'Удалить')) {
      return;
    }
    final ok = await ref.read(dbProvider).deleteCustomProduct(widget.product!.id);
    if (!mounted) return;
    if (!ok) {
      toast(context, 'Продукт используется в блюде. Сначала уберите его из рецепта.');
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final u = unit == 'ml' ? '100 мл' : '100 г';
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Продукт' : 'Новый продукт'),
        actions: [
          if (_editing && !_locked)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_locked)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Справочный продукт нельзя изменить. Создайте свой на его основе.'),
            ),
          AbsorbPointer(
            absorbing: _locked,
            child: Column(children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                  controller: brand,
                  decoration: const InputDecoration(labelText: 'Производитель (необязательно)')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: [for (final c in productCategories) DropdownMenuItem(value: c, child: Text(c))],
                onChanged: (v) => setState(() => category = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: unit,
                decoration: const InputDecoration(labelText: 'Единица измерения'),
                items: const [
                  DropdownMenuItem(value: 'g', child: Text('Граммы (значения на 100 г)')),
                  DropdownMenuItem(value: 'ml', child: Text('Миллилитры (значения на 100 мл)')),
                ],
                onChanged: (v) => setState(() => unit = v!),
              ),
              const SizedBox(height: 12),
              NumField(controller: kcal, label: 'Калории на $u', suffix: 'ккал', max: 950),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: NumField(controller: prot, label: 'Белки', suffix: 'г', max: 100)),
                const SizedBox(width: 8),
                Expanded(child: NumField(controller: fat, label: 'Жиры', suffix: 'г', max: 100)),
                const SizedBox(width: 8),
                Expanded(child: NumField(controller: carb, label: 'Углеводы', suffix: 'г', max: 100)),
              ]),
              const SizedBox(height: 12),
              NumField(
                  controller: portion,
                  label: 'Масса стандартной порции',
                  suffix: unit == 'ml' ? 'мл' : 'г',
                  required: false,
                  allowZero: false,
                  max: 5000),
              const SizedBox(height: 12),
              NumField(
                  controller: piece,
                  label: 'Масса одной штуки',
                  suffix: 'г',
                  required: false,
                  allowZero: false,
                  max: 5000),
              const SizedBox(height: 12),
              TextFormField(
                controller: barcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Штрихкод (необязательно)'),
              ),
            ]),
          ),
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Источник данных: ${widget.product!.source}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 20),
          if (!_locked)
            FilledButton(onPressed: _save, child: const Text('Сохранить')),
        ]),
      ),
    );
  }
}
