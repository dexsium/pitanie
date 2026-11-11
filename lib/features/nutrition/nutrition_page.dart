import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../database/database.dart';
import '../ai/ai_photo_page.dart';
import '../../shared/widgets.dart';
import '../calendar/calendar_page.dart';
import '../dashboard/day_data.dart';
import '../products/barcode_scan_page.dart';
import '../recipes/recipes_page.dart';
import 'add_food_page.dart';
import 'diary_actions.dart';
import 'edit_entry_sheet.dart';
import 'meal_templates.dart';
import '../ads/ad_slot.dart';
import '../ads/ads_models.dart';
import '../planner/planner_page.dart';

class NutritionPage extends ConsumerWidget {
  const NutritionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(selectedDayProvider);
    final key = dayKey(sel);
    final data = ref.watch(dayDataProvider(key));
    final cs = Theme.of(context).colorScheme;
    void shift(int d) => ref.read(selectedDayProvider.notifier).state =
        DateTime(sel.year, sel.month, sel.day + d);

    Future<void> addMeal(DayData d) async {
      if (!await guardPast(context, d.key)) return;
      if (!context.mounted) return;
      final m = await showModalBottomSheet<Meal>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Выберите приём пищи',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            for (final m in Meal.values)
              ListTile(
                  leading: Icon(m.icon, color: m.color),
                  title: Text(m.label),
                  onTap: () => Navigator.pop(ctx, m)),
          ]),
        ),
      );
      if (m != null && context.mounted) {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => AddFoodPage(day: d.key, meal: m)));
      }
    }

    Future<void> copyDay() async {
      if (!await guardPast(context, key)) return;
      if (!context.mounted) return;
      final from = await showDatePicker(
          context: context,
          initialDate: sel.subtract(const Duration(days: 1)),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: 'Откуда копировать весь день');
      if (from == null || !context.mounted) return;
      final fk = dayKey(from);
      if (fk == key) {
        toast(context, 'Выберите другую дату');
        return;
      }
      if (!await confirmDialog(context, 'Скопировать день?',
          'Все приёмы пищи за ${dayDateLine(from)} будут добавлены к выбранному дню.',
          ok: 'Скопировать')) {
        return;
      }
      final n = await ref.read(dbProvider).copyDay(fk, key);
      if (context.mounted) {
        toast(context, n == 0 ? 'В выбранный день нет записей' : 'Скопировано записей: $n');
      }
    }

    void openAdd(int tab) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                AddFoodPage(day: key, meal: mealForNow(), initialTab: tab)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [
          IconButton.filledTonal(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CalendarPage())),
              icon: const Icon(Icons.calendar_month_rounded)),
          IconButton(
              onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: GestureDetector(
              onTap: () => ref.read(selectedDayProvider.notifier).state =
                  dayStart(DateTime.now()),
              onHorizontalDragEnd: (e) {
                final v = e.primaryVelocity ?? 0;
                if (v > 200) shift(-1);
                if (v < -200) shift(1);
              },
              child: Column(children: [
                const Text('Питание',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text(dayDateLine(sel),
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
            ),
          ),
          IconButton(
              tooltip: 'Следующий день',
              onPressed: () => shift(1),
              icon: const Icon(Icons.chevron_right)),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            style: IconButton.styleFrom(backgroundColor: cs.secondaryContainer),
            onSelected: (v) {
              if (v == 'recipes') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RecipesPage()));
              }
              if (v == 'copy_day') copyDay();
              if (v == 'planner') {
                Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const PlannerPage()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recipes', child: Text('Мои блюда')),
              PopupMenuItem(value: 'planner', child: Text('Планировщик питания')),
              PopupMenuItem(value: 'copy_day', child: Text('Скопировать день из другой даты…')),
            ],
          ),
        ]),
        const SizedBox(height: 16),
        data.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => EmptyHint('Ошибка: $e'),
          data: (d) => Column(children: [
            _Summary(d),
            // Рекламный блок под карточкой калорий и БЖУ.
            const AdSlot(AdPlacement.nutritionBanner),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  const _Chip('Приёмы пищи', Icons.restaurant, true, null),
                  _Chip('Продукты', Icons.apple_outlined, false, () => openAdd(0)),
                  _Chip('Блюда', Icons.soup_kitchen_outlined, false, () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RecipesPage()));
                  }),
                  _Chip('Избранное', Icons.star_border, false, () => openAdd(1)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            for (final m in Meal.values) ...[
              MealCard(key: ValueKey('${d.key}-${m.name}'), meal: m, data: d),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder()),
                onPressed: () => addMeal(d),
                icon: const Icon(Icons.add),
                label: const Text('Добавить приём пищи',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          ]),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  const _Chip(this.label, this.icon, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected ? kPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: selected ? Colors.white : cs.onSurface),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : cs.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final DayData d;
  const _Summary(this.d);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = d.calorieTarget;
    final e = d.eaten;
    Widget macro(String l, IconData i, Color c, double v, double g) {
      final pct = g > 0 ? v / g : 0.0;
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(i, color: c, size: 18),
            const SizedBox(width: 4),
            Flexible(
                child: Text(l,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 6),
          Text('${fmt0(v)} г',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text('из ${fmt0(g)} г',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 8,
                color: c,
                backgroundColor: c.withOpacity(0.18)),
          ),
          Align(
              alignment: Alignment.centerRight,
              child: Text('${(pct * 100).round()}%',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
        ]),
      );
    }

    final divider = Container(
        width: 1,
        height: 110,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: cs.outlineVariant);
    return AppCard(
      child: Row(children: [
        CalorieRing(
          size: 120,
          progress: target > 0 ? e.calories / target : 0,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(fmt0(e.calories),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const Text('ккал', style: TextStyle(fontSize: 13)),
            Text('из ${fmt0(target)}',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 12),
        macro('Белки', Icons.fitness_center, kBlue, e.proteins, d.goal.proteins),
        divider,
        macro('Жиры', Icons.water_drop_outlined, kOrange, e.fats, d.goal.fats),
        divider,
        macro('Углеводы', Icons.grass, kViolet, e.carbs, d.goal.carbs),
      ]),
    );
  }
}

