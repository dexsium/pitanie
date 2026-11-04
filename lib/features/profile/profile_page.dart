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
import '../scale/scale_controller.dart';
import '../settings/settings_page.dart';
import '../water/water_page.dart';
import '../wearables/wearable_controller.dart';
import '../weight/weight_page.dart';
import 'onboarding_page.dart';

/// Размеры экрана заданы в пикселях макета (ширина 851) и масштабируются по ширине устройства.
const _mockWidth = 851.0;

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(userProvider).valueOrNull;
    final ws = ref.watch(weightsProvider).valueOrNull ?? [];
    final key = dayKey(DateTime.now());
    final goal = ref.watch(dayDataProvider(key)).valueOrNull?.goal ?? GoalValues.fallback;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final db = ref.read(dbProvider);
    final src = ref.watch(sourceProvider).valueOrNull;
    final busy = ref.watch(syncBusyProvider);
    final watch = ref.watch(wearableProvider);
    final scale = ref.watch(scaleProvider);

    final k = MediaQuery.sizeOf(context).width / _mockWidth;
    double s(double v) => v * k;
    final card = dark ? const Color(0xFF1C1C26) : Colors.white;
    final ink = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final tint = kPrimary.withOpacity(dark ? 0.22 : 0.10);
    final rowBg = dark ? const Color(0xFF262633) : const Color(0xFFF2F1F9);

    TextStyle t(double px, {FontWeight w = FontWeight.w400, Color? c, double? h}) =>
        TextStyle(fontSize: s(px), fontWeight: w, color: c ?? ink, height: h ?? 1.2);

    final shadow = [
      BoxShadow(
          color: kPrimary.withOpacity(dark ? 0.0 : 0.07),
          blurRadius: s(30),
          offset: Offset(0, s(10)))
    ];

    Widget cardBox({required Widget child, EdgeInsets? padding, VoidCallback? onTap, Widget? decor}) =>
        Padding(
          padding: EdgeInsets.only(bottom: s(23)),
          child: Container(
            decoration:
                BoxDecoration(color: card, borderRadius: BorderRadius.circular(s(40)), boxShadow: shadow),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(s(40)),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  child: Stack(children: [
                    if (decor != null) Positioned.fill(child: decor),
                    Padding(padding: padding ?? EdgeInsets.all(s(26)), child: child),
                  ]),
                ),
              ),
            ),
          ),
        );

    Widget squareBtn(IconData i, VoidCallback onTap,
            {double size = 80, double icon = 40, Color? color}) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: s(size),
            height: s(size * 0.96),
            decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(s(24)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(dark ? 0 : 0.10),
                      blurRadius: s(18),
                      offset: Offset(0, s(6)))
                ]),
            child: Icon(i, size: s(icon), color: color ?? ink),
          ),
        );

    void info(String text) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(content: Text(text), actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))
            ]));

    double? bmr;
    double? tdee;
    if (u != null && u.birthDate != null && u.heightCm != null && ws.isNotEmpty) {
      bmr = bmrMifflin(
          sex: u.sex == 'female' ? Sex.female : Sex.male,
          weightKg: ws.last.weightKg,
          heightCm: u.heightCm!,
          age: ageOn(u.birthDate!, DateTime.now()));
      final lvl = ActivityLevel.values
          .firstWhere((l) => l.name == u.activityLevel, orElse: () => ActivityLevel.light);
      tdee = bmr * activityFactor[lvl]!;
    }

    Widget stat(IconData i, String label, String value) => Row(children: [
          Container(
              width: s(76),
              height: s(76),
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(s(22))),
              child: Icon(i, size: s(40), color: kPrimary)),
          SizedBox(width: s(16)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: t(23))),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: t(34, w: FontWeight.w800))),
            ]),
          ),
        ]);

    Widget normRow(IconData i, Color c, String label, String value) => Container(
          height: s(50),
          decoration: BoxDecoration(color: rowBg, borderRadius: BorderRadius.circular(s(25))),
          child: Row(children: [
            Container(
                width: s(65),
                decoration: BoxDecoration(
                    color: c.withOpacity(dark ? 0.25 : 0.14),
                    borderRadius: BorderRadius.circular(s(25))),
                alignment: Alignment.center,
                child: Icon(i, size: s(32), color: c)),
            SizedBox(width: s(15)),
            Expanded(child: Text(label, style: t(25))),
            Text(value, style: t(26, w: FontWeight.w700)),
            SizedBox(width: s(16)),
          ]),
        );

    Widget navCard(IconData i, String title, Widget page) => cardBox(
          padding: EdgeInsets.symmetric(horizontal: s(40), vertical: s(17)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          child: Row(children: [
            Icon(i, size: s(48), color: kPrimary),
            SizedBox(width: s(37)),
            Expanded(child: Text(title, style: t(31, w: FontWeight.w600))),
            Icon(Icons.chevron_right, size: s(40), color: muted),
          ]),
        );

    ButtonStyle outlined() => OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(s(66)),
        shape: const StadiumBorder(),
        foregroundColor: kPrimary,
        side: const BorderSide(color: kPrimary, width: 1.6),
        textStyle: t(25, w: FontWeight.w500));

    final goalType = u == null
        ? null
        : GoalType.values.firstWhere((g) => g.name == u.goalType, orElse: () => GoalType.maintain);

    return ListView(padding: EdgeInsets.fromLTRB(s(22), s(26), s(22), s(24)), children: [
      // Заголовок
      Padding(
        padding: EdgeInsets.only(left: s(22), bottom: s(34)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: s(5),
                    height: s(25),
                    decoration:
                        BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(s(3)))),
                SizedBox(width: s(15)),
                Text('Мой профиль', style: t(26, c: ink.withOpacity(0.85))),
              ]),
              SizedBox(height: s(4)),
              Text('Профиль', style: t(62, w: FontWeight.w800, h: 1.1)),
            ]),
          ),
          squareBtn(
              Icons.settings_outlined,
              () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
        ]),
      ),

      // Анкета
      if (u != null)
        cardBox(
          decor: CustomPaint(painter: _Swoosh(kPrimary.withOpacity(dark ? 0.10 : 0.06))),
          padding: EdgeInsets.fromLTRB(s(26), s(26), s(26), s(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: s(192),
                height: s(192),
                padding: EdgeInsets.all(s(5)),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: card,
                    border: Border.all(color: kPrimary, width: s(5))),
                child: ClipOval(child: Image.asset('assets/profile/avatar.png', fit: BoxFit.cover)),
              ),
              SizedBox(width: s(24)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.person_outline, size: s(40), color: kPrimary),
                    SizedBox(width: s(14)),
                    Expanded(child: Text('Анкета', style: t(34, w: FontWeight.w800))),
                    squareBtn(
                        Icons.edit_outlined,
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const OnboardingPage(editing: true))),
                        size: 67,
                        icon: 34,
                        color: kPrimary),
                  ]),
                  SizedBox(height: s(2)),
                  Text(
                      '${u.sex == 'female' ? 'Женский' : 'Мужской'}'
                      '${u.birthDate == null ? '' : ', ${ageOn(u.birthDate!, DateTime.now())} лет'}',
                      style: t(27)),
                  SizedBox(height: s(6)),
                  Text(
                      '${u.heightCm == null ? '' : '${fmtAuto(u.heightCm!)} см'}'
                      '${u.heightCm != null && ws.isNotEmpty ? '  •  ' : ''}'
                      '${ws.isEmpty ? '' : '${fmt1(ws.last.weightKg)} кг'}',
                      style: t(27)),
                  SizedBox(height: s(14)),
                  Container(
                    height: s(55),
                    padding: EdgeInsets.symmetric(horizontal: s(22)),
                    decoration:
                        BoxDecoration(color: tint, borderRadius: BorderRadius.circular(s(28))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.track_changes, size: s(34), color: kPrimary),
                      SizedBox(width: s(12)),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text.rich(TextSpan(children: [
                            TextSpan(
                                text: 'Цель: ', style: t(25, w: FontWeight.w700, c: kPrimary)),
                            TextSpan(text: goalLabel(goalType!), style: t(25)),
                          ])),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: s(10), vertical: s(20)),
              child: Divider(height: 1, color: muted.withOpacity(0.25)),
            ),
            IntrinsicHeight(
              child: Row(children: [
                SizedBox(width: s(10)),
                Expanded(
                    child: stat(Icons.local_fire_department_outlined, 'Базовый обмен',
                        bmr == null ? '—' : '${fmt0(bmr)} ккал')),
                VerticalDivider(width: s(40), color: muted.withOpacity(0.25)),
                Expanded(
                    child: stat(Icons.layers_outlined, 'Суточная потребность',
                        tdee == null ? '—' : '≈ ${fmt0(tdee)} ккал')),
              ]),
            ),
            SizedBox(height: s(18)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.info_outline, size: s(26), color: kPrimary),
              SizedBox(width: s(10)),
              Flexible(
                  child: Text('По формуле Миффлина — Сан Жеора, не медицинская рекомендация.',
                      style: t(21))),
            ]),
          ]),
        ),

      // Суточные нормы
      cardBox(
        padding: EdgeInsets.fromLTRB(s(22), s(22), s(22), s(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s(4)),
            child: Row(children: [
              Icon(Icons.flag_outlined, size: s(46), color: kPrimary),
              SizedBox(width: s(22)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Суточные нормы', style: t(32, w: FontWeight.w800)),
                  Text('Ваша цель на сутки (план потребления)', style: t(22, c: muted)),
                ]),
              ),
              GestureDetector(
                onTap: () =>
                    info('Изменение действует с сегодняшнего дня, история не пересчитывается.'),
                child: Icon(Icons.info_outline, size: s(36), color: kPrimary),
              ),
            ]),
          ),
          SizedBox(height: s(22)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: s(242),
              height: s(220),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s(36)),
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tint, kPrimary.withOpacity(dark ? 0.12 : 0.05)]),
                boxShadow: [
                  BoxShadow(
                      color: kPrimary.withOpacity(dark ? 0 : 0.10),
                      blurRadius: s(24),
                      offset: Offset(0, s(10)))
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.restaurant, size: s(52), color: kPrimary),
                SizedBox(height: s(4)),
                FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(fmt0(goal.calories), style: t(50, w: FontWeight.w800))),
                Text('ккал', style: t(26, w: FontWeight.w800)),
                Text('цель в сутки', style: t(23, c: muted)),
              ]),
              ),
            ),
            SizedBox(width: s(35)),
            Expanded(
              child: Column(children: [
                normRow(Icons.fitness_center, kPrimary, 'Белки', '${fmt0(goal.proteins)} г'),
                SizedBox(height: s(7)),
                normRow(Icons.water_drop_outlined, kOrange, 'Жиры', '${fmt0(goal.fats)} г'),
                SizedBox(height: s(7)),
                normRow(Icons.grass, kOrange, 'Углеводы', '${fmt0(goal.carbs)} г'),
                SizedBox(height: s(7)),
                normRow(Icons.water_drop_outlined, kBlue, 'Вода', '${fmt0(goal.waterMl)} мл'),
              ]),
            ),
          ]),
          SizedBox(height: s(38)),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  style: outlined(),
                  onPressed: () => _editGoals(context, db, goal),
                  child: const Text('Изменить')),
            ),
            SizedBox(width: s(24)),
            Expanded(
              child: OutlinedButton(
                  style: outlined(),
                  onPressed: u == null || bmr == null
                      ? null
                      : () async {
                          final lvl =
                              ActivityLevel.values.firstWhere((l) => l.name == u.activityLevel);
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

      // Умные часы
      cardBox(
        padding: EdgeInsets.fromLTRB(s(44), 0, s(30), 0),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesPage())),
        child: SizedBox(
          height: s(149),
          child: Row(children: [
            Image.asset('assets/profile/watch.png', height: s(148), fit: BoxFit.fitHeight),
            SizedBox(width: s(32)),
            Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Умные часы', style: t(34, w: FontWeight.w800)),
                    SizedBox(height: s(4)),
                    Text(
                      switch (watch.status) {
                        WearStatus.ready => 'Bluetooth: подключено, данные идут',
                        WearStatus.connected ||
                        WearStatus.authorizing =>
                          'Bluetooth: авторизация…',
                        WearStatus.connecting => 'Bluetooth: подключаем…',
                        WearStatus.off => watch.savedId == null
                            ? 'Часы не подключены'
                            : 'Bluetooth: нет связи',
                      },
                      style: t(23),
                    ),
                    if (src != null)
                      Text(
                        '${src.deviceName.isEmpty ? 'Система здоровья' : src.deviceName} • ${statusLabel(src.syncStatus)}'
                        '${src.lastSync == null ? '' : ', синхронизация ${fmtTime(src.lastSync!)}'
                            '${isSameDay(src.lastSync!, DateTime.now()) ? '' : ', ${shortDate(src.lastSync!)}'}'}',
                        style: t(23),
                      ),
                  ]),
            ),
            if (src != null)
              IconButton(
                tooltip: 'Синхронизировать',
                iconSize: s(44),
                color: ink,
                onPressed: busy
                    ? null
                    : () async {
                        ref.read(syncBusyProvider.notifier).state = true;
                        final r = await ref.read(healthServiceProvider).sync();
                        ref.read(syncBusyProvider.notifier).state = false;
                        if (context.mounted) toast(context, syncMessage(r));
                      },
                icon: busy
                    ? SizedBox(
                        width: s(30),
                        height: s(30),
                        child: const CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
              ),
          ]),
        ),
      ),

      // Умные весы
      cardBox(
        padding: EdgeInsets.fromLTRB(s(34), s(22), s(30), s(24)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(s(24)),
            child: Image.asset('assets/profile/scale.png', width: s(142), fit: BoxFit.contain),
          ),
          SizedBox(width: s(28)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Умные весы Mi', style: t(34, w: FontWeight.w800))),
                SizedBox(
                  width: s(93),
                  height: s(54),
                  child: FittedBox(
                    child: Switch(
                      value: scale.enabled,
                      onChanged: (v) => ref.read(scaleProvider).setEnabled(v),
                      activeTrackColor: kPrimary,
                      activeThumbColor: Colors.white,
                      trackOutlineColor: WidgetStateProperty.all(kPrimary.withOpacity(0.5)),
                    ),
                  ),
                ),
              ]),
              Text('Mi Body Composition Scale 2', style: t(25)),
              SizedBox(height: s(10)),
              Text(
                  'Приём по Bluetooth работает, пока приложение открыто. '
                  'Сохраняются вес и импеданс; состав тела считается по формулам (оценка).',
                  style: t(23, c: muted)),
              if (scale.lastKg != null)
                Padding(
                  padding: EdgeInsets.only(top: s(8)),
                  child: Text(
                      'Последнее: ${fmt1(scale.lastKg!)} кг, ${fmtTime(scale.lastAt!)}'
                      '${isSameDay(scale.lastAt!, DateTime.now()) ? '' : ', ${shortDate(scale.lastAt!)}'}',
                      style: t(23, w: FontWeight.w600)),
                ),
              if (scale.log.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: s(6)),
                  child: Text(scale.log.first, style: t(19, c: muted)),
                ),
            ]),
          ),
        ]),
      ),

      navCard(Icons.monitor_weight_outlined, 'Вес', const WeightPage()),
      navCard(Icons.water_drop_outlined, 'Вода', const WaterPage()),
      navCard(Icons.calendar_month_outlined, 'Календарь питания', const CalendarPage()),
      navCard(Icons.menu_book_outlined, 'Мои блюда', const RecipesPage()),
      navCard(Icons.watch_outlined, 'Устройства и источники', const DevicesPage()),
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

/// Мягкие лавандовые «волны» в правом верхнем углу карточки анкеты.
class _Swoosh extends CustomPainter {
  final Color color;
  _Swoosh(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    canvas.drawCircle(Offset(size.width * 0.93, -size.height * 0.10), size.height * 0.62, p);
    canvas.drawCircle(Offset(size.width * 1.02, size.height * 0.52), size.height * 0.30, p);
  }

  @override
  bool shouldRepaint(_Swoosh old) => old.color != color;
}
