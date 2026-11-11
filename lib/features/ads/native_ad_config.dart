// Настройки нативной рекламы Яндекса (РСЯ) в планировщике питания.

/// Рабочий блок нативной рекламы в РСЯ.
const String kNativeAdProductionUnitId = 'R-M-20382283-1';

/// Демонстрационный блок Яндекса для рекламы приложений (иконка, цена, кнопка).
/// Не приносит дохода и нужен только для проверки интеграции.
const String kNativeAdDemoUnitId = 'demo-native-app-yandex';

/// Переключатель тестового и рабочего режима. Пока интеграцию проверяют в TestFlight,
/// включена демонстрационная реклама. Перед коммерческим запуском поставьте значение по
/// умолчанию `false` (или соберите с `--dart-define=NATIVE_AD_DEMO=false`).
const bool kNativeAdUseDemo = bool.fromEnvironment('NATIVE_AD_DEMO', defaultValue: true);

/// Идентификатор блока, который используется сейчас.
const String kNativeAdUnitId = kNativeAdUseDemo ? kNativeAdDemoUnitId : kNativeAdProductionUnitId;

/// Тип платформенного представления (совпадает с iOS-плагином pitanie_native_ads).
const String kNativeAdViewType = 'pitanie/native_ad';
