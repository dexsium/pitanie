import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../features/coach/goal_service.dart';
import '../features/dashboard/day_data.dart';
import '../features/settings/notif_prefs.dart';
import '../services/health/plan_service.dart';
import '../features/activity/activity_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/nutrition/nutrition_page.dart';
import '../features/profile/onboarding_page.dart';
import '../features/profile/profile_page.dart';
import '../features/settings/notification_service.dart';
import '../features/statistics/statistics_page.dart';
import '../features/wearables/workout_service.dart';
import '../database/catalog_importer.dart';
import '../features/scale/scale_controller.dart';
import '../features/scale/scale_measure_page.dart';
import 'package:pitanie_widgets/pitanie_widgets.dart';

import '../features/settings/settings_page.dart';
import '../features/water/water_page.dart';
import '../features/weight/weight_page.dart';
import '../features/widgets/widget_sync.dart';
import 'providers.dart';
import 'theme.dart';

final notificationsProvider = Provider<NotificationService>((ref) => NotificationService());

class PitanieApp extends ConsumerWidget {
  const PitanieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).valueOrNull ?? {};
    final mode = switch (s['theme']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'Питание',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Gate(),
    );
  }
}

/// Показывает анкету при первом запуске, затем основное приложение.
class _Gate extends ConsumerWidget {
  const _Gate();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    return user.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Ошибка базы данных: $e'))),
      data: (u) => u == null ? const OnboardingPage() : const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  bool _measureOpen = false;
  StreamSubscription<String>? _widgetActions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetActions = PitanieWidgets.actions.listen(_onWidgetAction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      PitanieWidgets.takeInitialAction().then((a) {
        if (a != null) _onWidgetAction(a);
      });
      scheduleWidgetUpdate(ref.read(dbProvider));
      _sync();
      ref.read(scaleProvider).start();
      _loadCatalog();
      _autoPlan();
      _healthCheck();
      final n = ref.read(notificationsProvider);
      await n.init();
      await n.reschedule(await ref.read(dbProvider).allSettings());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetActions?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(notificationsProvider).cancel(8).catchError((_) {});
      scheduleWidgetUpdate(ref.read(dbProvider));
      _sync();
      ref.read(scaleProvider).start();
      _autoPlan();
      _healthCheck();
    }
  }

  /// Нажатие на виджет главного экрана: открываем нужный раздел. Данные из виджета в базу
  /// не пишутся: вода и взвешивание добавляются на открывшемся экране самим пользователем.
  void _onWidgetAction(String action) {
    if (!mounted) return;
    switch (action) {
      case 'nutrition':
        ref.read(tabProvider.notifier).state = 1;
      case 'water':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WaterPage()));
      case 'weight':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeightPage()));
      case 'settings':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    }
  }

  /// Проверка после синхронизации, при запуске и возврате в приложение: тренировки и цели.
  Future<void> _healthCheck() async {
    // Тренировки по пульсу: новая найденная тренировка приходит уведомлением.
    try {
      final n = ref.read(notificationsProvider);
      final db = ref.read(dbProvider);
      await scanWorkouts(db, (id, title, body) async {
        if (!notifEnabled(await db.allSettings(), kNotifWorkoutsKey)) return;
        await n.showNow(id, title, body);
      });
    } catch (_) {}
    await _goalCheck();
  }

  bool _goalBusy = false;

  /// Цели дня: уведомление о выполненных и пересчёт вечерней подсказки «чем добрать норму».
  Future<void> _goalCheck() async {
    if (_goalBusy) return;
    _goalBusy = true;
    try {
      final n = ref.read(notificationsProvider);
      final db = ref.read(dbProvider);
      await checkGoals(db, (id, title, body) async {
        if (!notifEnabled(await db.allSettings(), kNotifGoalsKey)) return;
        await n.showGoal(id, title, body);
      });
      await updateCoach(db, n);
    } catch (_) {
    } finally {
      _goalBusy = false;
    }
  }

  /// Автоприменение корректировки нормы (только если пользователь включил его в настройках).
  Future<void> _autoPlan() async {
    try {
      await maybeAutoApply(ref.read(dbProvider));
    } catch (_) {}
  }

  Future<void> _loadCatalog() async {
    try {
      final res = await ensureCatalog(ref.read(dbProvider), onProgress: (d, t) {
        if (mounted) ref.read(catalogProgressProvider.notifier).state = d / t;
      });
      if (res != null) debugPrint('Каталог: добавлено ${res.added} из ${res.total}');
    } catch (e) {
      debugPrint('Не удалось загрузить каталог: $e');
    } finally {
      if (mounted) ref.read(catalogProgressProvider.notifier).state = null;
    }
  }

  Future<void> _sync() async {
    if (ref.read(syncBusyProvider)) return;
    ref.read(syncBusyProvider.notifier).state = true;
    try {
      await ref.read(healthServiceProvider).sync();
    } finally {
      if (mounted) ref.read(syncBusyProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(tabProvider);
    // Человек встал на весы, пока приложение открыто: само открываем окно измерения.
    // Данные сегодняшнего дня изменились (еда, вода, шаги): проверяем цели.
    ref.listen<AsyncValue<DayData>>(dayDataProvider(dayKey(DateTime.now())),
        (prev, next) {
      final d = next.valueOrNull;
      if (d == null) return;
      String sig(DayData x) =>
          '${x.food.length}|${x.eaten.calories.round()}|${x.plainWaterMl.round()}|'
          '${x.activity.steps.round()}|${x.calorieTarget.round()}';
      final p = prev?.valueOrNull;
      if (p == null || sig(p) != sig(d)) {
        _goalCheck();
        scheduleWidgetUpdate(ref.read(dbProvider));
      }
    });
    ref.listen<bool>(syncBusyProvider, (prev, next) {
      if (prev == true && !next) _healthCheck();
    });
    ref.listen<ScaleController>(scaleProvider, (prev, next) {
      if (next.phase == ScalePhase.measuring &&
          !next.dismissed &&
          !_measureOpen &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
        _measureOpen = true;
        Navigator.of(context)
            .push(MaterialPageRoute(
                fullscreenDialog: true, builder: (_) => const ScaleMeasurePage()))
            .whenComplete(() => _measureOpen = false);
      }
    });
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: tab, children: const [
          DashboardPage(),
          NutritionPage(),
          ActivityPage(),
          StatisticsPage(),
          ProfilePage(),
        ]),
      ),
      bottomNavigationBar: Theme(
        data: tab == 2 ? _greenNav(Theme.of(context)) : Theme.of(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Линия 1 px между экраном и нижним меню (слегка серая, заметная в обеих темах).
            Container(
              height: 1,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0x59FFFFFF)
                  : const Color(0xFFBDBDCB),
            ),
            NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Питание'),
          NavigationDestination(icon: Icon(Icons.directions_run), label: 'Активность'),
          NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Статистика'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Профиль'),
        ],
      ),
          ],
        ),
      ),
    );
  }
}

/// На вкладке «Активность» выбранный пункт нижней панели фиолетовый, как в макете раздела.
ThemeData _greenNav(ThemeData base) => base.copyWith(
      navigationBarTheme: base.navigationBarTheme.copyWith(
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
            fontSize: 12,
            fontWeight: st.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: st.contains(WidgetState.selected) ? kPrimary : null)),
        iconTheme: WidgetStateProperty.resolveWith((st) =>
            IconThemeData(color: st.contains(WidgetState.selected) ? kPrimary : null)),
      ),
    );
