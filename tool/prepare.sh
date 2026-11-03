#!/usr/bin/env bash
# Подготовка проекта: платформенные папки, зависимости, кодогенерация Drift,
# настройка разрешений. Запускать из корня проекта.
set -euo pipefail

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create --platforms=android,ios --org com.pitanie --project-name pitanie .
  rm -f test/widget_test.dart
fi
flutter pub get
dart run build_runner build --delete-conflicting-outputs
python3 tool/setup_platforms.py
flutter pub get
dart run flutter_launcher_icons
