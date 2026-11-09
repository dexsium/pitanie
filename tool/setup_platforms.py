#!/usr/bin/env python3
"""Настройка сгенерированных папок android/ и ios/ после `flutter create`.

Добавляет разрешения Health Connect / HealthKit / камеры / уведомлений,
MainActivity на FlutterFragmentActivity, minSdk 26, desugaring и
entitlements HealthKit. Скрипт идемпотентен: повторный запуск безопасен.
Запускать из корня проекта после `flutter create` и `flutter pub get`.
"""
import glob
import os
import re
import sys

ROOT = os.getcwd()


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


BG_PLIST = (
    chr(9) + "<key>UIBackgroundModes</key>" + chr(10)
    + chr(9) + "<array>" + chr(10)
    + chr(9) + chr(9) + "<string>bluetooth-central</string>" + chr(10)
    + chr(9) + "</array>" + chr(10)
)

BLE_PLIST = (
    chr(9) + "<key>NSBluetoothAlwaysUsageDescription</key>" + chr(10)
    + chr(9) + "<string>Bluetooth нужен для поиска и подключения умных часов.</string>" + chr(10)
)


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def patch_manifest():
    path = os.path.join(ROOT, "android/app/src/main/AndroidManifest.xml")
    if not os.path.exists(path):
        print("skip: нет AndroidManifest.xml")
        return
    s = read(path)
    ble = """
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>
"""
    if "BLUETOOTH_SCAN" not in s:
        s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + ble, s, count=1)
        write(path, s)
        print("AndroidManifest: добавлены разрешения Bluetooth")
    if "READ_STEPS" in s:
        print("AndroidManifest уже настроен")
        return
    perms = """
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.health.READ_STEPS"/>
    <uses-permission android:name="android.permission.health.READ_DISTANCE"/>
    <uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED"/>
    <uses-permission android:name="android.permission.health.READ_TOTAL_CALORIES_BURNED"/>
    <uses-permission android:name="android.permission.health.READ_HEART_RATE"/>
    <uses-permission android:name="android.permission.health.READ_SLEEP"/>
    <uses-permission android:name="android.permission.health.READ_EXERCISE"/>
    <queries>
        <package android:name="com.google.android.apps.healthdata"/>
        <intent>
            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
        </intent>
    </queries>
"""
    s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + perms, s, count=1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="Питание"', s, count=1)
    rationale = """
            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
            </intent-filter>
        </activity>
        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE"
            android:targetActivity=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>
                <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>
            </intent-filter>
        </activity-alias>"""
    s = s.replace("</activity>", rationale, 1)
    write(path, s)
    print("AndroidManifest обновлён")


def patch_main_activity():
    files = glob.glob(os.path.join(ROOT, "android/app/src/main/kotlin/**/MainActivity.kt"), recursive=True)
    for path in files:
        s = read(path)
        if "FlutterFragmentActivity" in s:
            print("MainActivity уже настроена")
            continue
        pkg = re.search(r"^package\s+[\w.]+", s, re.M).group(0)
        write(path, f"""{pkg}

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
""")
        print("MainActivity обновлена")


def patch_gradle():
    for name in ("build.gradle.kts", "build.gradle"):
        path = os.path.join(ROOT, "android/app", name)
        if not os.path.exists(path):
            continue
        s = read(path)
        if "coreLibraryDesugaring" in s:
            print(f"{name} уже настроен")
            return
        kts = name.endswith(".kts")
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", s)
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", s)
        flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
        s = re.sub(r"(compileOptions\s*\{)", lambda m: m.group(1) + "\n        " + flag, s, count=1)
        dep = ('coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if kts
               else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'")
        s += f"\n\ndependencies {{\n    {dep}\n}}\n"
        write(path, s)
        print(f"{name} обновлён")
        return
    print("skip: нет build.gradle")


def patch_plist():
    path = os.path.join(ROOT, "ios/Runner/Info.plist")
    if not os.path.exists(path):
        print("skip: нет Info.plist")
        return
    s = read(path)
    if "NSBluetoothAlwaysUsageDescription" not in s:
        idx = s.rfind("</dict>")
        s = s[:idx] + BLE_PLIST + s[idx:]
        write(path, s)
        print("Info.plist: добавлено описание Bluetooth")
    if "UIBackgroundModes" not in s:
        idx = s.rfind("</dict>")
        s = s[:idx] + BG_PLIST + s[idx:]
        write(path, s)
        print("Info.plist: добавлен фоновый режим bluetooth-central")
    if "NSHealthShareUsageDescription" in s:
        print("Info.plist уже настроен")
        return
    add = """	<key>NSHealthShareUsageDescription</key>
	<string>Приложение читает шаги, активность, пульс и сон из Apple Health, чтобы показывать вашу активность рядом с питанием.</string>
	<key>NSHealthUpdateUsageDescription</key>
	<string>Запись в Apple Health приложением не выполняется.</string>
	<key>NSCameraUsageDescription</key>
	<string>Камера нужна для сканирования штрихкодов и для фото еды (распознавание умным помощником).</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Доступ к фото нужен, чтобы выбрать снимок еды для распознавания.</string>
	<key>CFBundleDisplayName</key>
	<string>Питание</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
"""
    s = re.sub(r"\t<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>\n", "", s)
    idx = s.rfind("</dict>")
    s = s[:idx] + add + s[idx:]
    write(path, s)
    print("Info.plist обновлён")


def patch_ios_project():
    ent = os.path.join(ROOT, "ios/Runner/Runner.entitlements")
    if os.path.isdir(os.path.dirname(ent)) and not os.path.exists(ent):
        write(ent, """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
</dict>
</plist>
""")
        print("Runner.entitlements создан")
    pbx = os.path.join(ROOT, "ios/Runner.xcodeproj/project.pbxproj")
    if os.path.exists(pbx):
        s = read(pbx)
        s = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.5;", s)
        if "CODE_SIGN_ENTITLEMENTS" not in s:
            s = re.sub(
                r"(\t+)(PRODUCT_BUNDLE_IDENTIFIER = [^;]*(?<!RunnerTests);\n)",
                lambda m: f"{m.group(1)}CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n{m.group(1)}{m.group(2)}",
                s,
            )
            # Entitlements-файл должен быть в проекте как ссылка не обязательно:
            # путь в CODE_SIGN_ENTITLEMENTS достаточен для сборки.
        write(pbx, s)
        print("project.pbxproj обновлён")
    pod = os.path.join(ROOT, "ios/Podfile")
    if os.path.exists(pod):
        s = read(pod)
        s = re.sub(r"#?\s*platform :ios, '[\d.]+'", "platform :ios, '15.5'", s, count=1)
        write(pod, s)
        print("Podfile обновлён")
    else:
        print("Podfile ещё не создан (появится после flutter pub get / сборки)")


if __name__ == "__main__":
    if not os.path.exists(os.path.join(ROOT, "pubspec.yaml")):
        sys.exit("Запускайте из корня проекта")
    patch_manifest()
    patch_main_activity()
    patch_gradle()
    patch_plist()
    patch_ios_project()
