import 'package:intl/intl.dart';

/// Ключ локального дня вида 2025-01-24. Сутки считаются по локальному времени.
String dayKey(DateTime d) {
  final l = d.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-'
      '${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime dayEnd(DateTime d) => DateTime(d.year, d.month, d.day + 1);

DateTime parseDayKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int tzOffsetMinutes([DateTime? at]) =>
    (at ?? DateTime.now()).timeZoneOffset.inMinutes;

String fmt0(num v) => NumberFormat('#,##0', 'ru').format(v.round());
String fmt1(num v) => NumberFormat('#,##0.0', 'ru').format(v);

/// Граммы и т. п.: целое без дробной части, иначе один знак.
String fmtAuto(num v) =>
    (v - v.roundToDouble()).abs() < 0.05 ? fmt0(v) : fmt1(v);

String fmtTime(DateTime d) => DateFormat('HH:mm').format(d.toLocal());

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String dayTitle(DateTime d) {
  final today = dayStart(DateTime.now());
  final diff = dayStart(d).difference(today).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == -1) return 'Вчера';
  if (diff == 1) return 'Завтра';
  return _cap(DateFormat('EEEE', 'ru').format(d));
}

String dayDateLine(DateTime d) =>
    _cap(DateFormat('E, d MMMM', 'ru').format(d));

String fullDate(DateTime d) => DateFormat('d MMMM yyyy', 'ru').format(d);
String shortDate(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

double? parseNum(String? s) {
  if (s == null) return null;
  return double.tryParse(s.trim().replaceAll(',', '.').replaceAll(' ', ''));
}
