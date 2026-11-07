import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/heart_zones.dart';

void main() {
  test('зоны макс. пульса совпадают со скриншотом Zepp (макс. 185)', () {
    final z = hrZones(185);
    expect(z.map((e) => (e.from, e.to)), [
      (92, 110),
      (111, 128),
      (129, 147),
      (148, 165),
      (166, 185),
    ]);
    expect(z.first.name, 'Легкая активность');
    expect(z.last.name, 'МПК');
    expect((z.first.pctFrom, z.first.pctTo), (50, 59));
    expect((z.last.pctFrom, z.last.pctTo), (90, 100));
  });

  test('максимальный пульс по возрасту', () {
    expect(maxHeartRate(35), 185);
  });

  test('зоны по запасу пульса (Карвонен): покой 60, макс. 185', () {
    final z = hrZones(185, resting: 60);
    // 60 + 50% от 125 = 122, 60 + 60% = 135, 70% = 147, 80% = 160, 90% = 172
    expect(z.map((e) => (e.from, e.to)), [
      (122, 134),
      (135, 146),
      (147, 159),
      (160, 171),
      (172, 185),
    ]);
  });

  test('зона для пульса', () {
    final z = hrZones(185);
    expect(zoneFor(z, 91), isNull);
    expect(zoneFor(z, 92)!.name, 'Легкая активность');
    expect(zoneFor(z, 128)!.name, 'Сжигание жира');
    expect(zoneFor(z, 190)!.name, 'МПК');
  });
}
