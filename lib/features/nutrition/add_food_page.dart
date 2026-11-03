import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../products/barcode_scan_page.dart';
import '../products/product_form_page.dart';
import 'diary_actions.dart';

/// Поиск продукта. В режиме [pickProduct] возвращает выбранный продукт,
/// иначе добавляет его в дневник.
class AddFoodPage extends ConsumerStatefulWidget {
  final String day;
  final Meal meal;
  final bool pickProduct;
  const AddFoodPage(
      {super.key, required this.day, required this.meal, this.pickProduct = false});
  @override
  ConsumerState<AddFoodPage> createState() => _AddFoodPageState();
}

class _AddFoodPageState extends ConsumerState<AddFoodPage> {
  String _query = '';
  String? _category;

  AppDatabase get db => ref.read(dbProvider);

  Future<void> _selected(Product p) async {
    if (widget.pickProduct) {
      Navigator.pop(context, p);
      return;
    }
    final added = await showAmountSheet(context, db, p, widget.day, widget.meal);
    if (added == true && mounted) toast(context, 'Добавлено: ${p.name}');
  }

  Future<void> _scan() async {
    final p = await scanProduct(context, db);
    if (p != null && mounted) await _selected(p);
  }

  Future<void> _create([String? name]) async {
    final p = await Navigator.push<Product>(context,
        MaterialPageRoute(builder: (_) => ProductFormPage(initialName: name)));
    if (p != null && mounted) await _selected(p);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(text: 'Поиск'),
      const Tab(text: 'Избранное'),
      const Tab(text: 'Недавние'),
      if (!widget.pickProduct) const Tab(text: 'Блюда'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pickProduct ? 'Выбор продукта' : widget.meal.label),
          actions: [
            IconButton(
                tooltip: 'Сканировать штрихкод',
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner)),
            IconButton(
                tooltip: 'Свой продукт',
                onPressed: _create,
                icon: const Icon(Icons.add_circle_outline)),
          ],
          bottom: TabBar(tabs: tabs, isScrollable: false),
        ),
        body: TabBarView(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Название продукта'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in [null, ...productCategories])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: ChoiceChip(
                        label: Text(c ?? 'Все'),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _ProductList(
                stream: db.watchProducts(query: _query, category: _category),
                onTap: _selected,
                emptyAction: _query.trim().isEmpty ? null : () => _create(_query.trim()),
                emptyLabel: 'Создать продукт «${_query.trim()}»',
              ),
            ),
          ]),
          _ProductList(
              stream: db.watchProducts(favoritesOnly: true),
              onTap: _selected,
              hint: 'Отмечайте продукты звёздочкой, и они появятся здесь'),
          _ProductList(
              stream: db.watchProducts(recentOnly: true, limit: 40),
              onTap: _selected,
              hint: 'Здесь появятся недавно добавленные продукты'),
          if (!widget.pickProduct) _RecipeList(day: widget.day, meal: widget.meal),
        ]),
      ),
    );
  }
}

String productSubtitle(Product p) {
  final u = p.measurementUnit == 'ml' ? '100 мл' : '100 г';
  final b = (p.brand == null || p.brand!.isEmpty) ? '' : '${p.brand} · ';
  return '$b${fmt0(p.calories)} ккал · Б ${fmtAuto(p.proteins)} Ж ${fmtAuto(p.fats)} У ${fmtAuto(p.carbohydrates)} на $u';
}

class _ProductList extends ConsumerWidget {
  final Stream<List<Product>> stream;
  final ValueChanged<Product> onTap;
  final String? hint, emptyLabel;
  final VoidCallback? emptyAction;
  const _ProductList(
      {required this.stream,
      required this.onTap,
      this.hint,
      this.emptyAction,
      this.emptyLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return StreamBuilder<List<Product>>(
      stream: stream,
      builder: (context, snap) {
        final list = snap.data ?? [];
        if (snap.hasData && list.isEmpty) {
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            EmptyHint(hint ?? 'Ничего не найдено.\nЕсли данных нет — введите их вручную.'),
            if (emptyAction != null)
              FilledButton.tonal(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: emptyAction,
                  child: Text(emptyLabel ?? 'Создать продукт')),
          ]);
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final p = list[i];
            return ListTile(
              title: Text(p.name),
              subtitle: Text(productSubtitle(p), maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => onTap(p),
              onLongPress: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ProductFormPage(product: p))),
              trailing: IconButton(
                icon: Icon(p.isFavorite ? Icons.star : Icons.star_border,
                    color: p.isFavorite ? Colors.amber : null),
                onPressed: () => db.setFavorite(p.id, !p.isFavorite),
              ),
            );
          },
        );
      },
    );
  }
}

class _RecipeList extends ConsumerWidget {
  final String day;
  final Meal meal;
  const _RecipeList({required this.day, required this.meal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return StreamBuilder<List<Recipe>>(
      stream: db.watchRecipes(),
      builder: (context, snap) {
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return const EmptyHint('Блюд пока нет. Создайте их в разделе «Мои блюда».');
        }
        return ListView(children: [
          for (final r in list)
            ListTile(
              leading: Icon(r.isFavorite ? Icons.star : Icons.menu_book_outlined),
              title: Text(r.name),
              subtitle: Text('Порций: ${r.servings}'),
              onTap: () async {
                final ok = await showRecipeAddDialog(context, db, r, day, meal);
                if (ok && context.mounted) toast(context, 'Добавлено: ${r.name}');
              },
            ),
        ]);
      },
    );
  }
}

