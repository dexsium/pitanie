import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../nutrition/add_food_page.dart';
import '../nutrition/diary_actions.dart';

class RecipesPage extends ConsumerWidget {
  const RecipesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои блюда')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const RecipeEditorPage())),
        icon: const Icon(Icons.add),
        label: const Text('Новое блюдо'),
      ),
      body: StreamBuilder<List<Recipe>>(
        stream: db.watchRecipes(),
        builder: (context, snap) {
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const EmptyHint('Здесь будут ваши блюда из нескольких ингредиентов.');
          }
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            for (final r in list)
              FutureBuilder<RecipeResult>(
                future: db.recipeResult(r.id),
                builder: (context, s) {
                  final res = s.data;
                  return ListTile(
                    leading: IconButton(
                      icon: Icon(r.isFavorite ? Icons.star : Icons.star_border,
                          color: r.isFavorite ? Colors.amber : null),
                      onPressed: () => db.setRecipeFavorite(r.id, !r.isFavorite),
                    ),
                    title: Text(r.name),
                    subtitle: res == null
                        ? null
                        : Text('${fmt0(res.perServing.calories)} ккал / порция · '
                            '${fmt0(res.per100.calories)} ккал / 100 г · ${fmt0(res.finalWeight)} г'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => RecipeEditorPage(recipe: r))),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'add') {
                          final day = dayKey(ref.read(selectedDayProvider));
                          if (!await guardPast(context, day)) return;
                          final ok = await showRecipeAddDialog(context, db, r, day, mealForNow());
                          if (ok && context.mounted) toast(context, 'Добавлено в дневник');
                        } else if (v == 'copy') {
                          await db.copyRecipe(r.id);
                        } else if (v == 'delete') {
                          if (await confirmDialog(context, 'Удалить блюдо?',
                              'Записи дневника сохранятся.', ok: 'Удалить')) {
                            await db.deleteRecipe(r.id);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'add', child: Text('Добавить в дневник')),
                        PopupMenuItem(value: 'copy', child: Text('Копировать')),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                  );
                },
              ),
          ]);
        },
      ),
    );
  }
}

class _Ing {
  final Product product;
  double qty;
  _Ing(this.product, this.qty);
}

class RecipeEditorPage extends ConsumerStatefulWidget {
  final Recipe? recipe;
  const RecipeEditorPage({super.key, this.recipe});
  @override
  ConsumerState<RecipeEditorPage> createState() => _EditorState();
}

class _EditorState extends ConsumerState<RecipeEditorPage> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.recipe?.name ?? '');
  late final servings = TextEditingController(text: '${widget.recipe?.servings ?? 1}');
  late final cooked = TextEditingController(
      text: widget.recipe?.cookedWeight == null ? '' : fmtAuto(widget.recipe!.cookedWeight!));
  final _ings = <_Ing>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.recipe == null) {
      _loaded = true;
    } else {
      ref.read(dbProvider).ingredientsOf(widget.recipe!.id).then((l) {
        if (!mounted) return;
        setState(() {
          _ings.addAll(l.map((e) => _Ing(e.$2, e.$1.quantity)));
          _loaded = true;
        });
      });
    }
  }

  RecipeResult get _result => calcRecipe(
        _ings.map((i) => RecipeLine(productPer100(i.product), i.qty)).toList(),
        cookedWeight: parseNum(cooked.text),
        servings: int.tryParse(servings.text) ?? 1,
      );

  Future<void> _addIngredient() async {
    final p = await Navigator.push<Product>(
        context,
        MaterialPageRoute(
            builder: (_) => AddFoodPage(day: dayKey(DateTime.now()), meal: Meal.lunch, pickProduct: true)));
    if (p == null || !mounted) return;
    final q = await promptNumber(context, p.name,
        initial: 100, suffix: p.measurementUnit == 'ml' ? 'мл' : 'г', allowZero: false, max: 50000);
    if (q != null) setState(() => _ings.add(_Ing(p, q)));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_ings.isEmpty) {
      toast(context, 'Добавьте хотя бы один ингредиент');
      return;
    }
    await ref.read(dbProvider).saveRecipe(
          id: widget.recipe?.id,
          name: name.text.trim(),
          cookedWeight: parseNum(cooked.text),
          servings: int.parse(servings.text),
          isFavorite: widget.recipe?.isFavorite ?? false,
          ingredients: _ings.map((i) => (productId: i.product.id, quantity: i.qty)).toList(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipe == null ? 'Новое блюдо' : 'Блюдо')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Название'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: servings,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Порций'),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n < 1 || n > 100) ? '1–100' : null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: cooked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Масса готового', suffixText: 'г', helperText: 'необязательно'),
                      validator: numValidator(required: false, allowZero: false, max: 100000),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                const SectionTitle('Ингредиенты'),
                for (var i = 0; i < _ings.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_ings[i].product.name),
                    subtitle: Text(
                        '${fmtAuto(_ings[i].qty)} ${_ings[i].product.measurementUnit == 'ml' ? 'мл' : 'г'}'
                        ' · ${fmt0(nutrientsForAmount(productPer100(_ings[i].product), _ings[i].qty).calories)} ккал'),
                    onTap: () async {
                      final q = await promptNumber(context, _ings[i].product.name,
                          initial: _ings[i].qty, allowZero: false, max: 50000);
                      if (q != null) setState(() => _ings[i].qty = q);
                    },
                    trailing: IconButton(
                        icon: const Icon(Icons.close), onPressed: () => setState(() => _ings.removeAt(i))),
                  ),
                TextButton.icon(
                    onPressed: _addIngredient,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить ингредиент')),
                const SizedBox(height: 8),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Расчёт', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    _line('Масса ингредиентов', '${fmt0(r.rawWeight)} г'),
                    _line('Масса блюда', '${fmt0(r.finalWeight)} г'),
                    _line('Всего', _nut(r.total)),
                    _line('На 100 г', _nut(r.per100)),
                    _line('Порция (${fmt0(r.servingWeight)} г)', _nut(r.perServing)),
                    if (parseNum(cooked.text) != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                            'Общая калорийность берётся из ингредиентов и не меняется от массы готового блюда.',
                            style: TextStyle(fontSize: 12)),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _save, child: const Text('Сохранить')),
              ]),
            ),
    );
  }

  String _nut(Nutrients n) =>
      '${fmt0(n.calories)} ккал · Б ${fmt1(n.proteins)} Ж ${fmt1(n.fats)} У ${fmt1(n.carbs)}';

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Text(a)),
          Expanded(flex: 6, child: Text(b, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
