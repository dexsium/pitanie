// «Зона пульса»: тип зон, максимальный пульс и пульс покоя, границы зон и время в зонах за сегодня.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/dates.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../dashboard/day_data.dart' show singleSource, mainSourceOf;
import 'heart_zones.dart';

const kHrZoneTypeKey = 'hr_zone_type'; // 'max' | 'reserve'
const kHrMaxKey = 'hr_max'; // ручной максимальный пульс
const kHrRestKey = 'hr_rest'; // ручной пульс покоя

const _zoneColors = [
  Color(0xFF8BC34A),
  Color(0xFFFFB300),
  Color(0xFFFB8C00),
  Color(0xFFE64A19),
  Color(0xFFC62828),
];

class HeartZonesPage extends ConsumerStatefulWidget {
  const HeartZonesPage({super.key});

  @override
  ConsumerState<HeartZonesPage> createState() => _HeartZonesPageState();
}

class _HeartZonesPageState extends ConsumerState<HeartZonesPage> {
  int? _restFromData;
  List<double> _todayHr = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final month =
        await db.activityBetween(now.subtract(const Duration(days: 30)), now);
    ActivityRecord? rest;
    for (final r in month) {
      if (r.type == 'restingHeartRate' &&
          r.value >= 30 &&
          r.value <= 120 &&
          (rest == null || r.startTime.isAfter(rest.startTime))) {
        rest = r;
      }
    }
    final today = dayStart(now);
    final recs = (await db.activityBetween(today, dayEnd(today)))
        .where((r) => r.type == 'heartRate' && r.value >= 30 && r.value <= 230)
        .toList();
    final use = singleSource(recs, preferred: mainSourceOf(await db.allSettings()));
    if (!mounted) return;
    setState(() {
      _restFromData = rest?.value.round();
      _todayHr = use.map((r) => r.value).toList();
    });
  }

  Future<int?> _askNumber(String title, int initial, int min, int max) async {
    final ctl = TextEditingController(text: '$initial');
    final r = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: TextField(
                controller: ctl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(helperText: 'От $min до $max уд/мин'),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Отмена')),
                FilledButton(
                    onPressed: () {
                      final v = int.tryParse(ctl.text);
                      Navigator.pop(ctx, v != null && v >= min && v <= max ? v : null);
                    },
                    child: const Text('Сохранить')),
              ],
            ));
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    final db = ref.read(dbProvider);
    final user = ref.watch(userProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;

    final type = s[kHrZoneTypeKey] == 'reserve' ? ZoneType.reserve : ZoneType.maxHr;
    final age = user?.birthDate == null ? null : ageOn(user!.birthDate!, DateTime.now());
    final manualMax = int.tryParse(s[kHrMaxKey] ?? '');
    final maxHr = manualMax ?? (age == null ? null : maxHeartRate(age));
    final manualRest = int.tryParse(s[kHrRestKey] ?? '');
    final rest = manualRest ?? _restFromData;

    final needRest = type == ZoneType.reserve;
    final ready = maxHr != null && (!needRest || rest != null);
    final zones = ready ? hrZones(maxHr, resting: needRest ? rest : null) : null;

    final minutes = List<int>.filled(5, 0);
    if (zones != null) {
      for (final v in _todayHr) {
        final z = zoneFor(zones, v.round());
        if (z != null) minutes[zones.indexOf(z)]++;
      }
    }

    Widget typeTile(String title, String sub, ZoneType t) => RadioListTile<ZoneType>(
          contentPadding: EdgeInsets.zero,
          value: t,
          groupValue: type,
          onChanged: (v) =>
              db.setSetting(kHrZoneTypeKey, v == ZoneType.reserve ? 'reserve' : 'max'),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: TextStyle(fontSize: 12.5, color: muted)),
        );

    Widget valueRow(String label, String value, String? hint, VoidCallback onEdit,
            {VoidCallback? onReset}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label),
              if (hint != null)
                Text(hint, style: TextStyle(fontSize: 11.5, color: muted)),
            ])),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20)),
            if (onReset != null)
              IconButton(onPressed: onReset, icon: const Icon(Icons.restart_alt, size: 20)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Зона пульса')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Тип интервала',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            typeTile(
                'Зона макс. пульса',
                'Проценты от максимального пульса. Он оценивается по формуле '
                    '(220 − возраст) и служит общим ориентиром для ежедневной интенсивности '
                    'тренировок.',
                ZoneType.maxHr),
            typeTile(
                'Зарезервированная зона пульса',
                'Пульс покоя плюс проценты от запаса (максимальный − покой), формула '
                    'Карвонена. Границы в Zepp не сверялись.',
                ZoneType.reserve),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Исходные данные',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            valueRow(
                'Максимальный пульс',
                maxHr == null ? '—' : '$maxHr',
                manualMax != null
                    ? 'задан вручную'
                    : (age == null
                        ? 'укажите дату рождения в профиле или задайте вручную'
                        : '220 − возраст ($age)'),
                () async {
              final v = await _askNumber('Максимальный пульс', maxHr ?? 185, 120, 230);
              if (v != null) await db.setSetting(kHrMaxKey, '$v');
            }, onReset: manualMax == null ? null : () => db.setSetting(kHrMaxKey, '')),
            if (needRest)
              valueRow(
                  'Пульс покоя',
                  rest == null ? '—' : '$rest',
                  manualRest != null
                      ? 'задан вручную'
                      : (_restFromData != null
                          ? 'последнее значение из данных часов'
                          : 'нет данных: задайте вручную'),
                  () async {
                final v = await _askNumber('Пульс покоя', rest ?? 60, 30, 120);
                if (v != null) await db.setSetting(kHrRestKey, '$v');
              }, onReset: manualRest == null ? null : () => db.setSetting(kHrRestKey, '')),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Зоны',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (zones == null)
              Text('Недостаточно данных для расчёта: задайте максимальный пульс'
                  '${needRest ? ' и пульс покоя' : ''}.',
                  style: TextStyle(color: muted))
            else
              for (var i = 0; i < zones.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                      color: _zoneColors[i].withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: _zoneColors[i], width: 4))),
                  child: Row(children: [
                    Expanded(
                        child: Text(zones[i].name,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('${zones[i].from}–${zones[i].to} '
                        '(${zones[i].pctFrom}%–${zones[i].pctTo}%)'),
                  ]),
                ),
          ]),
        ),
        if (zones != null) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Сегодня по зонам',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Минуты с записанным пульсом в каждой зоне.',
                  style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(height: 8),
              for (var i = 0; i < zones.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 130, child: Text(zones[i].name, style: const TextStyle(fontSize: 13))),
                    Expanded(
                        child: LinearProgressIndicator(
                            value: _todayHr.isEmpty
                                ? 0
                                : minutes[i] / _todayHr.length,
                            color: _zoneColors[i],
                            backgroundColor: _zoneColors[i].withValues(alpha: 0.12),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4))),
                    SizedBox(
                        width: 56,
                        child: Text('${minutes[i]} мин',
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 12.5))),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}
