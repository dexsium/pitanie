import 'dart:async';

import 'package:flutter/services.dart';

/// Мост к виджетам главного экрана. Работает только на Android и iOS; на других платформах
/// и в тестах все вызовы безопасно ничего не делают.
class PitanieWidgets {
  PitanieWidgets._();

  static const _channel = MethodChannel('pitanie_widgets');
  static final _actions = StreamController<String>.broadcast();
  static bool _listening = false;

  /// Команды, пришедшие с виджетов, пока приложение открыто: water, nutrition, weight, settings.
  static Stream<String> get actions {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onAction' && call.arguments is String) {
          _actions.add(call.arguments as String);
          return true;
        }
        return null;
      });
    }
    return _actions.stream;
  }

  /// Передаёт виджетам готовый снимок дня (JSON) и просит обновить их.
  /// Возвращает false, если виджеты недоступны на этой платформе или сборке.
  static Future<bool> update(String json) async {
    try {
      return await _channel.invokeMethod<bool>('update', {'json': json}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Команда, с которой приложение было открыто нажатием на виджет (и сброс этой команды).
  static Future<String?> takeInitialAction() async {
    try {
      return await _channel.invokeMethod<String>('initialAction');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Доступны ли виджеты в этой сборке (на iOS: настроена ли группа приложений).
  static Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
