import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/dashboard/day_data.dart';
import 'package:pitanie/features/sleep/sleep_data.dart';

ActivityRecord rec(String type, DateTime a, DateTime b, String source) => ActivityRecord(
    id: 0,
    type: type,
    startTime: a,
    endTime: b,
    value: b.difference(a).inMinutes.toDouble(),
    unit: 'min',
    source: source,
    sourceName: source,
    externalRecordId: '$type$a',
    tzOffsetMin: 0,
    platform: '',
    origin: '');

void main() {
  test('сон из Здоровья: запись-интервал превращается в минуты, фазы считаются сном', () {
    final s = DateTime(2026, 11, 9, 23);
    final recs = [
      rec('sleepLight', s, s.add(const Duration(minutes: 120)), 'health'),
      rec('sleepDeep', s.add(const Duration(minutes: 120)), s.add(const Duration(minutes: 200)), 'health'),
      rec('sleepRem', s.add(const Duration(minutes: 200)), s.add(const Duration(minutes: 260)), 'health'),
    ];
    final r = sleepSessions(recs).single;
    expect(r.sleepMin, 260);
    expect(r.deepMin, 80);
    expect(r.remMin, 60);
    expect(r.lightMin, 120);
  });

  test('singleSource берёт источник с большим числом записей', () {
    final t = DateTime(2026, 11, 10, 8);
    final a = [
      for (var i = 0; i < 3; i++)
        rec('heartRate', t.add(Duration(minutes: i)), t.add(Duration(minutes: i + 1)), 'zepp'),
      rec('heartRate', t, t.add(const Duration(minutes: 1)), 'other'),
    ];
    expect(singleSource(a).every((r) => r.source == 'zepp'), true);
    expect(singleSource(a), hasLength(3));
  });
}
