// Доступ часов к системным уведомлениям iPhone (ANCS). Только чтение статуса из iOS.
//
// Приложение не получает чужие уведомления и не управляет ими: часы сами читают их у iPhone по
// Bluetooth, а разрешает это пользователь в «Настройки → Bluetooth → часы → Делиться системными
// уведомлениями». Здесь показывается то, что iOS сообщает публичным свойством ancsAuthorized.
import 'dart:io';

import 'package:flutter/services.dart';

enum AncsState {
  /// Не iOS или нативный вызов недоступен.
  unsupported,
  bluetoothOff,
  noBluetoothAccess,

  /// iOS не знает часы с сохранённым идентификатором (не сопряжены на уровне системы).
  watchNotFound,
  authorized,
  denied,
  unknown,
}

class AncsStatus {
  final AncsState state;
  final String? watchName;

  /// 0 отключено, 1 подключается, 2 подключено, 3 отключается (CBPeripheralState).
  final int? connection;

  /// Техническая причина, если статус определить не удалось (для диагностики).
  final String? detail;
  const AncsStatus(this.state, {this.watchName, this.connection, this.detail});

  String get title => switch (state) {
        AncsState.authorized => 'Разрешён',
        AncsState.denied => 'Не разрешён',
        AncsState.watchNotFound => 'Часы не найдены в системе',
        AncsState.bluetoothOff => 'Bluetooth выключен',
        AncsState.noBluetoothAccess => 'Нет доступа к Bluetooth',
        AncsState.unsupported => 'Недоступно',
        AncsState.unknown => 'Не удалось определить',
      };
}

AncsStatus parseAncsStatus(Map? m) {
  if (m == null) return const AncsStatus(AncsState.unknown);
  final name = (m['name'] as String?)?.trim();
  final conn = m['connection'] as int?;
  final detail =
      'ответ iOS: ${m.entries.where((e) => e.key != 'name').map((e) => '${e.key}=${e.value}').join(', ')}';
  AncsStatus s(AncsState st) => AncsStatus(st,
      watchName: name == null || name.isEmpty ? null : name,
      connection: conn,
      detail: detail);
  switch (m['state']) {
    case 'poweredOff':
      return s(AncsState.bluetoothOff);
    case 'unauthorized':
      return s(AncsState.noBluetoothAccess);
    case 'unsupported':
      return s(AncsState.unsupported);
    case 'poweredOn':
      if (m['found'] != true) return s(AncsState.watchNotFound);
      final a = m['ancsAuthorized'];
      if (a is bool) return s(a ? AncsState.authorized : AncsState.denied);
      return s(AncsState.unknown);
    default:
      return s(AncsState.unknown);
  }
}

class WatchAncs {
  static const _ch = MethodChannel('pitanie/watch_ancs');

  static bool get supported => Platform.isIOS;

  /// [id] — идентификатор часов (remoteId из flutter_blue_plus, на iOS это UUID).
  static Future<AncsStatus> status(String? id) async {
    if (!supported) return const AncsStatus(AncsState.unsupported);
    if (id == null || id.isEmpty) {
      return const AncsStatus(AncsState.watchNotFound);
    }
    Object? last;
    // Нативный канал может зарегистрироваться через пару секунд после запуска: повторяем.
    for (var i = 0; i < 4; i++) {
      try {
        final r = await _ch.invokeMethod<Map>('status', id);
        return parseAncsStatus(r);
      } on MissingPluginException catch (e) {
        last = e;
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        return AncsStatus(AncsState.unknown, detail: 'ошибка вызова: $e');
      }
    }
    return AncsStatus(AncsState.unknown, detail: 'ошибка вызова: $last');
  }
}
