import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../calendar/calendar_page.dart';
import '../dashboard/day_data.dart';
import '../recipes/recipes_page.dart';
import 'add_food_page.dart';
import 'diary_actions.dart';

class NutritionPage extends ConsumerWidget {
  const NutritionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = dayKey(ref.watch(selectedDayProvider));
    final data = ref.watch(dayDataProvider(key));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DayBar(
          onCalendar: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const CalendarPage())),
          trailing: IconButton.filledTonal(
              tooltip: 'Мои блюда',
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const RecipesPage())),
              icon: const Icon(Icons.menu_book_outlined)),
        ),
        const SizedBox(height: 16),
        data.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => EmptyHint('Ошибка: $e'),
          data: (d) => Column(children: [
            for (final m in Meal.values) ...[
              MealCard(meal: m, data: d),
              const SizedBox(height: 14),
            ],
          ]),
        ),
      ],
    );
  }
}

class MealCard extends ConsumerWidget {
  final Meal meal;
  final DayData data;
  const MealCard({super.key, required this.meal, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final entries = data.food.where((e) => e.mealType == meal.name).toList();
    final t = data.mealTotal(meal.name);
    final cs = Theme.of(context).colorScheme;

    Future<void> add() async {
      if (!await guardPast(context, data.key)) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AddFoodPage(day: data.key, meal: meal)));
    }

    Future<void> repeatYesterday() async {
      if (!await guardPast(context, data.key)) return;
      final prev = dayKey(parseDayKey(data.key).subtract(const Duration(days: 1)));
      final n = await db.copyMeal(prev, data.key, meal.name);
      toast(context, n == 0 ? 'Вчера в этом приёме пищи нет записей' : 'Скопировано записей: $n');
    }

    Future<void> copyFrom() async {
      if (!await guardPast(context, data.key)) return;
      final d = await showDatePicker(
          context: context,
          initialDate: parseDayKey(data.key),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: 'Откуда копировать ${meal.label.toLowerCase()}');
      if (d == null) return;
      final n = await db.copyMeal(dayKey(d), data.key, meal.name);
      toast(context, n == 0 ? 'В выбранный день нет записей' : 'Скопировано записей: $n');
    }

    Future<void> quick() async {
      if (!await guardPast(context, data.key)) return;
      await showQuickAdd(context, db, data.key, meal);
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: meal.color.withOpacity(0.16),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(meal.icon, color: meal.color),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(meal.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          Text('${fmt0(t.calories)} ккал',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'yesterday') repeatYesterday();
              if (v == 'copy') copyFrom();
              if (v == 'quick') quick();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'yesterday',
                  child: Text('Повторить вчерашний ${meal.label.toLowerCase()}')),
              const PopupMenuItem(value: 'copy', child: Text('Копировать из другого дня…')),
              const PopupMenuItem(value: 'quick', child: Text('Быстрое добавление калорий')),
            ],
          ),
        ]),
        const SizedBox(height: 4),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Пока ничего не добавлено',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final e in entries)
          _EntryTile(entry: e, dayKeyStr: data.key),
        if (entries.isNotEmpty) ...[
          const Divider(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _total('Калории', '${fmt0(t.calories)} ккал'),
            _total('Белки', '${fmt0(t.proteins)} г'),
            _total('Жиры', '${fmt0(t.fats)} г'),
            _total('Углеводы', '${fmt0(t.carbs)} г'),
          ]),
        ],
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
            onPressed: add,
            icon: const Icon(Icons.add),
            label: const Text('Добавить продукт')),
      ]),
    );
  }

  Widget _total(String l, String v) => Column(children: [
        Text(l, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

class _EntryTile extends ConsumerWidget {
  final FoodEntry entry;
  final String dayKeyStr;
  const _EntryTile({required this.entry, required this.dayKeyStr});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: entry.amount > 0
          ? () async {
              if (!await guardPast(context, dayKeyStr)) return;
              final v = await promptNumber(context, 'Количество: ${entry.name}',
                  initial: entry.amount,
                  suffix: entry.amountUnit == 'ml' ? 'мл' : 'г',
                  allowZero: false,
                  max: 20000);
              if (v != null) await db.updateFoodAmount(entry, v);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                  '${entryQtyText(entry)}${entry.isManual ? '  •  введено вручную' : ''}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
          ),
          Text('${fmt0(entry.caloriesSnapshot)} ккал'),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 20, color: cs.onSurfaceVariant),
            onPressed: () async {
              if (!await guardPast(context, dayKeyStr)) return;
              await db.deleteFood(entry.id);
            },
          ),
        ]),
      ),
    );
  }
}

Future<void> showQuickAdd(
    BuildContext context, AppDatabase db, String day, Meal meal) async {
  final name = TextEditingController();
  final k = TextEditingController(), p = TextEditingController();
  final f = TextEditingController(), c = TextEditingController();
  final form = GlobalKey<FormState>();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Быстрое добавление: ${meal.label}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название (необязательно)')),
          const SizedBox(height: 10),
          NumField(controller: k, label: 'Калории', suffix: 'ккал', max: 10000),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: NumField(controller: p, label: 'Белки', suffix: 'г', required: false, max: 1000)),
            const SizedBox(width: 8),
            Expanded(child: NumField(controller: f, label: 'Жиры', suffix: 'г', required: false, max: 1000)),
            const SizedBox(width: 8),
            Expanded(child: NumField(controller: c, label: 'Углеводы', suffix: 'г', required: false, max: 1000)),
          ]),
          const SizedBox(height: 14),
          FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                await addManualEntry(db,
                    day: day,
                    meal: meal,
                    name: name.text.trim(),
                    kcal: parseNum(k.text)!,
                    p: parseNum(p.text) ?? 0,
                    f: parseNum(f.text) ?? 0,
                    c: parseNum(c.text) ?? 0);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Добавить')),
        ]),
      ),
    ),
  );
}
