Pod::Spec.new do |s|
  s.name             = 'pitanie_native_ads'
  s.version          = '0.0.1'
  s.summary          = 'Нативная реклама Яндекса для приложения питания (iOS).'
  s.description      = <<-DESC
Платформенное представление нативной рекламы Яндекса (Yandex Mobile Ads SDK 8).
                       DESC
  s.homepage         = 'https://github.com/dexsium/pitanie'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'pitanie' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'pitanie_native_ads/Sources/pitanie_native_ads/**/*'
  s.dependency 'Flutter'
  # Версия совпадает с официальным плагином yandex_mobileads, чтобы не было двух SDK.
  s.dependency 'YandexMobileAds', '~> 8.6.0'
  s.platform = :ios, '15.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.xcconfig = { 'OTHER_LDFLAGS' => '-ObjC' }
  s.swift_version = '5.0'
end
