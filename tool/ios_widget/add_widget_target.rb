# Добавляет в сгенерированный проект iOS расширение виджета WidgetKit (цель PitanieWidget),
# внедряет его в приложение, включает группу приложений и адрес pitanie:// для открытия из виджета.
# Запускается только в CI и только когда задан секрет профиля виджета (см. ios-testflight.yml).
# Не проверялось на реальной сборке: при первом запуске смотрите журнал шага.
#
# Окружение: TEAM_ID, WIDGET_PROFILE_NAME. Запуск из корня репозитория.
require "fileutils"
require "xcodeproj"

TEAM = ENV.fetch("TEAM_ID")
PROFILE = ENV.fetch("WIDGET_PROFILE_NAME")
APP_BUNDLE = ENV.fetch("BUNDLE_ID", "com.pitanie.pitanie")
WIDGET_BUNDLE = "#{APP_BUNDLE}.widget"
APP_GROUP = "group.#{APP_BUNDLE}"

src = File.join("tool", "ios_widget", "PitanieWidget")
dst = File.join("ios", "PitanieWidget")
FileUtils.rm_rf(dst)
FileUtils.cp_r(src, dst)

proj = Xcodeproj::Project.open("ios/Runner.xcodeproj")
runner = proj.targets.find { |t| t.name == "Runner" } or abort("цель Runner не найдена")
abort("цель PitanieWidget уже есть") if proj.targets.any? { |t| t.name == "PitanieWidget" }

ext = proj.new_target(:app_extension, "PitanieWidget", :ios, "15.0")

group = proj.main_group.new_group("PitanieWidget", "PitanieWidget")
swift = group.new_file("PitanieWidget.swift")
group.new_file("Info.plist")
group.new_file("PitanieWidget.entitlements")
ext.add_file_references([swift])

runner_configs = runner.build_configurations.map { |c| [c.name, c] }.to_h
ext.build_configurations.each do |c|
  s = c.build_settings
  base = runner_configs[c.name]
  # Номера версии и сборки берутся из тех же xcconfig, что и у приложения.
  c.base_configuration_reference = base.base_configuration_reference if base
  s["PRODUCT_BUNDLE_IDENTIFIER"] = WIDGET_BUNDLE
  s["PRODUCT_NAME"] = "$(TARGET_NAME)"
  s["INFOPLIST_FILE"] = "PitanieWidget/Info.plist"
  s["GENERATE_INFOPLIST_FILE"] = "NO"
  s["CODE_SIGN_ENTITLEMENTS"] = "PitanieWidget/PitanieWidget.entitlements"
  s["CODE_SIGN_STYLE"] = "Manual"
  s["DEVELOPMENT_TEAM"] = TEAM
  s["PROVISIONING_PROFILE_SPECIFIER"] = PROFILE
  s["CODE_SIGN_IDENTITY"] = "Apple Distribution"
  s["SWIFT_VERSION"] = "5.0"
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
  s["TARGETED_DEVICE_FAMILY"] = "1"
  s["SKIP_INSTALL"] = "YES"
  s["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks",
                                  "@executable_path/../../Frameworks"]
  s["ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS"] = "NO"
end

# Внедрение расширения в приложение: фаза копирования в PlugIns перед «Thin Binary»,
# иначе сборка Flutter может упереться в цикл зависимостей.
embed = runner.new_copy_files_build_phase("Embed Foundation Extensions")
embed.symbol_dst_subfolder_spec = :plug_ins
file = embed.add_file_reference(ext.product_reference, true)
file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
runner.build_phases.delete(embed)
idx = runner.build_phases.index { |p| p.respond_to?(:name) && p.name.to_s.include?("Thin Binary") }
runner.build_phases.insert(idx || runner.build_phases.length, embed)
runner.add_dependency(ext)

proj.save

# Группа приложений в правах основного приложения.
ent = "ios/Runner/Runner.entitlements"
abort("нет #{ent}") unless File.exist?(ent)
pb = "/usr/libexec/PlistBuddy"
unless system(pb, "-c", "Print :com.apple.security.application-groups", ent, out: File::NULL, err: File::NULL)
  system(pb, "-c", "Add :com.apple.security.application-groups array", ent) or abort("PlistBuddy: группа")
  system(pb, "-c", "Add :com.apple.security.application-groups:0 string #{APP_GROUP}", ent) or abort("PlistBuddy: значение")
end

# Адрес pitanie:// для открытия приложения из виджета.
info = "ios/Runner/Info.plist"
unless system(pb, "-c", "Print :CFBundleURLTypes", info, out: File::NULL, err: File::NULL)
  system(pb, "-c", "Add :CFBundleURLTypes array", info) or abort("PlistBuddy: URL types")
  system(pb, "-c", "Add :CFBundleURLTypes:0 dict", info)
  system(pb, "-c", "Add :CFBundleURLTypes:0:CFBundleURLName string #{APP_BUNDLE}", info)
  system(pb, "-c", "Add :CFBundleURLTypes:0:CFBundleURLSchemes array", info)
  system(pb, "-c", "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string pitanie", info) or abort("PlistBuddy: схема")
end

puts "Расширение виджета добавлено: #{WIDGET_BUNDLE}, профиль «#{PROFILE}»"
