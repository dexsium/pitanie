import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitanie/app/providers.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/ads/ad_provider.dart';
import 'package:pitanie/features/ads/ad_slot.dart';
import 'package:pitanie/features/ads/ads_models.dart';
import 'package:pitanie/features/ads/ads_service.dart';
import 'package:pitanie/features/ads/native_ad_config.dart';
import 'package:pitanie/features/ads/yandex_ad_provider.dart';

class FakeProvider extends AdProvider {
  FakeProvider({this.ad, this.throws = false, this.isAvailable = true});
  final Widget? ad;
  final bool throws;
  final bool isAvailable;
  final requested = <AdPlacement>[];
  @override
  String get name => 'тестовая';
  @override
  bool get available => isAvailable;
  @override
  Future<Widget?> buildAd(AdPlacement placement, {AdEvents? events}) async {
    requested.add(placement);
    if (throws) throw StateError('sdk failure');
    return ad;
  }
}

void main() {
  yandexTests();
  late AppDatabase db;
  var now = DateTime(2026, 11, 10, 12);
  setUp(() {
    db = AppDatabase.memory();
    now = DateTime(2026, 11, 10, 12);
  });
  tearDown(() => db.close());

  AdsService svc() => AdsService(db, clock: () => now);

  group('решения о показе', () {
    test('отключить рекламу пользователь не может: без настроек она разрешена', () async {
      for (final p in AdPlacement.values) {
        expect(await svc().decide(p), AdDecision.allowed);
      }
    });

    test('частота: не чаще интервала и не больше дневного лимита', () async {
      final s = svc();
      await db.setSetting(
          kAdsConfigKey, jsonEncode(const AdsConfig(minSecondsBetween: 60, maxPerDay: 2).toJson()));
      const p = AdPlacement.homeBanner;
      expect(await s.decide(p), AdDecision.allowed);
      await s.recordImpression(p);
      expect(await s.decide(p), AdDecision.tooSoon);
      now = now.add(const Duration(seconds: 61));
      expect(await s.decide(p), AdDecision.allowed);
      await s.recordImpression(p);
      now = now.add(const Duration(minutes: 5));
      expect(await s.decide(p), AdDecision.dailyCap);
      // Другое размещение считается отдельно.
      expect(await s.decide(AdPlacement.statsBanner), AdDecision.allowed);
      // Завтра лимит обнуляется.
      now = DateTime(2026, 11, 11, 9);
      expect(await s.decide(p), AdDecision.allowed);
    });

    test('отключённое размещение не показывается', () async {
      final s = svc();
      await db.setSetting(
          kAdsConfigKey, jsonEncode(const AdsConfig(placements: {'home_banner': false}).toJson()));
      expect(await s.decide(AdPlacement.homeBanner), AdDecision.placementOff);
      expect(await s.decide(AdPlacement.statsBanner), AdDecision.allowed);
    });

    test('подряд идущие ошибки ставят размещение на паузу, потом пауза проходит', () async {
      final s = svc();
      await db.setSetting(
          kAdsConfigKey, jsonEncode(const AdsConfig(errorsToPause: 2, pauseMinutes: 30).toJson()));
      const p = AdPlacement.statsBanner;
      await s.recordError(p);
      expect(await s.decide(p), AdDecision.allowed);
      await s.recordError(p);
      expect(await s.decide(p), AdDecision.paused);
      now = now.add(const Duration(minutes: 31));
      expect(await s.decide(p), AdDecision.allowed);
      final report = await s.todayReport();
      expect(report[p]!.errors, 2);
    });

    test('счётчики показов и ошибок ведутся по размещениям, хранятся 14 дней', () async {
      final s = svc();
      await s.recordImpression(AdPlacement.homeBanner);
      await s.recordImpression(AdPlacement.homeBanner);
      await s.recordError(AdPlacement.plannerNative);
      var r = await s.todayReport();
      expect(r[AdPlacement.homeBanner]!.impressions, 2);
      expect(r[AdPlacement.plannerNative]!.errors, 1);
      for (var d = 1; d <= 20; d++) {
        now = DateTime(2026, 11, 10).add(Duration(days: d));
        await s.recordImpression(AdPlacement.homeBanner);
      }
      final stats = jsonDecode((await db.allSettings())[kAdsStatsKey]!) as Map;
      expect(stats.length, 14);
      r = await s.todayReport();
      expect(r[AdPlacement.homeBanner]!.impressions, 1);
    });
  });

  group('удалённые настройки', () {
    test('безопасный разбор: мусор и опасные значения заменяются', () {
      expect(AdsConfig.parse(null).maxPerDay, 12);
      expect(AdsConfig.parse('не json').maxPerDay, 12);
      final c = AdsConfig.fromJson({
        'minSecondsBetween': 1,
        'maxPerDay': 100000,
        'errorsToPause': 0,
        'placements': {'home_banner': false, 'x': 5, 3: true},
      });
      expect(c.minSecondsBetween, 30);
      expect(c.maxPerDay, 50);
      expect(c.errorsToPause, 1);
      expect(c.placementAllowed(AdPlacement.homeBanner), isFalse);
      expect(c.placementAllowed(AdPlacement.statsBanner), isTrue);
    });

    test('загружаются только по https и только при успехе', () async {
      final s = svc();
      final client = MockClient((r) async => http.Response(
          jsonEncode({'maxPerDay': 3, 'placements': {'stats_banner': false}}), 200));
      expect(await s.refreshRemoteConfig(client: client), isFalse); // адрес не задан
      await db.setSetting(kAdsConfigUrlKey, 'http://example.com/ads.json');
      expect(await s.refreshRemoteConfig(client: client), isFalse); // не https
      await db.setSetting(kAdsConfigUrlKey, 'https://example.com/ads.json');
      expect(await s.refreshRemoteConfig(client: client), isTrue);
      final cfg = await s.config();
      expect(cfg.maxPerDay, 3);
      expect(cfg.placementAllowed(AdPlacement.statsBanner), isFalse);
      // Ошибка сервера не стирает прежние настройки.
      final bad = MockClient((r) async => http.Response('err', 500));
      expect(await s.refreshRemoteConfig(client: bad), isFalse);
      expect((await s.config()).maxPerDay, 3);
    });
  });

  group('рекламное место', () {
    Future<void> pump(WidgetTester t, AppDatabase d, AdProvider p) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(d),
          adProviderProvider.overrideWithValue(p),
          adsServiceProvider.overrideWithValue(AdsService(d, clock: () => now)),
        ],
        child: const MaterialApp(home: Scaffold(body: AdSlot(AdPlacement.homeBanner))),
      ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }

    testWidgets('без подключённой сети место пустое и ничего не запрашивается', (t) async {
      final d = AppDatabase(NativeDatabase.memory());
      await pump(t, d, const NoAdProvider());
      expect(find.text('Реклама'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => d.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
    });

    testWidgets('показывает объявление с подписью и учитывает показ', (t) async {
      final d = AppDatabase(NativeDatabase.memory());
      final p = FakeProvider(ad: const Text('объявление'));
      await pump(t, d, p);
      expect(find.text('Реклама'), findsOneWidget);
      expect(find.text('объявление'), findsOneWidget);
      final r = await t.runAsync(() => AdsService(d, clock: () => now).todayReport());
      expect(r![AdPlacement.homeBanner]!.impressions, 1);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => d.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
    });

    testWidgets('заглушка показывается всегда и не попадает в счётчики', (t) async {
      final d = AppDatabase(NativeDatabase.memory());
      for (var i = 0; i < 3; i++) {
        await pump(t, d, const PlaceholderAdProvider());
        expect(find.text('Реклама'), findsOneWidget);
        expect(find.text('Здесь будет реклама'), findsOneWidget);
      }
      final r = await t.runAsync(() => AdsService(d, clock: () => now).todayReport());
      expect(r![AdPlacement.homeBanner]!.impressions, 0);
      await t.pumpWidget(const SizedBox());
      await t.runAsync(() => d.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
    });

    testWidgets('пустой ответ и сбой SDK: место пустое, приложение работает, ошибка учтена', (t) async {
      for (final p in [FakeProvider(), FakeProvider(throws: true)]) {
        final d = AppDatabase(NativeDatabase.memory());
          await pump(t, d, p);
        expect(find.text('Реклама'), findsNothing);
        expect(t.takeException(), isNull);
        final r = await t.runAsync(() => AdsService(d, clock: () => now).todayReport());
        expect(r![AdPlacement.homeBanner]!.errors, 1);
        await t.pumpWidget(const SizedBox());
        await t.runAsync(() => d.close().timeout(const Duration(seconds: 5), onTimeout: () {}));
      }
    });
  });
}

void yandexTests() {
  test('блоки РСЯ: главная и статистика — баннеры, для планировщика блока во Flutter нет', () {
    expect(YandexAdProvider.unitFor(AdPlacement.homeBanner), 'R-M-20382283-2');
    expect(YandexAdProvider.unitFor(AdPlacement.statsBanner), 'R-M-20382283-3');
    expect(YandexAdProvider.unitFor(AdPlacement.nutritionBanner), isNotNull);
    expect(YandexAdProvider.unitFor(AdPlacement.plannerNative), kNativeAdUnitId);
    expect(YandexAdProvider.unitFor(AdPlacement.bonusRewarded), isNull);
    const p = YandexAdProvider();
    expect(p.available, Platform.isIOS); // реклама подключена только на iOS
    expect(p.reportsOwnEvents, isTrue);
    expect(p.providesLabel(AdPlacement.plannerNative), isTrue);
    expect(p.providesLabel(AdPlacement.homeBanner), isFalse);
  });

  test('без платформенной части SDK провайдер не падает и ничего не показывает', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const p = YandexAdProvider();
    final w = await p.buildAd(AdPlacement.homeBanner,
        events: AdEvents(onLoaded: () {}, onFailed: () {}));
    expect(w, isNull);
    expect(await p.buildAd(AdPlacement.plannerNative,
        events: AdEvents(onLoaded: () {}, onFailed: () {})), isNull);
  });
}
