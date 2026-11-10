import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/dashboard/day_data.dart';

void main() {
  test('основной источник: всегда автоматический выбор', () {
    expect(mainSourceOf({}), isNull);
    expect(mainSourceOf({kMainSourceKey: 'ble'}), isNull);
    expect(mainSourceOf({kMainSourceKey: 'com.huawei.health'}), isNull);
  });
}
