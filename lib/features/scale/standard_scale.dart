// Разбор стандартных характеристик Bluetooth SIG (Weight Scale Service 0x181D и Body Composition
// Service 0x181B). Форматы взяты из спецификаций GATT: Weight Measurement (0x2A9D) и Body
// Composition Measurement (0x2A9C). На реальных весах не проверялся.
import 'scale_driver.dart';

class _Reader {
  final List<int> d;
  int i = 0;
  _Reader(this.d);
  bool has(int n) => i + n <= d.length;
  int u8() => d[i++];
  int u16() {
    final v = d[i] | (d[i + 1] << 8);
    i += 2;
    return v;
  }
}

/// 0xFFFF и близкие значения — «не число» / «измерение не удалось» по спецификации.
bool _invalid(int v) => v >= 0xFFFE;

DateTime? _timestamp(_Reader r) {
  if (!r.has(7)) return null;
  final y = r.u16(), mo = r.u8(), d = r.u8(), h = r.u8(), mi = r.u8(), s = r.u8();
  if (y < 2000 || mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 59) return null;
  return DateTime(y, mo, d, h, mi, s);
}

double _mass(int raw, bool imperial) =>
    imperial ? raw * 0.01 * 0.45359237 : raw * 0.005;

bool _plausibleKg(double kg) => kg >= 2 && kg <= 400;

/// Weight Measurement (0x2A9D). Возвращает null для неполного пакета или неудачного измерения.
ScaleMeasurement? parseWeightMeasurement(List<int> data) {
  if (data.length < 3) return null;
  final r = _Reader(data);
  final flags = r.u8();
  final imperial = flags & 0x01 != 0;
  final raw = r.u16();
  if (_invalid(raw)) return null;
  final kg = _mass(raw, imperial);
  if (!_plausibleKg(kg)) return null;
  DateTime? ts;
  int? user;
  if (flags & 0x02 != 0) {
    if (!r.has(7)) return null;
    ts = _timestamp(r);
  }
  if (flags & 0x04 != 0) {
    if (!r.has(1)) return null;
    final u = r.u8();
    user = u == 0xFF ? null : u;
  }
  return ScaleMeasurement(
      weightKg: double.parse(kg.toStringAsFixed(3)), deviceTime: ts, userId: user);
}

/// Body Composition Measurement (0x2A9C). Поля идут в порядке битов флагов; процент жира
/// присутствует всегда. Пакеты из нескольких частей (бит 12) не поддерживаются.
ScaleMeasurement? parseBodyComposition(List<int> data) {
  if (data.length < 4) return null;
  final r = _Reader(data);
  final flags = r.u16();
  if (flags & 0x1000 != 0) return null;
  final imperial = flags & 0x0001 != 0;
  final fatRaw = r.u16();
  double? fat = _invalid(fatRaw) ? null : fatRaw * 0.1;
  if (fat != null && (fat < 1 || fat > 80)) fat = null;

  DateTime? ts;
  int? user;
  double? bmr, musclePct, muscleKg, fatFree, water, imp, weight;

  double? takeMass() {
    if (!r.has(2)) return null;
    final v = r.u16();
    if (_invalid(v)) return null;
    final kg = _mass(v, imperial);
    return _plausibleKg(kg) || kg > 0 ? kg : null;
  }

  if (flags & 0x0002 != 0) ts = _timestamp(r);
  if (flags & 0x0004 != 0) {
    if (!r.has(1)) return null;
    final u = r.u8();
    user = u == 0xFF ? null : u;
  }
  if (flags & 0x0008 != 0) {
    if (!r.has(2)) return null;
    final v = r.u16();
    if (!_invalid(v)) bmr = v / 4.184; // кДж → ккал
  }
  if (flags & 0x0010 != 0) {
    if (!r.has(2)) return null;
    final v = r.u16();
    if (!_invalid(v)) musclePct = v * 0.1;
  }
  if (flags & 0x0020 != 0) muscleKg = takeMass();
  if (flags & 0x0040 != 0) fatFree = takeMass();
  if (flags & 0x0080 != 0) takeMass(); // мягкая тощая масса: не используется
  if (flags & 0x0100 != 0) water = takeMass();
  if (flags & 0x0200 != 0) {
    if (!r.has(2)) return null;
    final v = r.u16();
    if (!_invalid(v)) imp = v * 0.1;
  }
  if (flags & 0x0400 != 0) {
    if (!r.has(2)) return null;
    final v = r.u16();
    if (!_invalid(v)) {
      final kg = _mass(v, imperial);
      weight = _plausibleKg(kg) ? kg : null;
    }
  }
  if (fat == null &&
      bmr == null &&
      musclePct == null &&
      muscleKg == null &&
      fatFree == null &&
      water == null &&
      imp == null &&
      weight == null) {
    return null;
  }
  double? r2(double? v) => v == null ? null : double.parse(v.toStringAsFixed(2));
  return ScaleMeasurement(
    weightKg: r2(weight),
    impedanceOhm: r2(imp),
    bodyFatPct: r2(fat),
    fatFreeKg: r2(fatFree),
    muscleMassKg: r2(muscleKg),
    musclePct: r2(musclePct),
    bodyWaterKg: r2(water),
    bmrKcal: r2(bmr),
    deviceTime: ts,
    userId: user,
  );
}

/// Разбор значения характеристики по её 16-битному UUID; null, если характеристика не наша.
ScaleMeasurement? parseCharacteristic(String shortUuidValue, List<int> data) =>
    switch (shortUuidValue) {
      kWeightMeasurementChar => parseWeightMeasurement(data),
      kBodyCompositionChar => parseBodyComposition(data),
      _ => null,
    };
