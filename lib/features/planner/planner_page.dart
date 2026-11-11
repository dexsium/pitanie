import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../nutrition/add_food_page.dart';
import '../nutrition/diary_actions.dart';

/// Понедельник недели, в которую входит [d].
DateTime weekStartOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Сумма КБЖУ запланированных позиций.
Nutrients planTotal(Iterable<MealPlanItem> items) => items.fold(
    Nutrients.zero,
    (s, e) => s +
        Nutrients(e.caloriesSnapshot, e.proteinsSnapshot, e.fatsSnapshot, e.carbohydratesSnapshot));

/// Планировщик питания на неделю. План хранится отдельно от дневника: запланированное не
/// считается съеденным, пока его не перенесли в дневник.
class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  DateTime _week = weekStartOf(DateTime.now());

  Future<void> _add(DateTime day, Meal meal) async {
    final db = ref.read(dbProvider);
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Что запланировать?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ListTile(
              leading: const Icon(Icons.apple_outlined),
              title: const Text('Продукт'),
              onTap: () => Navigator.pop(ctx, 'product')),
          ListTile(
              leading: const Icon(Icons.soup_kitchen_outlined),
              title: const Text('Блюдо из «Моих блюд»'),
              onTap: () => Navigator.pop(ctx, 'recipe')),
        ]),
      ),
    );
    if (kind == null || !mounted) return;
    final dk = dayKey(day);
    if (kind == 'product') {
      final pr = await Navigator.push<Product>(
          context,
          MaterialPageRoute(
              builder: (_) => AddFoodPage(day: dk, meal: meal, pickProduct: true)));
      if (pr == null || !mounted) return;
      final grams = await promptNumber(context, 'Масса, ${pr.measurementUnit == 'ml' ? 'мл' : 'г'}',
          initial: pr.portionSize ?? 100, suffix: pr.measurementUnit == 'ml' ? 'мл' : 'г', max: 5000, allowZero: false);
      if (grams == null) return;
      final n = nutrientsForAmount(productPer100(pr), grams);
      await db.addPlanItem(MealPlanItemsCompanion.insert(
        date: dk,
        mealType: meal.name,
        name: pr.name,
        caloriesSnapshot: n.calories,
        proteinsSnapshot: n.proteins,
        fatsSnapshot: n.fats,
        carbohydratesSnapshot: n.carbs,
        productId: Value(pr.id),
        amount: Value(grams),
        amountUnit: Value(pr.measurementUnit),
        displayQty: Value(grams),
        displayUnit: Value(pr.measurementUnit),
      ));
    } else {
      final recipes = await db.watchRecipes().first;
      if (!mounted) return;
      if (recipes.isEmpty) {
        toast(context, 'Сначала создайте блюдо в разделе «Мои блюда»');
        return;
      }
      final r = await showDialog<Recipe>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('Выберите блюдо'), children: [
          for (final x in recipes)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, x), child: Text(x.name)),
        ]),
      );
      if (r == null || !mounted) return;
      final qty = await promptNumber(context, 'Порций', initial: 1, suffix: 'порц.', max: 50, allowZero: false);
      if (qty == null) return;
      final res = await db.recipeResult(r.id);
      final n = res.perServing * qty;
      await db.addPlanItem(MealPlanItemsCompanion.insert(
        date: dk,
        mealType: meal.name,
        name: r.name,
        caloriesSnapshot: n.calories,
        proteinsSnapshot: n.proteins,
        fatsSnapshot: n.fats,
        carbohydratesSnapshot: n.carbs,
        recipeId: Value(r.id),
        amount: Value(res.servingWeight * qty),
        displayQty: Value(qty),
        displayUnit: const Value('portion'),
      ));
    }
  }

  Future<void> _copyDay(DateTime from) async {
    final to = await showDatePicker(
        context: context,
        initialDate: from.add(const Duration(days: 1)),
        firstDate: DateTime.now().subtract(const Duration(days: 30)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        helpText: 'Скопировать меню на дату');
    if (to == null || !mounted) return;
    final n = await ref.read(dbProvider).copyPlanDay(dayKey(from), dayKey(to));
    if (mounted) toast(context, n == 0 ? 'В этом дне нет плана' : 'Скопировано позиций: $n');
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    final end = _week.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(title: const Text('Планировщик питания'), actions: [
        IconButton(
          tooltip: 'Список покупок',
          icon: const Icon(Icons.shopping_cart_outlined),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ShoppingPage(weekStart: dayKey(_week)))),
        ),
      ]),
      body: StreamBuilder<List<MealPlanItem>>(
        stream: db.watchPlan(dayKey(_week), dayKey(end)),
        builder: (context, snap) {
          final items = snap.data ?? const <MealPlanItem>[];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Row(children: [
              IconButton(
                  onPressed: () => setState(() => _week = _week.subtract(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                  child: Text('${shortDate(_week)} – ${shortDate(end)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(
                  onPressed: () => setState(() => _week = _week.add(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_right)),
            ]),
            const SizedBox(height: 4),
            for (var i = 0; i < 7; i++)
              _dayCard(_week.add(Duration(days: i)),
                  [for (final x in items) if (x.date == dayKey(_week.add(Duration(days: i)))) x], cs),
          ]);
        },
      ),
    );
  }

  Widget _dayCard(DateTime day, List<MealPlanItem> items, ColorScheme cs) {
    final db = ref.read(dbProvider);
    final total = planTotal(items);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dayDateLine(day), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(
                  items.isEmpty
                      ? 'План не составлен'
                      : 'План: ${fmt0(total.calories)} ккал · Б ${fmt0(total.proteins)} Ж ${fmt0(total.fats)} У ${fmt0(total.carbs)}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'copy') await _copyDay(day);
              if (v == 'clear') {
                if (await confirmDialog(context, 'Очистить план дня?', 'Дневник не изменится.',
                    ok: 'Очистить')) {
                  await db.clearPlanDay(dayKey(day));
                }
              }
              if (v == 'all') {
                var n = 0;
                for (final x in items.where((x) => !x.done)) {
                  if (await db.transferPlanItemToDiary(x.id)) n++;
                }
                if (mounted) toast(context, n == 0 ? 'Переносить нечего' : 'Перенесено в дневник: $n');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'copy', child: Text('Скопировать меню на другую дату…')),
              PopupMenuItem(
                  value: 'all',
                  enabled: items.any((x) => !x.done),
                  child: const Text('Перенести всё в дневник')),
              PopupMenuItem(
                  value: 'clear', enabled: items.isNotEmpty, child: const Text('Очистить день')),
            ],
          ),
        ]),
        for (final m in Meal.values) ...[
          const Divider(height: 14),
          Row(children: [
            Icon(m.icon, size: 18, color: m.color),
            const SizedBox(width: 6),
            Expanded(child: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Запланировать',
                icon: const Icon(Icons.add_circle_outline, color: kPrimary),
                onPressed: () => _add(day, m)),
          ]),
          for (final x in items.where((x) => x.mealType == m.name))
            Row(children: [
              Expanded(
                child: Text(x.name,
                    style: TextStyle(
                        decoration: x.done ? TextDecoration.lineThrough : null,
                        color: x.done ? cs.onSurfaceVariant : null)),
              ),
              Text('${fmt0(x.caloriesSnapshot)} ккал',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (v) async {
                  if (v == 'diary') {
                    final ok = await db.transferPlanItemToDiary(x.id);
                    if (mounted) toast(context, ok ? 'Добавлено в дневник' : 'Уже перенесено');
                  }
                  if (v == 'del') await db.deletePlanItem(x.id);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'diary', enabled: !x.done, child: const Text('Перенести в дневник')),
                  const PopupMenuItem(value: 'del', child: Text('Удалить из плана')),
                ],
              ),
            ]),
        ],
      ]),
    );
  }
}

