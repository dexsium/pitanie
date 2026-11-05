// Архив сырых данных, которые отдали часы. Нужен, чтобы прочитанное не пропадало зря: часы
// отдают некоторые потоки (например, 0x2c) один раз, повторно они приходят пустыми.
// Архив лежит в папке приложения одним текстовым файлом: время|тип|байт|пометка|hex.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'huami_fetch.dart';

const _maxFileBytes = 4 * 1024 * 1024;

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Короткое описание содержимого для журнала и отчёта.
List<String> describeRaw(int type, Uint8List data) {
  final head =
      data.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  switch (type) {
    case 0x2c:
      return summarizeEvents(data);
    case 0x3b:
      return ['protobuf: ${dumpProtobuf(data)}'];
    default:
      return ['начало: $head'];
  }
}

class WatchArchive {
  static Future<File> file() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/watch_raw');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/archive.txt');
  }

  /// Добавляет блок в архив. При превышении размера отбрасывается старая половина.
  static Future<void> add(int type, Uint8List data, {String? note}) async {
    if (data.isEmpty) return;
    final f = await file();
    final line =
        '${DateTime.now().toIso8601String()}|0x${type.toRadixString(16)}|${data.length}|${note ?? ''}|${_hex(data)}\n';
    await f.writeAsString(line, mode: FileMode.append, flush: true);
    if (await f.length() > _maxFileBytes) {
      final lines = await f.readAsLines();
      await f.writeAsString('${lines.sublist(lines.length ~/ 2).join('\n')}\n');
    }
  }

  /// Отчёт: по каждой записи — сводка; сырые байты только у небольших блоков.
  static Future<String> report(
      {int rawLimit = 3000, int maxChars = 120000}) async {
    final f = await file();
    if (!await f.exists()) return 'Архив пуст.';
    final out = StringBuffer();
    for (final line in await f.readAsLines()) {
      final p = line.split('|');
      if (p.length < 5) continue;
      final type = int.tryParse(p[1].substring(2), radix: 16) ?? 0;
      final data = _unhex(p[4]);
      out.writeln('${p[0]} тип ${p[1]} ${p[2]} байт ${p[3]}');
      for (final l in describeRaw(type, data)) {
        out.writeln('  $l');
      }
      if (data.length <= rawLimit) {
        out.writeln('  hex: ${_hex(data)}');
      } else if (type == 0x2c) {
        out.writeln('  hex (начало 600 байт): ${_hex(data.sublist(0, 600))}');
      }
    }
    final s = out.toString();
    return s.length > maxChars ? s.substring(s.length - maxChars) : s;
  }
}
