import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';

/// Стандартные обхваты. Остальные названия пользователь задаёт сам.
const kBodyKinds = <String, String>{
  'waist': 'Талия',
  'chest': 'Грудь',
  'hips': 'Бёдра (ягодицы)',
  'arm': 'Рука',
  'thigh': 'Бедро',
};

String kindLabel(String k) => kBodyKinds[k] ?? k;

/// Изменение между первым и последним значением за период [days] (0 — за всё время).
/// null, если в периоде меньше двух замеров. Считается по данным, ничего не предполагается.
double? measureChange(List<BodyMeasurement> list, int days, DateTime now) {
  final from = days == 0 ? null : now.subtract(Duration(days: days));
  final inRange = [
    for (final m in list)
      if (from == null || !m.measuredAt.isBefore(from)) m
  ]..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  if (inRange.length < 2) return null;
  return inRange.last.valueCm - inRange.first.valueCm;
}

/// Каталог закрытых фото прогресса внутри папки приложения.
Future<Directory> photosDir() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'progress_photos')).create(recursive: true);
}

Future<void> deletePhotoFiles(Iterable<String> names) async {
  try {
    final d = await photosDir();
    for (final n in names) {
      final f = File(p.join(d.path, n));
      if (f.existsSync()) f.deleteSync();
    }
  } catch (_) {}
}

class MeasurementsPage extends ConsumerWidget {
  const MeasurementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Измерения тела'),
          bottom: const TabBar(tabs: [Tab(text: 'Обхваты'), Tab(text: 'Фото прогресса')]),
        ),
        body: const TabBarView(children: [_GirthTab(), _PhotoTab()]),
      ),
    );
  }
}

class _GirthTab extends ConsumerWidget {
  const _GirthTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<BodyMeasurement>>(
      stream: db.watchBodyMeasures(),
      builder: (context, snap) {
        final all = snap.data ?? const <BodyMeasurement>[];
        final byKind = <String, List<BodyMeasurement>>{};
        for (final m in all) {
          byKind.putIfAbsent(m.kind, () => []).add(m);
        }
        final kinds = [
          ...kBodyKinds.keys,
          ...byKind.keys.where((k) => !kBodyKinds.containsKey(k)),
        ];
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addDialog(context, db, byKind.keys.toList()),
            icon: const Icon(Icons.add),
            label: const Text('Замер'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            for (final k in kinds)
              Builder(builder: (context) {
                final list = byKind[k] ?? const <BodyMeasurement>[];
                final last = list.isEmpty ? null : list.last;
                final d30 = measureChange(list, 30, DateTime.now());
                return AppCard(
                  onTap: list.isEmpty
                      ? () => _addDialog(context, db, byKind.keys.toList(), kind: k)
                      : () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => _KindPage(kind: k))),
                  child: Row(children: [
                    const Icon(Icons.straighten, color: kPrimary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(kindLabel(k),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                            last == null
                                ? 'Нет замеров'
                                : '${shortDate(last.measuredAt)} · ${list.length} замер.',
                            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(last == null ? '—' : '${fmtAuto(last.valueCm)} см',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      if (d30 != null)
                        Text('${d30 > 0 ? '+' : ''}${fmtAuto(double.parse(d30.toStringAsFixed(1)))} см за 30 дн.',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
                  ]),
                );
              }),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Измеряйте в одно и то же время и в одном положении. Изменения за короткий срок '
                  'могут быть связаны с водой и пищей в организме, а не с жиром.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ),
          ]),
        );
      },
    );
  }
}

