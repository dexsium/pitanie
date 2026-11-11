import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/dates.dart';
import '../../database/database.dart';
import 'ads_models.dart';

const kAdsConfigKey = 'ads_config'; // JSON настроек размещений и частоты
const kAdsConfigUrlKey = 'ads_config_url'; // необязательный https-адрес удалённых настроек
const kAdsStatsKey = 'ads_stats'; // JSON счётчиков по дням
const kAdsStateKey = 'ads_state'; // JSON времени последнего показа и ошибок по размещениям

/// Решает, можно ли показать рекламу, и ведёт учёт показов и ошибок. Отключить рекламу
/// пользователь не может: ограничения только по частоте, размещениям и ошибкам сети.
/// Приложение работает полностью, если рекламы нет: любой отказ означает пустое место.
class AdsService {
  AdsService(this.db, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() _now;

  Future<AdsConfig> config() async => AdsConfig.parse((await db.allSettings())[kAdsConfigKey]);

  Map<String, dynamic> _json(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      final v = jsonDecode(s);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  Future<AdDecision> decide(AdPlacement p) async {
    final s = await db.allSettings();
    final cfg = AdsConfig.parse(s[kAdsConfigKey]);
    if (!cfg.placementAllowed(p)) return AdDecision.placementOff;
    final now = _now();
    final state = _json(s[kAdsStateKey])[p.key];
    if (state is Map) {
      final until = state['pausedUntil'];
      if (until is int && now.millisecondsSinceEpoch < until) return AdDecision.paused;
      final last = state['last'];
      if (last is int && now.millisecondsSinceEpoch - last < cfg.minSecondsBetween * 1000) {
        return AdDecision.tooSoon;
      }
    }
    if (todayCounters(s, p).impressions >= cfg.maxPerDay) return AdDecision.dailyCap;
    return AdDecision.allowed;
  }

  AdCounters todayCounters(Map<String, String> settings, AdPlacement p) {
    final day = _json(settings[kAdsStatsKey])[dayKey(_now())];
    final c = day is Map ? day[p.key] : null;
    if (c is! Map) return AdCounters.zero;
    return AdCounters((c['i'] as num?)?.toInt() ?? 0, (c['e'] as num?)?.toInt() ?? 0);
  }

  Future<void> _bump(AdPlacement p, {required bool impression}) async {
    final s = await db.allSettings();
    final stats = _json(s[kAdsStatsKey]);
    final today = dayKey(_now());
    final day = Map<String, dynamic>.from((stats[today] as Map?) ?? {});
    final c = Map<String, dynamic>.from((day[p.key] as Map?) ?? {});
    c[impression ? 'i' : 'e'] = ((c[impression ? 'i' : 'e'] as num?)?.toInt() ?? 0) + 1;
    day[p.key] = c;
    stats[today] = day;
    // Хранятся только последние 14 дней.
    final keys = stats.keys.toList()..sort();
    for (final k in keys.take((keys.length - 14).clamp(0, keys.length))) {
      stats.remove(k);
    }
    await db.setSetting(kAdsStatsKey, jsonEncode(stats));

    final cfg = AdsConfig.parse(s[kAdsConfigKey]);
    final all = _json(s[kAdsStateKey]);
    final st = Map<String, dynamic>.from((all[p.key] as Map?) ?? {});
    final ms = _now().millisecondsSinceEpoch;
    if (impression) {
      st['last'] = ms;
      st['errors'] = 0;
    } else {
      final errors = ((st['errors'] as num?)?.toInt() ?? 0) + 1;
      st['errors'] = errors;
      if (errors >= cfg.errorsToPause) {
        st['pausedUntil'] = ms + cfg.pauseMinutes * 60000;
        st['errors'] = 0;
      }
    }
    all[p.key] = st;
    await db.setSetting(kAdsStateKey, jsonEncode(all));
  }

  Future<void> recordImpression(AdPlacement p) => _bump(p, impression: true);

  /// Ошибка загрузки или отсутствие объявления. Несколько ошибок подряд ставят размещение
  /// на паузу, чтобы не нагружать сеть и батарею и не показывать пустые блоки.
  Future<void> recordError(AdPlacement p) => _bump(p, impression: false);

  /// Показы и ошибки за сегодня по всем размещениям (для экрана настроек).
  Future<Map<AdPlacement, AdCounters>> todayReport() async {
    final s = await db.allSettings();
    return {for (final p in AdPlacement.values) p: todayCounters(s, p)};
  }

  /// Удалённые настройки размещений: загружаются только если пользователь указал https-адрес.
  /// Запрос не содержит никаких данных пользователя. При любой ошибке остаются прежние настройки.
  Future<bool> refreshRemoteConfig({http.Client? client}) async {
    final s = await db.allSettings();
    final url = Uri.tryParse(s[kAdsConfigUrlKey] ?? '');
    if (url == null || url.scheme != 'https') return false;
    final c = client ?? http.Client();
    try {
      final r = await c.get(url).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200 || r.bodyBytes.length > 20000) return false;
      final cfg = AdsConfig.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
      await db.setSetting(kAdsConfigKey, jsonEncode(cfg.toJson()));
      return true;
    } catch (_) {
      return false;
    } finally {
      if (client == null) c.close();
    }
  }
}
