import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/scale/scale_driver.dart';
import 'package:pitanie/features/scale/standard_scale.dart';

List<int> u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

void main() {
  group('Weight Measurement 0x2A9D', () {
    test('килограммы: 70,5 кг = 14100 × 0,005', () {
      final m = parseWeightMeasurement([0x00, ...u16(14100)])!;
      expect(m.weightKg, closeTo(70.5, 1e-6));
      expect(m.bodyFatPct, isNull);
    });
    test('фунты: 155,00 lb = 15500 × 0,01', () {
      final m = parseWeightMeasurement([0x01, ...u16(15500)])!;
      expect(m.weightKg, closeTo(70.307, 0.01));
    });
    test('время и пользователь читаются в порядке флагов', () {
      final m = parseWeightMeasurement([
        0x06, ...u16(14000), // время + пользователь
        ...u16(2026), 11, 10, 8, 30, 15,
        2,
      ])!;
      expect(m.weightKg, closeTo(70.0, 1e-6));
      expect(m.deviceTime, DateTime(2026, 11, 10, 8, 30, 15));
      expect(m.userId, 2);
    });
    test('неудачное измерение (0xFFFF), короткий и нелепый пакеты отбрасываются', () {
      expect(parseWeightMeasurement([0x00, 0xFF, 0xFF]), isNull);
      expect(parseWeightMeasurement([0x00, 0x01]), isNull);
      expect(parseWeightMeasurement([0x00, ...u16(10)]), isNull); // 0,05 кг
      expect(parseWeightMeasurement([0x02, ...u16(14000)]), isNull); // время заявлено, байт нет
    });
  });

  group('Body Composition Measurement 0x2A9C', () {
    test('жир, мышцы, вода, импеданс и вес в порядке флагов', () {
      // флаги: мышечная масса(5) + вода(8) + импеданс(9) + вес(10)
      final flags = (1 << 5) | (1 << 8) | (1 << 9) | (1 << 10);
      final m = parseBodyComposition([
        ...u16(flags),
        ...u16(215), // жир 21,5 %
        ...u16(7600), // мышечная масса 38,0 кг
        ...u16(9000), // вода 45,0 кг
        ...u16(4850), // импеданс 485,0 Ом
        ...u16(14100), // вес 70,5 кг
      ])!;
      expect(m.bodyFatPct, 21.5);
      expect(m.muscleMassKg, 38.0);
      expect(m.bodyWaterKg, 45.0);
      expect(m.impedanceOhm, 485.0);
      expect(m.weightKg, 70.5);
      expect(m.hasComposition, isTrue);
    });
    test('обмен веществ в кДж переводится в ккал, процент мышц читается', () {
      final flags = (1 << 3) | (1 << 4);
      final m = parseBodyComposition([...u16(flags), ...u16(180), ...u16(7531), ...u16(412)])!;
      expect(m.bmrKcal, closeTo(1800, 1));
      expect(m.musclePct, 41.2);
    });
    test('недоступные значения (0xFFFF) остаются пустыми, а не нулями', () {
      final flags = (1 << 5);
      final m = parseBodyComposition([...u16(flags), ...u16(0xFFFF), ...u16(0xFFFF)]);
      expect(m, isNull);
      final m2 = parseBodyComposition([...u16(flags), ...u16(200), ...u16(0xFFFF)])!;
      expect(m2.bodyFatPct, 20.0);
      expect(m2.muscleMassKg, isNull);
    });
    test('пакет из нескольких частей и обрезанный пакет не разбираются', () {
      expect(parseBodyComposition([...u16(0x1000), ...u16(200)]), isNull);
      expect(parseBodyComposition([...u16(1 << 10), ...u16(200)]), isNull);
    });
  });

  test('вес и состав одного взвешивания объединяются, значения не теряются', () {
    final w = parseWeightMeasurement([0x00, ...u16(14100)])!;
    final c = parseBodyComposition([...u16(0), ...u16(215)])!;
    final m = w.merge(c);
    expect(m.weightKg, 70.5);
    expect(m.bodyFatPct, 21.5);
    expect(c.merge(w).weightKg, 70.5);
  });

  group('выбор драйвера', () {
    test('Mi Scale 2 (13 байт в 0x181B) — рекламный драйвер, проверенный', () {
      final a = ScaleAdvert('MIBFS', {}, {'181b': List.filled(13, 0)});
      final d = driverFor(a)!;
      expect(d.id, 'mi_scale2');
      expect(d.verified, isTrue);
      expect(d.transport, ScaleTransport.advertising);
    });
    test('весы с объявленным 0x181D — стандартный драйвер, непроверенный', () {
      final d = driverFor(const ScaleAdvert('Scale', {'181d'}, {}))!;
      expect(d.id, 'gatt_standard');
      expect(d.verified, isFalse);
      expect(d.transport, ScaleTransport.gatt);
    });
    test('0x181B без 13-байтных данных — тоже стандартный драйвер', () {
      expect(driverFor(const ScaleAdvert('X', {'181b'}, {}))?.id, 'gatt_standard');
    });
    test('неизвестное устройство не считается весами', () {
      expect(driverFor(const ScaleAdvert('Watch', {'180d'}, {})), isNull);
    });
    test('полный UUID приводится к короткому', () {
      expect(shortUuid('0000181D-0000-1000-8000-00805F9B34FB'), '181d');
      expect(shortUuid('6e400001-b5a3-f393-e0a9-e50e24dcca9e'),
          '6e400001-b5a3-f393-e0a9-e50e24dcca9e');
    });
  });
}
