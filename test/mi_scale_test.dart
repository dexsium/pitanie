import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/scale/mi_scale.dart';

// Пакеты собраны вручную по описанному формату (ESPHome xiaomi_miscale, 0x181B, 13 байт):
// тесты проверяют разбор, а не поведение реальных весов.
List<int> packet({int unit = 0x02, int flags = 0x22, int imp = 500, required int raw}) => [
      unit, flags, 0xEA, 0x07, 11, 4, 9, 30, 15, //
      imp & 0xFF, imp >> 8, raw & 0xFF, raw >> 8,
    ];

void main() {
  test('вес в кг: значение / 200', () {
    final r = parseMiScale2(packet(raw: 14000))!; // 70,00 кг
    expect(r.weightKg, 70.0);
    expect(r.isFinal, isTrue);
    expect(r.impedance, 500);
  });
  test('фунты пересчитываются в кг', () {
    final r = parseMiScale2(packet(unit: 0x03, raw: 15432))!; // 154,32 фунта
    expect(r.weightKg, closeTo(70.0, 0.01));
  });
  test('нестабильный вес и снятая нагрузка не считаются итоговыми', () {
    expect(parseMiScale2(packet(flags: 0x02, raw: 14000))!.isFinal, isFalse);
    expect(parseMiScale2(packet(flags: 0xA2, raw: 14000))!.isFinal, isFalse);
  });
  test('чужие и неправдоподобные пакеты отклоняются', () {
    expect(parseMiScale2([1, 2, 3]), isNull);
    expect(parseMiScale2(packet(unit: 0x55, raw: 14000)), isNull);
    expect(parseMiScale2(packet(raw: 100)), isNull); // 0,5 кг
    expect(parseMiScale2(packet(raw: 60000)), isNull); // 300 кг
  });
  test('метка времени одинакова у повторов и различается у разных взвешиваний', () {
    final a = parseMiScale2(packet(raw: 14000))!;
    final b = parseMiScale2(packet(raw: 14010))!;
    expect(a.stamp, b.stamp);
    final c = parseMiScale2([...packet(raw: 14000)]..[8] = 16)!;
    expect(c.stamp, isNot(a.stamp));
  });
}
