import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/dashboard/day_data.dart';

void main() {
  test('основной источник: по умолчанию автоматический, выбранный применяется', () {
    expect(mainSourceOf({}), isNull);
    expect(mainSourceOf({kMainSourceKey: 'auto'}), isNull);
    expect(mainSourceOf({kMainSourceKey: 'ble'}), isNull);
    expect(mainSourceOf({kMainSourceKey: 'com.huawei.health'}), 'com.huawei.health');
  });
}
