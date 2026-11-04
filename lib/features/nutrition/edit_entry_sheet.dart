import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

/// Правка записи дневника: приём пищи, количество (в тех же единицах: г/мл, порции, штуки)
/// с пересчётом КБЖУ, а для быстрых записей — название и значения.
Future<void> showEditEntrySheet(BuildContext context, AppDatabase db, FoodEntry entry) async {
  final product = entry.productId == null ? null : await db.productById(entry.productId!);
  double? recipeServing;
  if (entry.recipeId != null) {
    try {
      recipeServing = (await db.recipeResult(entry.recipeId!)).servingWeight;
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => EditEntrySheet(
      db: db,
      entry: entry,
      portionSize: product?.portionSize ?? recipeServing,
      pieceWeight: product?.pieceWeight,
    ),
  );
}

class EditEntrySheet extends StatefulWidget {
  final AppDatabase db;
  final FoodEntry entry;
  final double? portionSize, pieceWeight;
  const EditEntrySheet(
      {super.key, required this.db, required this.entry, this.portionSize, this.pieceWeight});

  @override
  State<EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<EditEntrySheet> {
  final _form = GlobalKey<FormState>();
  late Meal _meal = mealFromKey(widget.entry.mealType);
  late QtyUnit _unit = _initialUnit();
  late final _qty = TextEditingController(text: fmtInput(_initialQty()));
  late final _name = TextEditingController(text: widget.entry.name);
  late final _kcal = TextEditingController(text: fmtInput(widget.entry.caloriesSnapshot));
  late final _p = TextEditingController(text: fmtInput(widget.entry.proteinsSnapshot));
  late final _f = TextEditingController(text: fmtInput(widget.entry.fatsSnapshot));
  late final _c = TextEditingController(text: fmtInput(widget.entry.carbohydratesSnapshot));

  FoodEntry get e => widget.entry;
  bool get _manual => e.isManual;

  /// Количество можно менять, только если у записи есть масса.
  bool get _hasAmount => !e.isManual && e.amount > 0;

  String get _baseLabel => e.amountUnit == 'ml' ? 'мл' : 'г';

  List<QtyUnit> get _units => [
        QtyUnit.base,
        if (widget.portionSize != null) QtyUnit.portion,
        if (widget.pieceWeight != null) QtyUnit.piece,
      ];

  QtyUnit _initialUnit() {
    if (e.displayUnit == 'piece' && widget.pieceWeight != null) return QtyUnit.piece;
    if (e.displayUnit == 'portion' && widget.portionSize != null) return QtyUnit.portion;
    return QtyUnit.base;
  }

  double _initialQty() {
    final sameUnit = switch (_unit) {
      QtyUnit.piece => e.displayUnit == 'piece',
      QtyUnit.portion => e.displayUnit == 'portion',
      QtyUnit.base => e.displayUnit != 'piece' && e.displayUnit != 'portion',
    };
    return sameUnit && e.displayQty > 0 ? e.displayQty : e.amount;
  }

  @override
  void dispose() {
    for (final c in [_qty, _name, _kcal, _p, _f, _c]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setUnit(QtyUnit u) => setState(() {
        final amount = _amount();
        _unit = u;
        // Пересчитываем введённое число в новую единицу, чтобы масса не менялась.
        if (amount != null && amount > 0) {
          final q = switch (u) {
            QtyUnit.base => amount,
            QtyUnit.portion => amount / widget.portionSize!,
            QtyUnit.piece => amount / widget.pieceWeight!,
          };
          _qty.text = fmtInput(double.parse(q.toStringAsFixed(2)));
        }
      });

  double? _amount() {
    final q = parseNum(_qty.text);
    if (q == null || q <= 0) return null;
    return baseAmount(
        unit: _unit, qty: q, portionSize: widget.portionSize, pieceWeight: widget.pieceWeight);
  }

  Nutrients get _preview {
    final a = _amount();
    if (a == null || e.amount <= 0) return Nutrients.zero;
    final k = a / e.amount;
    return Nutrients(
        e.caloriesSnapshot * k, e.proteinsSnapshot * k, e.fatsSnapshot * k, e.carbohydratesSnapshot * k);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_manual) {
      await widget.db.updateFoodEntry(e,
          mealType: _meal.name,
          name: _name.text.trim().isEmpty ? 'Быстрая запись' : _name.text.trim(),
          kcal: parseNum(_kcal.text) ?? 0,
          p: parseNum(_p.text) ?? 0,
          f: parseNum(_f.text) ?? 0,
          c: parseNum(_c.text) ?? 0);
    } else if (_hasAmount) {
      final a = _amount();
      if (a == null) return;
      await widget.db.updateFoodEntry(e,
          mealType: _meal.name,
          amount: a,
          displayQty: parseNum(_qty.text),
          displayUnit: switch (_unit) {
            QtyUnit.base => e.amountUnit,
            QtyUnit.portion => 'portion',
            QtyUnit.piece => 'piece',
          });
    } else {
      await widget.db.updateFoodEntry(e, mealType: _meal.name);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = _preview;
    Widget cell(String l, String v) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
        );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_manual ? 'Изменить запись' : e.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (!_manual)
            Text('Изменить запись',
                style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 14),
          const Text('Приём пищи', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in Meal.values)
              ChoiceChip(
                label: Text(m.label),
                selected: _meal == m,
                onSelected: (_) => setState(() => _meal = m),
              ),
          ]),
          const SizedBox(height: 14),
          if (_manual) ...[
            TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 10),
            NumField(controller: _kcal, label: 'Калории', suffix: 'ккал', max: 10000),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: NumField(controller: _p, label: 'Белки', suffix: 'г', required: false, max: 1000)),
              const SizedBox(width: 8),
              Expanded(child: NumField(controller: _f, label: 'Жиры', suffix: 'г', required: false, max: 1000)),
              const SizedBox(width: 8),
              Expanded(child: NumField(controller: _c, label: 'Углеводы', suffix: 'г', required: false, max: 1000)),
            ]),
          ] else if (_hasAmount) ...[
            if (_units.length > 1)
              SegmentedButton<QtyUnit>(
                segments: [
                  for (final u in _units)
                    ButtonSegment(
                        value: u,
                        label: Text(switch (u) {
                          QtyUnit.base => _baseLabel,
                          QtyUnit.portion => 'порции',
                          QtyUnit.piece => 'штуки',
                        })),
                ],
                selected: {_unit},
                onSelectionChanged: (s) => _setUnit(s.first),
              ),
            if (_units.length > 1) const SizedBox(height: 12),
            TextFormField(
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: numFormatters,
              decoration: InputDecoration(
                  labelText: 'Количество',
                  suffixText: switch (_unit) {
                    QtyUnit.base => _baseLabel,
                    QtyUnit.portion => 'порц.',
                    QtyUnit.piece => 'шт.',
                  }),
              validator: numValidator(allowZero: false, max: 20000),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                cell('Ккал', fmt0(n.calories)),
                cell('Белки', fmt1(n.proteins)),
                cell('Жиры', fmt1(n.fats)),
                cell('Углеводы', fmt1(n.carbs)),
              ]),
            ),
          ] else
            Text('У этой записи нет количества: можно только сменить приём пищи.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Сохранить')),
        ]),
      ),
    );
  }
}
