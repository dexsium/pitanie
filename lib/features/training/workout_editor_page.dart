import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import 'strength_math.dart';
import 'training_repo.dart';

class _EditSet {
  final reps = TextEditingController();
  final weight = TextEditingController();
  final rest = TextEditingController();
  void dispose() {
    reps.dispose();
    weight.dispose();
    rest.dispose();
  }
}

class _EditEx {
  final LiftExercise ex;
  final List<_EditSet> sets = [];
  String last = '';
  _EditEx(this.ex);
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Создание и правка тренировки: упражнения, подходы, повторения, вес, отдых.
class WorkoutEditorPage extends ConsumerStatefulWidget {
  final int? sessionId;
  final List<int>? templateIds;
  final String? title;
  const WorkoutEditorPage(
      {super.key, this.sessionId, this.templateIds, this.title});
  @override
  ConsumerState<WorkoutEditorPage> createState() => _WorkoutEditorPageState();
}

class _WorkoutEditorPageState extends ConsumerState<WorkoutEditorPage> {
  late final TrainingRepo repo = TrainingRepo(ref.read(dbProvider));
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _duration = TextEditingController();
  final _items = <_EditEx>[];
  DateTime _started = DateTime.now();
  final _opened = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  List<LiftExercise> _all = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _all = await repo.exercises();
    final byId = {for (final e in _all) e.id: e};
    if (widget.sessionId != null) {
      final sessions = await repo.history(limit: 1000);
      final s =
          sessions.firstWhere((x) => x.session.id == widget.sessionId).session;
      _title.text = s.title;
      _note.text = s.note;
      _duration.text = s.durationMin?.toString() ?? '';
      _started = s.startedAt.toLocal();
      final sets = await repo.setsOf(s.id);
      for (final x in sets) {
        final ex = byId[x.exerciseId];
        if (ex == null) continue;
        var item = _items.where((i) => i.ex.id == ex.id).firstOrNull;
        if (item == null) {
          item = _EditEx(ex);
          _items.add(item);
        }
        item.sets.add(_EditSet()
          ..reps.text = '${x.reps}'
          ..weight.text = x.weightKg == null ? '' : fmtAuto(x.weightKg!)
          ..rest.text = x.restSec?.toString() ?? '');
      }
    } else {
      _title.text = widget.title ?? '';
      for (final id in widget.templateIds ?? const <int>[]) {
        final ex = byId[id];
        if (ex != null) await _addExercise(ex);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addExercise(LiftExercise ex) async {
    final item = _EditEx(ex);
    final last = await repo.lastSets(ex.id, exceptSessionId: widget.sessionId);
    if (last.isNotEmpty) {
      item.last =
          'В прошлый раз: ${last.map((s) => s.weightKg != null && s.weightKg! > 0 ? '${s.reps}×${fmtAuto(s.weightKg!)}' : '${s.reps}').join(', ')}';
    }
    item.sets.add(_EditSet());
    _items.add(item);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _duration.dispose();
    for (final i in _items) {
      for (final s in i.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final used = _items.map((i) => i.ex.id).toSet();
    final chosen = await showModalBottomSheet<LiftExercise>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ExercisePicker(
            all: _all.where((e) => !used.contains(e.id)).toList(),
            onCreate: (name, kind) async {
              final id = await repo.addExercise(name, kind);
              _all = await repo.exercises();
              return _all.firstWhere((e) => e.id == id);
            }));
    if (chosen != null) {
      await _addExercise(chosen);
      if (mounted) setState(() {});
    }
  }

  List<EditExerciseData> _collect() {
    final out = <EditExerciseData>[];
    for (final i in _items) {
      final sets = <EditSetData>[];
      for (final s in i.sets) {
        final reps = int.tryParse(s.reps.text.trim());
        if (reps == null || reps <= 0) continue; // пустые подходы не сохраняем
        final w = _num(s.weight.text);
        sets.add(EditSetData(reps, (w == null || w <= 0) ? null : w,
            int.tryParse(s.rest.text.trim())));
      }
      if (sets.isNotEmpty) out.add(EditExerciseData(i.ex.id, sets));
    }
    return out;
  }

  Future<void> _save() async {
    final data = _collect();
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Добавьте хотя бы один подход с повторениями')));
      return;
    }
    setState(() => _saving = true);
    var dur = int.tryParse(_duration.text.trim());
    if (dur == null && widget.sessionId == null) {
      final m = DateTime.now().difference(_opened).inMinutes;
      dur = m > 0 ? m : null;
    }
    await repo.save(
        id: widget.sessionId,
        title: _title.text.trim(),
        startedAt: _started,
        durationMin: dur,
        note: _note.text.trim(),
        exercises: data);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveTemplate() async {
    final ids = _items.map((i) => i.ex.id).toList();
    if (ids.isEmpty) return;
    final c = TextEditingController(text: _title.text);
    final name = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Сохранить как шаблон'),
              content: TextField(
                  controller: c,
                  decoration: const InputDecoration(labelText: 'Название')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('Отмена')),
                TextButton(
                    onPressed: () => Navigator.pop(d, c.text.trim()),
                    child: const Text('Сохранить')),
              ],
            ));
    if (name != null && name.isNotEmpty) {
      await repo.saveTemplate(name, ids);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Шаблон сохранён')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.sessionId == null ? 'Новая тренировка' : 'Тренировка'),
        actions: [
          IconButton(
              tooltip: 'Сохранить как шаблон',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: _saveTemplate),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                        labelText: 'Название (необязательно)')),
                const SizedBox(height: 12),
                for (final item in _items) ...[
                  AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(item.ex.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _items.remove(item)),
                            ),
                          ]),
                          Text(
                              item.ex.kind == 'bodyweight'
                                  ? 'Собственный вес: в «Вес» укажите только дополнительное отягощение'
                                  : 'Рабочий вес, кг',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                          if (item.last.isNotEmpty)
                            Text(item.last,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          for (var i = 0; i < item.sets.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                SizedBox(
                                    width: 24,
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))),
                                Expanded(
                                    child: _field(item.sets[i].reps, 'Повт.',
                                        digits: true)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child:
                                        _field(item.sets[i].weight, 'Вес, кг')),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: _field(item.sets[i].rest, 'Отдых, с',
                                        digits: true)),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: item.sets.length <= 1
                                      ? null
                                      : () => setState(() =>
                                          item.sets.removeAt(i).dispose()),
                                ),
                              ]),
                            ),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              final n = _EditSet();
                              final prev =
                                  item.sets.isEmpty ? null : item.sets.last;
                              if (prev != null) {
                                n.weight.text =
                                    prev.weight.text; // вес обычно повторяется
                                n.rest.text = prev.rest.text;
                              }
                              item.sets.add(n);
                            }),
                            icon: const Icon(Icons.add),
                            label: const Text('Подход'),
                          ),
                          _summary(item, cs),
                        ]),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.fitness_center),
                    label: const Text('Добавить упражнение')),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child:
                          _field(_duration, 'Длительность, мин', digits: true)),
                ]),
                const SizedBox(height: 8),
                TextField(
                    controller: _note,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Комментарий')),
                const SizedBox(height: 16),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kPrimary),
                    onPressed: _saving ? null : _save,
                    child: Text(widget.sessionId == null
                        ? 'Сохранить тренировку'
                        : 'Сохранить изменения')),
              ],
            ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool digits = false}) =>
      TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: !digits),
        inputFormatters: [
          digits
              ? FilteringTextInputFormatter.digitsOnly
              : FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
        ],
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) => setState(() {}),
      );

  Widget _summary(_EditEx item, ColorScheme cs) {
    final sets = [
      for (final s in item.sets)
        if ((int.tryParse(s.reps.text.trim()) ?? 0) > 0)
          SetData(int.parse(s.reps.text.trim()), _num(s.weight.text))
    ];
    if (sets.isEmpty) return const SizedBox.shrink();
    final v = volumeKg(sets);
    final e = best1Rm(sets);
    return Text(
        'Подходов: ${sets.length}, повторений: ${totalReps(sets)}'
        '${v > 0 ? ', объём ${fmt0(v)} кг' : ''}'
        '${e != null ? ', оценка 1ПМ ≈ ${fmt0(e)} кг' : ''}',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant));
  }
}

class _ExercisePicker extends StatefulWidget {
  final List<LiftExercise> all;
  final Future<LiftExercise> Function(String name, String kind) onCreate;
  const _ExercisePicker({required this.all, required this.onCreate});
  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  String _q = '';
  String _kind = 'weight';

  @override
  Widget build(BuildContext context) {
    final list = widget.all
        .where((e) => e.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                  labelText: 'Найти или создать упражнение',
                  prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (_q.trim().isNotEmpty &&
              !widget.all
                  .any((e) => e.name.toLowerCase() == _q.trim().toLowerCase()))
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: kPrimary),
              title: Text('Создать «${_q.trim()}»'),
              subtitle: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'weight', label: Text('С весом')),
                  ButtonSegment(value: 'bodyweight', label: Text('Свой вес')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              onTap: () async {
                final e = await widget.onCreate(_q.trim(), _kind);
                if (context.mounted) Navigator.pop(context, e);
              },
            ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(list[i].name),
                subtitle: Text(list[i].kind == 'bodyweight'
                    ? 'Собственный вес'
                    : 'С отягощением'),
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
