import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/health_analysis/services/health_monitor.dart';
import '../services/health/plan_service.dart';
import '../features/activity/activity_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/nutrition/nutrition_page.dart';
import '../features/profile/onboarding_page.dart';
import '../features/profile/profile_page.dart';
import '../features/settings/notification_service.dart';
import '../features/statistics/statistics_page.dart';
import '../features/wearables/wearable_controller.dart';
import '../database/catalog_importer.dart';
import '../features/scale/scale_controller.dart';
import '../features/scale/scale_measure_page.dart';
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
  bool _syncWasBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _sync();
      ref.read(wearableProvider).start();
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
      ref.read(wearableProvider).start();
      ref.read(scaleProvider).start();
      _autoPlan();
      _healthCheck();
    }
  }

  /// Анализ здоровья: после синхронизации часов, при запуске и возврате в приложение.
  Future<void> _healthCheck() async {
    try {
      final n = ref.read(notificationsProvider);
      await runHealthMonitor(ref.read(dbProvider),
          (id, title, body, urgent) => n.showNow(id, title, body, urgent: urgent));
    } catch (_) {}
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
    ref.listen<WearableController>(wearableProvider, (prev, next) {
      if (_syncWasBusy && !next.syncBusy) _healthCheck();
      _syncWasBusy = next.syncBusy;
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
