import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/dashboard/day_data.dart';

void main() {
  test('основной источник: по умолчанию Bluetooth, auto — без предпочтения', () {
    expect(mainSourceOf({}), kBleSource);
    expect(mainSourceOf({kMainSourceKey: 'ble'}), kBleSource);
    expect(mainSourceOf({kMainSourceKey: 'auto'}), isNull);
    expect(mainSourceOf({kMainSourceKey: 'com.huawei.health'}),
        'com.huawei.health');
  });
}
