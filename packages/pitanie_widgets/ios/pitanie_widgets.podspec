#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pitanie_widgets.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pitanie_widgets'
  s.version          = '0.0.1'
  s.summary          = 'Виджеты главного экрана для приложения питания.'
  s.description      = <<-DESC
Виджеты главного экрана для приложения питания.
                       DESC
  s.homepage         = 'https://github.com/dexsium/pitanie'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'pitanie' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'pitanie_widgets/Sources/pitanie_widgets/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'pitanie_widgets_privacy' => ['pitanie_widgets/Sources/pitanie_widgets/PrivacyInfo.xcprivacy']}
end
