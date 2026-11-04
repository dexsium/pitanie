// Разбор рекламного пакета Mi Body Composition Scale 2 (XMTZC05HM): вес передаётся в данных
// сервиса 0x181B (13 байт), привязка не нужна. Формат взят из исходников ESPHome
// (xiaomi_miscale) и openScale (оба открытые); на реальных весах проверяется журналом.

class MiScaleReading {
  final double weightKg;
  final int? impedance;
  final bool stabilized, loadRemoved;

  /// Байты 2–8 пакета (часы весов): по ним отличаем одно взвешивание от повторов пакета.
  final String stamp;
  const MiScaleReading(this.weightKg, this.impedance, this.stabilized, this.loadRemoved, this.stamp);

  /// Взвешивание завершено: вес стабилен и человек ещё стоит на весах.
  bool get isFinal => stabilized && !loadRemoved;
}

/// Возвращает null, если пакет не похож на данные весов (длина, единица, разумный вес).
MiScaleReading? parseMiScale2(List<int> d) {
  if (d.length != 13) return null;
  final flags = d[1];
  final hasImpedance = flags & 0x02 != 0;
  final stabilized = flags & 0x20 != 0;
  final loadRemoved = flags & 0x80 != 0;
  final raw = d[11] | (d[12] << 8);
  final double kg;
  switch (d[0]) {
    case 0x02: // килограммы: шаг 0,005 кг
      kg = raw * 0.01 / 2;
    case 0x03: // фунты: шаг 0,01 фунта
      kg = raw * 0.01 * 0.453592;
    default:
      return null;
  }
  if (kg < 5 || kg > 250) return null;
  int? imp;
  if (hasImpedance) {
    final v = d[9] | (d[10] << 8);
    if (v > 0 && v < 3000) imp = v;
  }
  final stamp = d.sublist(2, 9).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return MiScaleReading(double.parse(kg.toStringAsFixed(2)), imp, stabilized, loadRemoved, stamp);
}
