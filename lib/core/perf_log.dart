import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Журнал производительности: хранится только в памяти, без личных данных (названия этапов,
/// количества записей и длительности). Нужен, чтобы найти, что именно тормозит приложение.
class PerfLog {
  static final Stopwatch _sw = Stopwatch()..start();
  static final List<String> _lines = [];
  static const _max = 1500;
  static bool _watching = false;

  static void mark(String what) {
    _lines.add('${_sw.elapsedMilliseconds.toString().padLeft(6)} мс  $what');
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
  }

  /// Выполняет [f] и записывает длительность этапа.
  static Future<T> time<T>(String what, Future<T> Function() f) async {
    final s = Stopwatch()..start();
    try {
      return await f();
    } finally {
      mark('$what: ${s.elapsedMilliseconds} мс');
    }
  }

  /// Следит за медленными кадрами и за «зависаниями» главного потока Dart.
  static void startWatching() {
    if (_watching) return;
    _watching = true;
    mark('запуск журнала');
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final total = t.totalSpan.inMilliseconds;
        if (total >= 100) {
          mark('медленный кадр $total мс (построение ${t.buildDuration.inMilliseconds}, '
              'отрисовка ${t.rasterDuration.inMilliseconds})');
        }
      }
    });
    // Если поток занят и таймер сработал с большим опозданием, значит, интерфейс стоял.
    var last = _sw.elapsedMilliseconds;
    Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = _sw.elapsedMilliseconds;
      final gap = now - last;
      last = now;
      if (gap >= 200) mark('поток занят: пауза $gap мс');
    });
  }

  static String dump() =>
      _lines.isEmpty ? 'Журнал пуст' : _lines.join('\n');
}
