// Зоны пульса: два типа, как в приложении Zepp.
//
// «Зона макс. пульса»: проценты от максимального пульса (220 − возраст).
// «Зарезервированная зона» (по запасу пульса): пульс покоя + проценты от (макс. − покой),
// формула Карвонена. Границы зон по максимальному пульсу сверены со скриншотом Zepp
// (макс. 185: 92–110, 111–128, 129–147, 148–165, 166–185). Границы по запасу пульса в Zepp
// не сверялись: применены те же полосы 50–100 %.

enum ZoneType { maxHr, reserve }

class HrZone {
  final String name;
  final int from, to;
  final int pctFrom, pctTo;
  const HrZone(this.name, this.from, this.to, this.pctFrom, this.pctTo);
}

const _names = [
  'Легкая активность',
  'Сжигание жира',
  'Аэробная',
  'Анаэробная',
  'МПК',
];
const _pct = [50, 60, 70, 80, 90];

/// Максимальный пульс по возрастной формуле.
int maxHeartRate(int age) => 220 - age;

/// Границы: нижняя — целая часть (без округления вверх), верхняя — на единицу меньше нижней
/// следующей зоны, у последней — максимум. Целочисленный счёт исключает ошибки округления.
List<HrZone> hrZones(int maxHr, {int? resting}) {
  final base = resting ?? 0;
  final span = maxHr - base;
  int low(int pct) => base + (pct * span) ~/ 100;
  final lows = [for (final p in _pct) low(p)];
  return [
    for (var i = 0; i < _pct.length; i++)
      HrZone(
        _names[i],
        lows[i],
        i == _pct.length - 1 ? maxHr : lows[i + 1] - 1,
        _pct[i],
        i == _pct.length - 1 ? 100 : _pct[i + 1] - 1,
      ),
  ];
}

/// Зона для пульса `bpm`; null, если пульс ниже первой зоны.
HrZone? zoneFor(List<HrZone> zones, int bpm) {
  for (final z in zones.reversed) {
    if (bpm >= z.from) return z;
  }
  return null;
}
