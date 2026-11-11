// Реклама: модели и настройки. Рекламная сеть в приложение пока не подключена: здесь только
// архитектура (размещения, лимиты частоты, согласие, счётчики). Рекламе не передаётся ничего,
// кроме названия размещения: сведения о здоровье, весе, питании и пульсе в запрос не входят.
import 'dart:convert';

enum AdFormat { banner, native, rewarded }

/// Размещения рекламы. Каждое можно отключить настройкой; полноэкранная реклама не используется.
enum AdPlacement {
  homeBanner('home_banner', AdFormat.banner),
  statsBanner('stats_banner', AdFormat.banner),
  plannerNative('planner_native', AdFormat.native),
  // Необязательная видеореклама за дополнительные материалы; основные функции не блокирует.
  bonusRewarded('bonus_rewarded', AdFormat.rewarded);

  const AdPlacement(this.key, this.format);
  final String key;
  final AdFormat format;
}

enum AdDecision {
  allowed,
  placementOff, // размещение отключено настройкой
  tooSoon, // слишком скоро после прошлого показа
  dailyCap, // достигнут дневной лимит
  paused, // пауза после подряд идущих ошибок (нет объявлений)
}

/// Настройки допустимых размещений и частоты показа. Можно задать удалённо (см. ads_service).
class AdsConfig {
  final Map<String, bool> placements;
  final int minSecondsBetween;
  final int maxPerDay;
  final int errorsToPause;
  final int pauseMinutes;
  const AdsConfig({
    this.placements = const {},
    this.minSecondsBetween = 120,
    this.maxPerDay = 12,
    this.errorsToPause = 3,
    this.pauseMinutes = 60,
  });

  static const defaults = AdsConfig();

  bool placementAllowed(AdPlacement p) => placements[p.key] ?? true;

  Map<String, dynamic> toJson() => {
        'placements': placements,
        'minSecondsBetween': minSecondsBetween,
        'maxPerDay': maxPerDay,
        'errorsToPause': errorsToPause,
        'pauseMinutes': pauseMinutes,
      };

  /// Разбор с защитой: неверные или опасные значения заменяются безопасными. Удалённая
  /// настройка не может ослабить ограничения ниже порогов (не чаще раза в 30 секунд,
  /// не больше 50 показов в сутки на размещение).
  factory AdsConfig.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    int intOf(String k, int def, int min, int max) {
      final v = raw[k];
      return v is num ? v.toInt().clamp(min, max) : def;
    }

    final pl = <String, bool>{};
    final p = raw['placements'];
    if (p is Map) {
      for (final e in p.entries) {
        if (e.key is String && e.value is bool) pl[e.key as String] = e.value as bool;
      }
    }
    return AdsConfig(
      placements: pl,
      minSecondsBetween: intOf('minSecondsBetween', 120, 30, 86400),
      maxPerDay: intOf('maxPerDay', 12, 0, 50),
      errorsToPause: intOf('errorsToPause', 3, 1, 20),
      pauseMinutes: intOf('pauseMinutes', 60, 1, 1440),
    );
  }

  static AdsConfig parse(String? s) {
    if (s == null || s.isEmpty) return defaults;
    try {
      return AdsConfig.fromJson(jsonDecode(s));
    } catch (_) {
      return defaults;
    }
  }
}

/// Счётчики показов и ошибок за день по размещению.
class AdCounters {
  final int impressions;
  final int errors;
  const AdCounters(this.impressions, this.errors);
  static const zero = AdCounters(0, 0);
}
