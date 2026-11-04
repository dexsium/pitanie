import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/dates.dart';
import '../../core/labels.dart';
import '../../core/nutrition.dart';
import '../../database/database.dart';
import '../../shared/widgets.dart';
import '../calendar/calendar_page.dart';
import '../health_integration/devices_page.dart';
import '../recipes/recipes_page.dart';
import '../settings/settings_page.dart';
import '../water/water_page.dart';
import '../scale/scale_controller.dart';
import '../wearables/wearable_controller.dart';
import '../weight/weight_page.dart';
import 'onboarding_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(userProvider).valueOrNull;
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final key = dayKey(DateTime.now());
    final goal = ref.watch(dayDataProvider(key)).valueOrNull?.goal ?? GoalValues.fallback;
    final cs = Theme.of(context).colorScheme;
    final db = ref.read(dbProvider);
    final src = ref.watch(sourceProvider).valueOrNull;
    final busy = ref.watch(syncBusyProvider);
    final watch = ref.watch(wearableProvider);
    final scale = ref.watch(scaleProvider);

    double? bmr;
    double? tdee;
    if (u != null && u.birthDate != null && u.heightCm != null && ws.isNotEmpty) {
      bmr = bmrMifflin(
          sex: u.sex == 'female' ? Sex.female : Sex.male,
          weightKg: ws.last.weightKg,
          heightCm: u.heightCm!,
          age: ageOn(u.birthDate!, DateTime.now()));
      final lvl = ActivityLevel.values.firstWhere((l) => l.name == u.activityLevel, orElse: () => ActivityLevel.light);
      tdee = bmr * activityFactor[lvl]!;
    }

    Widget nav(IconData i, String t, Widget page) => ListTile(
          leading: Icon(i),
          title: Text(t),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      const Text('Профиль', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (u != null)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle('Анкета',
                icon: Icons.person_outline,
                trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const OnboardingPage(editing: true))))),
            const SizedBox(height: 4),
            Text(
                '${u.sex == 'female' ? 'Женский' : 'Мужской'}'
                '${u.birthDate == null ? '' : ', ${ageOn(u.birthDate!, DateTime.now())} лет'}'
                '${u.heightCm == null ? '' : ', ${fmtAuto(u.heightCm!)} см'}'
                '${ws.isEmpty ? '' : ', ${fmt1(ws.last.weightKg)} кг'}'),
            Text('Цель: ${goalLabel(GoalType.values.firstWhere((g) => g.name == u.goalType, orElse: () => GoalType.maintain))}',
                style: TextStyle(color: cs.onSurfaceVariant)),
            if (bmr != null) ...[
              const Divider(height: 24),
              Text('Базовый обмен: ≈ ${fmt0(bmr)} ккал'),
              Text('Суточная потребность: ≈ ${fmt0(tdee!)} ккал'),
              Text('Это оценка по формуле Миффлина — Сан Жеора, не медицинская рекомендация.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      const SizedBox(height: 14),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle('Суточные нормы', icon: Icons.flag_outlined),
          const SizedBox(height: 8),
          Text('${fmt0(goal.calories)} ккал · Б ${fmt0(goal.proteins)} · Ж ${fmt0(goal.fats)} · У ${fmt0(goal.carbs)} г'),
          Text('Вода: ${fmt0(goal.waterMl)} мл'),
          const SizedBox(height: 4),
          Text('Изменение действует с сегодняшнего дня, история не пересчитывается.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: () => _editGoals(context, db, goal),
                  child: const Text('Изменить')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                  onPressed: u == null || bmr == null
                      ? null
                      : () async {
                          final lvl = ActivityLevel.values.firstWhere((l) => l.name == u.activityLevel);
                          final g = suggestGoals(
                              bmr: bmr!,
                              level: lvl,
                              goal: GoalType.values.firstWhere((x) => x.name == u.goalType),
                              weightKg: ws.last.weightKg);
                          final ok = await confirmDialog(
                              context,
                              'Пересчитать нормы?',
                              'Ориентировочно: ${fmt0(g.calories)} ккал, Б ${fmt0(g.proteins)}, '
                                  'Ж ${fmt0(g.fats)}, У ${fmt0(g.carbs)} г, вода ${fmt0(g.waterMl)} мл.\n'
                                  'Текущие значения будут заменены.',
                              ok: 'Применить');
                          if (ok) await db.setGoal(dayKey(DateTime.now()), g);
                        },
                  child: const Text('Пересчитать')),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      AppCard(
        child: Row(children: [
          Icon(watch.isConnected || src != null ? Icons.watch : Icons.watch_off_outlined,
              color: kPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Умные часы', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(
                switch (watch.status) {
                  WearStatus.ready => 'Bluetooth: подключено, данные идут',
                  WearStatus.connected || WearStatus.authorizing => 'Bluetooth: авторизация…',
                  WearStatus.connecting => 'Bluetooth: подключаем…',
                  WearStatus.off => watch.savedId == null
                      ? 'Часы не подключены'
                      : 'Bluetooth: нет связи',
                },
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              if (src != null)
                Text(
                  '${src.deviceName.isEmpty ? 'Система здоровья' : src.deviceName} · ${statusLabel(src.syncStatus)}'
                  '${src.lastSync == null ? '' : ', синхронизация ${fmtTime(src.lastSync!)}'
                      '${isSameDay(src.lastSync!, DateTime.now()) ? '' : ', ${shortDate(src.lastSync!)}'}'}',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
            ]),
          ),
          if (src != null)
            IconButton(
              tooltip: 'Синхронизировать',
              onPressed: busy
                  ? null
                  : () async {
                      ref.read(syncBusyProvider.notifier).state = true;
                      final r = await ref.read(healthServiceProvider).sync();
                      ref.read(syncBusyProvider.notifier).state = false;
                      if (context.mounted) toast(context, syncMessage(r));
                    },
              icon: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.monitor_weight_outlined, color: kPrimary),
            title: const Text('Умные весы Mi', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              scale.lastKg == null
                  ? 'Mi Body Composition Scale 2. Откройте приложение и встаньте на весы: вес сохранится сам.'
                  : 'Последнее: ${fmt1(scale.lastKg!)} кг, ${fmtTime(scale.lastAt!)}'
                      '${isSameDay(scale.lastAt!, DateTime.now()) ? '' : ', ${shortDate(scale.lastAt!)}'}',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            value: scale.enabled,
            onChanged: (v) => ref.read(scaleProvider).setEnabled(v),
          ),
          Text(
              'Приём по Bluetooth работает, пока приложение открыто. Сохраняется только вес; '
              'состав тела не рассчитывается.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          if (scale.log.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(scale.log.first,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ),
        ]),
      ),
      const SizedBox(height: 14),
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          nav(Icons.monitor_weight_outlined, 'Вес', const WeightPage()),
          nav(Icons.water_drop_outlined, 'Вода', const WaterPage()),
          nav(Icons.calendar_month_outlined, 'Календарь питания', const CalendarPage()),
          nav(Icons.menu_book_outlined, 'Мои блюда', const RecipesPage()),
          nav(Icons.watch_outlined, 'Умные часы и устройства', const DevicesPage()),
          nav(Icons.settings_outlined, 'Настройки', const SettingsPage()),
        ]),
      ),
    ]);
  }

  Future<void> _editGoals(BuildContext context, AppDatabase db, GoalValues g) async {
    final k = TextEditingController(text: fmtInput(g.calories));
    final p = TextEditingController(text: fmtInput(g.proteins));
    final f = TextEditingController(text: fmtInput(g.fats));
    final c = TextEditingController(text: fmtInput(g.carbs));
    final w = TextEditingController(text: fmtInput(g.waterMl));
    final form = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Суточные нормы'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              NumField(controller: k, label: 'Калории', suffix: 'ккал', min: 500, max: 10000, allowZero: false),
              const SizedBox(height: 8),
              NumField(controller: p, label: 'Белки', suffix: 'г', max: 1000),
              const SizedBox(height: 8),
              NumField(controller: f, label: 'Жиры', suffix: 'г', max: 1000),
              const SizedBox(height: 8),
              NumField(controller: c, label: 'Углеводы', suffix: 'г', max: 2000),
              const SizedBox(height: 8),
              NumField(controller: w, label: 'Вода', suffix: 'мл', min: 200, max: 10000, allowZero: false),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              await db.setGoal(
                  dayKey(DateTime.now()),
                  GoalValues(parseNum(k.text)!, parseNum(p.text)!, parseNum(f.text)!,
                      parseNum(c.text)!, parseNum(w.text)!));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
