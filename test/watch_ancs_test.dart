import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/watch_ancs.dart';

void main() {
  test('разбор статуса ANCS', () {
    AncsState s(Map m) => parseAncsStatus(m).state;
    expect(s({'state': 'poweredOn', 'found': true, 'ancsAuthorized': true}),
        AncsState.authorized);
    expect(s({'state': 'poweredOn', 'found': true, 'ancsAuthorized': false}),
        AncsState.denied);
    expect(s({'state': 'poweredOn', 'found': false}), AncsState.watchNotFound);
    expect(s({'state': 'poweredOn', 'found': true}), AncsState.unknown);
    expect(s({'state': 'poweredOff'}), AncsState.bluetoothOff);
    expect(s({'state': 'unauthorized'}), AncsState.noBluetoothAccess);
    expect(s({'state': 'timeout'}), AncsState.unknown);
    expect(parseAncsStatus(null).state, AncsState.unknown);
  });
}