Future<void> _addDialog(BuildContext context, AppDatabase db, List<String> existing,
    {String? kind}) async {
  var sel = kind ?? 'waist';
  var custom = !kBodyKinds.containsKey(sel);
  final name = TextEditingController(text: custom ? sel : '');
  final value = TextEditingController();
  var date = DateTime.now();
  final form = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Новый замер'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: custom ? '_custom' : sel,
                isExpanded: true,
                items: [
                  for (final e in kBodyKinds.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                  for (final k in existing.where((k) => !kBodyKinds.containsKey(k)))
                    DropdownMenuItem(value: k, child: Text(k)),
                  const DropdownMenuItem(value: '_custom', child: Text('Другое…')),
                ],
                onChanged: (v) => setState(() {
                  custom = v == '_custom';
                  if (v != null && !custom) sel = v;
                }),
              ),
              if (custom) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Название замера'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Введите название' : null,
                ),
              ],
              const SizedBox(height: 10),
              NumField(controller: value, label: 'Значение', suffix: 'см', min: 5, max: 300, allowZero: false),
              const SizedBox(height: 6),
              TextButton.icon(
                icon: const Icon(Icons.event),
                label: Text(shortDate(date)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (d != null) setState(() => date = d);
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final k = custom ? name.text.trim() : sel;
              final now = DateTime.now();
              final at = isSameDay(date, now)
                  ? now
                  : DateTime(date.year, date.month, date.day, 12);
              await db.addBodyMeasure(k, parseNum(value.text)!, at);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
}

class _KindPage extends ConsumerStatefulWidget {
  final String kind;
  const _KindPage({required this.kind});

  @override
  ConsumerState<_KindPage> createState() => _KindPageState();
}

class _KindPageState extends ConsumerState<_KindPage> {
  int _days = 30; // 0 — всё время

  @override
  Widget build(BuildContext context) {
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(kindLabel(widget.kind))),
      body: StreamBuilder<List<BodyMeasurement>>(
        stream: db.watchBodyMeasures(),
        builder: (context, snap) {
          final list = [
            for (final m in snap.data ?? const <BodyMeasurement>[])
              if (m.kind == widget.kind) m
          ];
          final now = DateTime.now();
          final from = _days == 0 ? null : now.subtract(Duration(days: _days));
          final shown = [
            for (final m in list)
              if (from == null || !m.measuredAt.isBefore(from)) m
          ];
          final change = measureChange(list, _days, now);
          final spots = [
            for (var i = 0; i < shown.length; i++) FlSpot(i.toDouble(), shown[i].valueCm)
          ];
          return ListView(padding: const EdgeInsets.all(16), children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 30, label: Text('30 дн.')),
                ButtonSegment(value: 90, label: Text('90 дн.')),
                ButtonSegment(value: 0, label: Text('Всё время')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    change == null
                        ? 'Для сравнения нужно хотя бы два замера за период'
                        : 'Изменение за период: ${change > 0 ? '+' : ''}${fmtAuto(double.parse(change.toStringAsFixed(1)))} см',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: spots.length < 2
                      ? Center(
                          child: Text('Мало данных для графика',
                              style: TextStyle(color: cs.onSurfaceVariant)))
                      : LineChart(LineChartData(
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          titlesData: const FlTitlesData(
                              topTitles: AxisTitles(),
                              rightTitles: AxisTitles(),
                              bottomTitles: AxisTitles()),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                                spots: spots,
                                isCurved: false,
                                color: kPrimary,
                                barWidth: 3,
                                dotData: const FlDotData(show: true)),
                          ],
                        )),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            for (final m in list.reversed)
              AppCard(
                child: Row(children: [
                  Expanded(
                      child: Text('${shortDate(m.measuredAt)}  ${fmtTime(m.measuredAt)}',
                          style: TextStyle(color: cs.onSurfaceVariant))),
                  Text('${fmtAuto(m.valueCm)} см',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      if (await confirmDialog(context, 'Удалить замер?', 'Это действие нельзя отменить.',
                          ok: 'Удалить')) {
                        await db.deleteBodyMeasure(m.id);
                      }
                    },
                  ),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class _PhotoTab extends ConsumerWidget {
  const _PhotoTab();

  Future<void> _add(BuildContext context, WidgetRef ref, ImageSource src) async {
    final db = ref.read(dbProvider);
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 88);
      if (x == null) return;
      final dir = await photosDir();
      final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(x.path).copy(p.join(dir.path, name));
      await db.addProgressPhoto(name, DateTime.now());
    } catch (_) {
      if (context.mounted) {
        toast(context, 'Не удалось получить фото. Проверьте разрешения камеры и фото.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<ProgressPhoto>>(
      stream: db.watchProgressPhotos(),
      builder: (context, snap) {
        final list = snap.data ?? const <ProgressPhoto>[];
        return FutureBuilder<Directory>(
          future: photosDir(),
          builder: (context, ds) {
            final dir = ds.data;
            return ListView(padding: const EdgeInsets.all(16), children: [
              AppCard(
                child: Text(
                    'Фото хранятся только на этом устройстве в закрытой папке приложения, не '
                    'отправляются никуда и не входят в резервную копию. Их можно удалить в любой момент.',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _add(context, ref, ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Снять')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _add(context, ref, ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Из галереи')),
                ),
              ]),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyHint('Фото прогресса пока нет.')
              else
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.75,
                  children: [
                    for (final ph in list)
                      GestureDetector(
                        onTap: dir == null
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => PhotoViewerPage(photo: ph, dirPath: dir.path))),
                        child: Stack(fit: StackFit.expand, children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: dir == null
                                ? const SizedBox()
                                : _PhotoImage(path: p.join(dir.path, ph.fileName)),
                          ),
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                              child: Text(shortDate(ph.takenAt),
                                  style: const TextStyle(color: Colors.white, fontSize: 11)),
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
            ]);
          },
        );
      },
    );
  }
}

class _PhotoImage extends StatelessWidget {
  final String path;
  const _PhotoImage({required this.path});

  @override
  Widget build(BuildContext context) => Image.file(File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.image_not_supported_outlined)));
}

/// Просмотр фото, удаление и сравнение с другим фото.
class PhotoViewerPage extends ConsumerWidget {
  final ProgressPhoto photo;
  final String dirPath;
  const PhotoViewerPage({super.key, required this.photo, required this.dirPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    return Scaffold(
      appBar: AppBar(title: Text('${shortDate(photo.takenAt)} ${fmtTime(photo.takenAt)}'), actions: [
        IconButton(
          tooltip: 'Сравнить с другим фото',
          icon: const Icon(Icons.compare),
          onPressed: () async {
            final all = (await db.allProgressPhotos()).where((x) => x.id != photo.id).toList()
              ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
            if (!context.mounted) return;
            if (all.isEmpty) {
              toast(context, 'Для сравнения нужно хотя бы два фото');
              return;
            }
            final other = await showModalBottomSheet<ProgressPhoto>(
              context: context,
              builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Сравнить с…',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  for (final o in all)
                    ListTile(
                      leading: SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _PhotoImage(path: p.join(dirPath, o.fileName)))),
                      title: Text('${shortDate(o.takenAt)} ${fmtTime(o.takenAt)}'),
                      onTap: () => Navigator.pop(ctx, o),
                    ),
                ]),
              ),
            );
            if (other == null || !context.mounted) return;
            final pair = [photo, other]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Сравнение')),
                          body: Row(children: [
                            for (final x in pair)
                              Expanded(
                                child: Column(children: [
                                  Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(shortDate(x.takenAt),
                                          style: const TextStyle(fontWeight: FontWeight.w800))),
                                  Expanded(
                                      child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Image.file(File(p.join(dirPath, x.fileName)),
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.image_not_supported_outlined)),
                                  )),
                                ]),
                              ),
                          ]),
                        )));
          },
        ),
        IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (!await confirmDialog(context, 'Удалить фото?',
                'Фото будет безвозвратно удалено с устройства.',
                ok: 'Удалить')) {
              return;
            }
            final name = await db.deleteProgressPhoto(photo.id);
            if (name != null) await deletePhotoFiles([name]);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      body: InteractiveViewer(
        child: Center(
          child: Image.file(File(p.join(dirPath, photo.fileName)),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('Файл фото не найден')),
        ),
      ),
    );
  }
}
