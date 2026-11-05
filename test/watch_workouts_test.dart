import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/watch_workouts.dart';

Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);

// Реальная сводка тренировки с Amazfit GTR 4 (тип 0x05, прошивка 7.6.0.2).
const real =
    '00800a03322e31120c0895e0b0d7061000183068451a04083410003a0808c80310c803200082010208359a01070873108c011860aa010e0801259a99993f2dcdcccc3d3007b201180801120a5c6f81019401a601b9011a08009601fe01200000';

void main() {
  test(
      'разбор реальной сводки: время, длительность и пульс сошлись с подробностями',
      () {
    final w = parseWatchWorkout(hex(real), now: DateTime(2026, 11, 6));
    expect(w, isNotNull);
    expect(w!.start.toUtc(), DateTime.utc(2026, 11, 5, 7, 28, 21));
    expect(w.durationSec, 456);
    expect(w.avgHr, 115);
    expect(w.maxHr, 140);
    expect(w.minHr, 96);
    expect(w.externalId, 'ble-wk-1793863701');
    expect(w.typeCode, 48);
    expect(watchWorkoutType(w.typeCode), 'STRENGTH_TRAINING');
    expect(watchWorkoutType(7), 'WATCH_ACTIVITY');
    expect(watchWorkoutType(null), 'WATCH_ACTIVITY');
  });

  test('мусор и обрыв не превращаются в тренировку', () {
    expect(parseWatchWorkout(Uint8List(0)), isNull);
    expect(parseWatchWorkout(hex('0080ffffffffffffff')), isNull);
    expect(
        parseWatchWorkout(hex(real.substring(0, 60)),
            now: DateTime(2026, 11, 6)),
        isNull);
  });

  test('неправдоподобные значения отбрасываются', () {
    // Дата в далёком будущем относительно «сейчас».
    expect(parseWatchWorkout(hex(real), now: DateTime(2024, 1, 1)), isNull);
  });
}
