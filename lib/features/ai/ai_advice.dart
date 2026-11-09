// Совет ИИ в карточке «Чем добрать норму»: что съесть, чтобы закрыть остаток калорий, белка
// и углеводов. Показывается только если помощник включён и ключ сохранён.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/nutrition.dart';
import '../../shared/widgets.dart';
import '../coach/goal_service.dart';
import '../dashboard/day_data.dart';
import 'ai_photo_page.dart';
import 'gemini_service.dart';

class AiAdvice extends ConsumerStatefulWidget {
  final DayData d;
  final Nutrients remaining;
  final Color accent;
  const AiAdvice({super.key, required this.d, required this.remaining, required this.accent});

  @override
  ConsumerState<AiAdvice> createState() => _AiAdviceState();
}

class _AiAdviceState extends ConsumerState<AiAdvice> {
  bool _busy = false;
  String? _error, _comment;
  List<AiFoodItem>? _items;
  final _wish = TextEditingController();

  @override
  void dispose() {
    _wish.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final db = ref.read(dbProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = await loadGeminiClient(db);
      if (client == null) {
        throw const AiException('ИИ выключен или не указан ключ (Настройки → Умный помощник).');
      }
      final mine = await loadCandidates(db);
      final r = await client.suggestMeals(
        remaining: widget.remaining,
        goal: widget.d.goal,
        mine: [for (final m in mine) (name: m.name, per100: m.per100)],
        eatenToday: [for (final e in widget.d.food) e.name],
        wish: _wish.text,
      );
      if (!mounted) return;
      setState(() {
        _items = r.items;
        _comment = r.comment;
      });
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось получить совет. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<AiFoodItem> items) async {
    await addAiItems(ref.read(dbProvider),
        day: widget.d.key, meal: mealByHour(DateTime.now()), items: items);
    if (mounted) toast(context, 'Добавлено в дневник');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? {};
    if (settings[kAiEnabledKey] != '1') return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final items = _items;
    final r = widget.remaining;
    final total = items == null
        ? Nutrients.zero
        : items.fold<Nutrients>(Nutrients.zero, (a, b) => a + b.total);
    String g(double v) => v.round().toString();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: widget.accent),
          const SizedBox(width: 6),
          const Text('Совет ИИ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _wish,
          decoration: const InputDecoration(
              isDense: true,
              hintText: 'Пожелание (необязательно): без молочного, что-то лёгкое…'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _ask,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: Text(items == null ? 'Спросить ИИ, чем добрать' : 'Спросить ещё раз'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: cs.error)),
          ),
        if (items != null && items.isEmpty && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('ИИ не предложил ничего подходящего.', style: TextStyle(color: muted)),
          ),
        if (items != null && items.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${i.name} · ${fmtGrams(i.grams)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        '${g(i.kcal)} ккал · Б ${g(i.proteins)} · Ж ${g(i.fats)} · У ${g(i.carbs)}',
                        style: TextStyle(fontSize: 12.5, color: muted)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Добавить в дневник',
                  onPressed: () => _add([i]),
                  icon: Icon(Icons.add_circle_outline, color: widget.accent),
                ),
              ]),
            ),
          Text(
              'Вместе: ${g(total.calories)} из ${g(r.calories)} ккал · белка ${g(total.proteins)} '
              'из ${g(r.proteins)} г · углеводов ${g(total.carbs)} из ${g(r.carbs)} г',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          if (_comment != null && _comment!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_comment!, style: TextStyle(fontSize: 12.5, color: muted)),
            ),
          const SizedBox(height: 6),
          OutlinedButton(onPressed: () => _add(items), child: const Text('Добавить всё в дневник')),
        ],
        const SizedBox(height: 6),
        Text('Оценка ИИ приблизительная. Сверяйтесь с реальными продуктами.',
            style: TextStyle(fontSize: 11.5, color: muted)),
      ]),
    );
  }
}
