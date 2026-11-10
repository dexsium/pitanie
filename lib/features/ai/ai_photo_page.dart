// Распознавание еды по фото: снимок → оценка ИИ → проверка и правка пользователем → дневник.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../nutrition/diary_actions.dart';
import 'ai_settings_card.dart';
import 'gemini_service.dart';

/// Открывает распознавание по фото; если ИИ не настроен, объясняет, что сделать.
Future<void> openAiPhoto(BuildContext context, AppDatabase db,
    {required String day, required Meal meal}) async {
  final client = await loadGeminiClient(db);
  if (!context.mounted) return;
  if (client == null) {
    await showAiNotConfigured(context);
    return;
  }
  await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => AiPhotoPage(day: day, meal: meal)));
}

/// Приём пищи по времени суток.
Meal mealByHour(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return Meal.breakfast;
  if (h >= 11 && h < 16) return Meal.lunch;
  if (h >= 17 && h < 22) return Meal.dinner;
  return Meal.snack;
}

String fmtGrams(double g) => '${g.round()} г';

/// Записывает позиции ИИ в дневник как ручные записи с итогом на порцию.
Future<void> addAiItems(AppDatabase db,
    {required String day, required Meal meal, required List<AiFoodItem> items}) async {
  for (final i in items) {
    await addManualEntry(db,
        day: day,
        meal: meal,
        name: '${i.name} (~${i.grams.round()} г)',
        kcal: i.kcal,
        p: i.proteins,
        f: i.fats,
        c: i.carbs);
  }
}

/// Диалог правки позиции: название и масса, состав пересчитывается пропорционально массе.
Future<AiFoodItem?> editAiItem(BuildContext context, AiFoodItem item) {
  final name = TextEditingController(text: item.name);
  final grams = TextEditingController(text: item.grams.round().toString());
  return showDialog<AiFoodItem>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Изменить позицию'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
        const SizedBox(height: 8),
        TextField(
            controller: grams,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Масса', suffixText: 'г')),
        const SizedBox(height: 8),
        const Text('Калории и БЖУ пересчитаются по новой массе.',
            style: TextStyle(fontSize: 12.5)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
          onPressed: () {
            final g = double.tryParse(grams.text.replaceAll(',', '.'));
            if (g == null || g < 1 || g > 3000) return;
            Navigator.pop(ctx, item.withGrams(g).withName(name.text.trim().isEmpty ? item.name : name.text.trim()));
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}

class AiPhotoPage extends ConsumerStatefulWidget {
  final String day;
  final Meal meal;
  const AiPhotoPage({super.key, required this.day, required this.meal});

  @override
  ConsumerState<AiPhotoPage> createState() => _AiPhotoPageState();
}

class _AiPhotoPageState extends ConsumerState<AiPhotoPage> {
  File? _file;
  bool _busy = false;
  String? _error, _comment;
  List<AiFoodItem>? _items;
  late Meal _meal = widget.meal;

  Future<void> _pick(ImageSource src) async {
    final db = ref.read(dbProvider);
    XFile? x;
    try {
      x = await ImagePicker()
          .pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 85);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось открыть камеру или галерею. Проверьте разрешения.');
      return;
    }
    if (x == null) return;
    setState(() {
      _file = File(x!.path);
      _busy = true;
      _error = null;
      _items = null;
      _comment = null;
    });
    try {
      final client = await loadGeminiClient(db);
      if (client == null) {
        throw const AiException('ИИ выключен или не указан ключ. Откройте Настройки → Умный помощник.');
      }
      final bytes = await _file!.readAsBytes();
      final mime = x.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final r = await client.recognizeFood(bytes, mime);
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _comment = r.comment;
        _busy = false;
      });
    } on AiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Не удалось обработать фото. Попробуйте ещё раз.';
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    final items = _items;
    if (items == null || items.isEmpty) return;
    await addAiItems(ref.read(dbProvider), day: widget.day, meal: _meal, items: items);
    if (!mounted) return;
    toast(context, 'Добавлено: ${items.length} поз.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total = items == null
        ? Nutrients.zero
        : items.fold<Nutrients>(Nutrients.zero, (a, b) => a + b.total);
    return Scaffold(
      appBar: AppBar(title: const Text('Еда по фото')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(_file!, height: 220, fit: BoxFit.cover),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Снять'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Из галереи'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
            'Фото отправляется в Google Gemini по вашему ключу. Вес и состав ИИ оценивает '
            'приблизительно: проверьте и поправьте граммы перед сохранением.',
            style: TextStyle(fontSize: 12.5)),
        if (_busy)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (items != null && items.isEmpty && !_busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Еда на фото не найдена. Попробуйте снять ближе и при хорошем свете.'),
          ),
        if (items != null && items.isNotEmpty && !_busy) ...[
          const SizedBox(height: 16),
          for (var i = 0; i < items.length; i++)
            AppCard(
              onTap: () async {
                final r = await editAiItem(context, items[i]);
                if (r != null) setState(() => items[i] = r);
              },
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${items[i].name} · ${fmtGrams(items[i].grams)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        '${items[i].kcal.round()} ккал · Б ${items[i].proteins.round()} · '
                        'Ж ${items[i].fats.round()} · У ${items[i].carbs.round()}',
                        style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Убрать',
                  onPressed: () => setState(() => items.removeAt(i)),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          Text(
              'Итого: ${total.calories.round()} ккал · Б ${total.proteins.round()} · '
              'Ж ${total.fats.round()} · У ${total.carbs.round()}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (_comment != null && _comment!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_comment!, style: const TextStyle(fontSize: 12.5)),
            ),
          const SizedBox(height: 12),
          SegmentedButton<Meal>(
            showSelectedIcon: false,
            segments: [for (final m in Meal.values) ButtonSegment(value: m, label: Text(m.label))],
            selected: {_meal},
            onSelectionChanged: (v) => setState(() => _meal = v.first),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Добавить в дневник'),
          ),
        ],
      ]),
    );
  }
}