/// Список покупок недели: строится по плану, позиции можно отмечать и добавлять вручную.
class ShoppingPage extends ConsumerStatefulWidget {
  final String weekStart;
  const ShoppingPage({super.key, required this.weekStart});

  @override
  ConsumerState<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends ConsumerState<ShoppingPage> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Первое открытие: список сразу строится по плану недели.
    ref.read(dbProvider).buildShoppingList(widget.weekStart);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Список покупок'), actions: [
        IconButton(
          tooltip: 'Обновить по плану',
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            final n = await db.buildShoppingList(widget.weekStart);
            if (context.mounted) toast(context, 'Позиций по плану: $n');
          },
        ),
      ]),
      body: StreamBuilder<List<ShoppingItem>>(
        stream: db.watchShopping(widget.weekStart),
        builder: (context, snap) {
          final list = snap.data ?? const <ShoppingItem>[];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(hintText: 'Добавить своё'),
                  onSubmitted: (_) => _addManual(db),
                ),
              ),
              IconButton(onPressed: () => _addManual(db), icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const EmptyHint('В плане недели нет продуктов. Запланируйте блюда или продукты.'),
            for (final x in list)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: x.checked,
                onChanged: (v) => db.toggleShopping(x.id, v ?? false),
                title: Text(x.name,
                    style: TextStyle(decoration: x.checked ? TextDecoration.lineThrough : null)),
                subtitle: x.grams > 0 ? Text('${fmt0(x.grams)} г') : null,
                secondary: x.manual
                    ? IconButton(
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                        onPressed: () => db.deleteShopping(x.id))
                    : null,
              ),
            if (list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    'Количества посчитаны по ингредиентам блюд и массе продуктов в плане, без учёта '
                    'потерь и остатков дома.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
          ]);
        },
      ),
    );
  }

  void _addManual(AppDatabase db) {
    final t = _name.text.trim();
    if (t.isEmpty) return;
    db.addManualShopping(widget.weekStart, t);
    _name.clear();
  }
}