/// Диалог добавления блюда в дневник (в порциях или граммах).
Future<bool> showRecipeAddDialog(BuildContext context, AppDatabase db, Recipe r,
    String day, Meal meal) async {
  final res = await db.recipeResult(r.id);
  if (res.rawWeight <= 0) {
    if (context.mounted) toast(context, 'В блюде нет ингредиентов');
    return false;
  }
  final qty = TextEditingController(text: '1');
  var byPortions = true;
  var m = meal;
  final form = GlobalKey<FormState>();
  final r2 = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final q = parseNum(qty.text) ?? 0;
        final n = byPortions ? res.perServing * q : nutrientsForAmount(res.per100, q);
        return AlertDialog(
          title: Text(r.name),
          content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Порции')),
                  ButtonSegment(value: false, label: Text('Граммы')),
                ],
                selected: {byPortions},
                onSelectionChanged: (s) => set(() {
                  byPortions = s.first;
                  qty.text = byPortions ? '1' : fmtAuto(res.servingWeight);
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(suffixText: byPortions ? 'порц.' : 'г'),
                validator: numValidator(allowZero: false, max: 20000),
                onChanged: (_) => set(() {}),
              ),
              const SizedBox(height: 8),
              DropdownButton<Meal>(
                value: m,
                isExpanded: true,
                items: [for (final x in Meal.values) DropdownMenuItem(value: x, child: Text(x.label))],
                onChanged: (v) => set(() => m = v!),
              ),
              Text('${fmt0(n.calories)} ккал · Б ${fmt1(n.proteins)} Ж ${fmt1(n.fats)} У ${fmt1(n.carbs)}'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
                onPressed: () {
                  if (form.currentState!.validate()) Navigator.pop(ctx, true);
                },
                child: const Text('Добавить')),
          ],
        );
      },
    ),
  );
  if (r2 != true) return false;
  await addRecipeEntry(db,
      day: day, meal: m, recipe: r, byPortions: byPortions, qty: parseNum(qty.text)!);
  return true;
}

/// Выбор количества и добавление продукта. true — запись добавлена.
Future<bool?> showAmountSheet(
    BuildContext context, AppDatabase db, Product p, String day, Meal meal) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AmountSheet(db: db, product: p, day: day, meal: meal),
  );
}

class _AmountSheet extends StatefulWidget {
  final AppDatabase db;
  final Product product;
  final String day;
  final Meal meal;
  const _AmountSheet(
      {required this.db, required this.product, required this.day, required this.meal});
  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _qty;
  QtyUnit _unit = QtyUnit.base;
  bool _drink = false;
  late Meal _meal = widget.meal;

  Product get p => widget.product;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: '100');
  }

  String get _baseLabel => p.measurementUnit == 'ml' ? 'мл' : 'г';

  void _setUnit(QtyUnit u) => setState(() {
        _unit = u;
        _qty.text = switch (u) {
          QtyUnit.base => '100',
          QtyUnit.portion => '1',
          QtyUnit.piece => '1',
        };
      });

  @override
  Widget build(BuildContext context) {
    final q = parseNum(_qty.text) ?? 0;
    final amount = baseAmount(
        unit: _unit, qty: q, portionSize: p.portionSize, pieceWeight: p.pieceWeight);
    final n = amount == null ? Nutrients.zero : nutrientsForAmount(productPer100(p), amount);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(productSubtitle(p),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SegmentedButton<QtyUnit>(
            segments: [
              ButtonSegment(value: QtyUnit.base, label: Text(_baseLabel)),
              if (p.portionSize != null)
                const ButtonSegment(value: QtyUnit.portion, label: Text('порции')),
              if (p.pieceWeight != null)
                const ButtonSegment(value: QtyUnit.piece, label: Text('штуки')),
            ],
            selected: {_unit},
            onSelectionChanged: (s) => _setUnit(s.first),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _qty,
            autofocus: true,
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
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _cell('Ккал', fmt0(n.calories)),
              _cell('Белки', fmt1(n.proteins)),
              _cell('Жиры', fmt1(n.fats)),
              _cell('Углеводы', fmt1(n.carbs)),
            ]),
          ),
          if (p.measurementUnit == 'ml')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _drink,
              onChanged: (v) => setState(() => _drink = v ?? false),
              title: const Text('Учесть объём в напитках'),
              subtitle: const Text('Калории не задваиваются'),
            ),
          DropdownButton<Meal>(
            value: _meal,
            isExpanded: true,
            items: [for (final x in Meal.values) DropdownMenuItem(value: x, child: Text(x.label))],
            onChanged: (v) => setState(() => _meal = v!),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              await addProductEntry(widget.db,
                  day: widget.day,
                  meal: _meal,
                  product: p,
                  unit: _unit,
                  qty: parseNum(_qty.text)!,
                  trackDrink: _drink);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: Text('Добавить в «${_meal.label}»'),
          ),
        ]),
      ),
    );
  }

  Widget _cell(String l, String v) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(l, style: const TextStyle(fontSize: 12)),
      ]);
}
