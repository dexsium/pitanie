import 'package:flutter/material.dart';

import '../../core/labels.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

/// Сохранение приёма пищи как шаблона.
Future<void> saveMealAsTemplate(
    BuildContext context, AppDatabase db, String day, Meal meal) async {
  final ctl = TextEditingController(text: meal.label);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Сохранить как шаблон'),
      content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название шаблона')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Сохранить')),
      ],
    ),
  );
  if (name == null) return;
  final id = await db.saveMealTemplate(day, meal.name, name);
  if (context.mounted) {
    toast(context, id == null ? 'В этом приёме пищи нет записей' : 'Шаблон сохранён');
  }
}

/// Список шаблонов: нажатие добавляет позиции в приём пищи, значок справа удаляет шаблон.
Future<void> showMealTemplatePicker(
    BuildContext context, AppDatabase db, String day, Meal meal) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StreamBuilder<List<MealTemplate>>(
      stream: db.watchMealTemplates(),
      builder: (ctx, snap) {
        final list = snap.data ?? const <MealTemplate>[];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Шаблоны: ${meal.label}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Text(
                      'Шаблонов пока нет. Откройте меню приёма пищи и выберите «Сохранить как шаблон».',
                      textAlign: TextAlign.center),
                ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final t in list)
                    ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(t.name),
                      trailing: IconButton(
                        tooltip: 'Удалить шаблон',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDialog(ctx, 'Удалить шаблон?',
                              'Записи дневника не изменятся.',
                              ok: 'Удалить')) {
                            await db.deleteMealTemplate(t.id);
                          }
                        },
                      ),
                      onTap: () async {
                        final n = await db.applyMealTemplate(t.id, day, meal.name);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) toast(context, 'Добавлено записей: $n');
                      },
                    ),
                ]),
              ),
            ]),
          ),
        );
      },
    ),
  );
}