class MealCard extends ConsumerStatefulWidget {
  final Meal meal;
  final DayData data;
  const MealCard({super.key, required this.meal, required this.data});
  @override
  ConsumerState<MealCard> createState() => _MealCardState();
}

class _MealCardState extends ConsumerState<MealCard> {
  late bool _open = widget.data.food.any((e) => e.mealType == widget.meal.name);

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal, data = widget.data;
    final db = ref.read(dbProvider);
    final entries = data.food.where((e) => e.mealType == meal.name).toList();
    final t = data.mealTotal(meal.name);
    final cs = Theme.of(context).colorScheme;

    Future<void> add() async {
      if (!await guardPast(context, data.key)) return;
      if (!context.mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AddFoodPage(day: data.key, meal: meal)));
    }

    Future<void> photo() async {
      if (!await guardPast(context, data.key)) return;
      if (!context.mounted) return;
      await openAiPhoto(context, db, day: data.key, meal: meal);
    }

    Future<void> scan() async {
      if (!await guardPast(context, data.key)) return;
      if (!context.mounted) return;
      final p = await scanProduct(context, db);
      if (p != null && context.mounted) {
        final ok = await showAmountSheet(context, db, p, data.key, meal);
        if (ok == true && context.mounted) toast(context, 'Добавлено: ${p.name}');
      }
    }

    Future<void> repeatYesterday() async {
      if (!await guardPast(context, data.key)) return;
      final prev = dayKey(parseDayKey(data.key).subtract(const Duration(days: 1)));
      final n = await db.copyMeal(prev, data.key, meal.name);
      if (context.mounted) {
        toast(context, n == 0 ? 'Вчера в этом приёме пищи нет записей' : 'Скопировано записей: $n');
      }
    }

    Future<void> repeatLast() async {
      if (!await guardPast(context, data.key)) return;
      final n = await db.repeatLastMeal(data.key, meal.name);
      if (context.mounted) {
        toast(context,
            n == 0 ? 'Раньше этот приём пищи не записывался' : 'Скопировано записей: $n');
      }
    }

    Future<void> saveTemplate() => saveMealAsTemplate(context, db, data.key, meal);

    Future<void> fromTemplate() async {
      if (!await guardPast(context, data.key)) return;
      if (!context.mounted) return;
      await showMealTemplatePicker(context, db, data.key, meal);
    }

    Future<void> copyFrom() async {
      if (!await guardPast(context, data.key)) return;
      if (!context.mounted) return;
      final d = await showDatePicker(
          context: context,
          initialDate: parseDayKey(data.key),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: 'Откуда копировать ${meal.label.toLowerCase()}');
      if (d == null) return;
      final n = await db.copyMeal(dayKey(d), data.key, meal.name);
      if (context.mounted) {
        toast(context, n == 0 ? 'В выбранный день нет записей' : 'Скопировано записей: $n');
      }
    }

    Future<void> quick() async {
      if (!await guardPast(context, data.key)) return;
      if (!context.mounted) return;
      await showQuickAdd(context, db, data.key, meal);
    }

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _open = !_open),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: meal.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(meal.icon, color: meal.color, size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(meal.label,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Б:${fmt0(t.proteins)} г   Ж: ${fmt0(t.fats)} г   У: ${fmt0(t.carbs)} г',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ]),
            ),
            Text('${fmt0(t.calories)} ккал',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            PopupMenuButton<String>(
              icon: Icon(_open ? Icons.chevron_right : Icons.expand_more),
              onSelected: (v) {
                if (v == 'last') repeatLast();
                if (v == 'yesterday') repeatYesterday();
                if (v == 'save_tpl') saveTemplate();
                if (v == 'tpl') fromTemplate();
                if (v == 'copy') copyFrom();
                if (v == 'quick') quick();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'last', child: Text('Повторить последний ${meal.label.toLowerCase()}')),
                PopupMenuItem(
                    value: 'yesterday',
                    child: Text('Повторить вчерашний ${meal.label.toLowerCase()}')),
                const PopupMenuItem(value: 'copy', child: Text('Копировать из другого дня…')),
                const PopupMenuItem(value: 'quick', child: Text('Быстрое добавление калорий')),
                const PopupMenuItem(value: 'tpl', child: Text('Добавить из шаблона…')),
                PopupMenuItem(
                    value: 'save_tpl',
                    enabled: entries.isNotEmpty,
                    child: const Text('Сохранить как шаблон…')),
              ],
            ),
          ]),
        ),
        if (_open) ...[
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Пока ничего не добавлено',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          // Первая полоска не должна касаться значка приёма пищи.
          if (entries.isNotEmpty) const SizedBox(height: 6),
          for (final e in entries) ...[
            const Divider(height: 1),
            _EntryTile(entry: e, dayKeyStr: data.key),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: kPrimary,
                      shape: const StadiumBorder()),
                  onPressed: add,
                  icon: const Icon(Icons.add),
                  label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Добавить продукт',
                          style: TextStyle(fontWeight: FontWeight.w700)))),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
                tooltip: 'Распознать еду по фото',
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: photo,
                icon: const Icon(Icons.photo_camera_outlined, color: kPrimary)),
            const SizedBox(width: 6),
            IconButton.filledTonal(
                tooltip: 'Сканировать штрихкод',
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: scan,
                icon: const Icon(Icons.qr_code_scanner, color: kPrimary)),
            const SizedBox(width: 6),
            IconButton.filledTonal(
                tooltip: 'Быстрое добавление калорий',
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: quick,
                icon: const Icon(Icons.add_circle_outline, color: kPrimary)),
          ]),
        ],
      ]),
    );
  }
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
      onTap: () async {
        if (!await guardPast(context, dayKeyStr)) return;
        if (context.mounted) await showEditEntrySheet(context, db, entry);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.restaurant_menu, size: 22, color: cs.onSurfaceVariant),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                  '${entryQtyText(entry)}${entry.isManual ? '  •  введено вручную' : ''}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
          ),
          Text('${fmt0(entry.caloriesSnapshot)} ккал',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Изменить',
            icon: Icon(Icons.edit_outlined, size: 20, color: cs.onSurfaceVariant),
            onPressed: () async {
              if (!await guardPast(context, dayKeyStr)) return;
              if (context.mounted) await showEditEntrySheet(context, db, entry);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Удалить',
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
