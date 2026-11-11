// Драйверы умных весов. Приложение не заявляет поддержку моделей, которые не проверены:
// у каждого драйвера есть признак `verified`.
//
//  * Mi Body Composition Scale 2 (XMTZC05HM): данные в рекламных пакетах, проверено на устройстве.
//  * Стандартные сервисы Bluetooth SIG (Weight Scale 0x181D, Body Composition 0x181B с
//    подключением): разбор написан по спецификации и проверен тестами на собранных пакетах,
//    но на реальных весах не проверялся, поэтому помечен как непроверенный.

/// Одно измерение, полученное любым драйвером. Отсутствующие показатели остаются null:
/// ничего не выдумывается и не подставляется.
class ScaleMeasurement {
  final double? weightKg;
  final double? impedanceOhm;
  final double? bodyFatPct;
  final double? fatFreeKg;
  final double? muscleMassKg;
  final double? musclePct;
  final double? bodyWaterKg;
  final double? bmrKcal;

  /// Время, переданное весами (часы весов часто не выставлены, поэтому используется редко).
  final DateTime? deviceTime;
  final int? userId;
  const ScaleMeasurement(
      {this.weightKg,
      this.impedanceOhm,
      this.bodyFatPct,
      this.fatFreeKg,
      this.muscleMassKg,
      this.musclePct,
      this.bodyWaterKg,
      this.bmrKcal,
      this.deviceTime,
      this.userId});

  static const empty = ScaleMeasurement();

  bool get hasComposition =>
      bodyFatPct != null ||
      fatFreeKg != null ||
      muscleMassKg != null ||
      musclePct != null ||
      bodyWaterKg != null;

  /// Объединяет два пакета одного взвешивания (вес из одного сервиса, состав из другого).
  /// Непустые значения нового пакета заменяют прежние.
  ScaleMeasurement merge(ScaleMeasurement o) => ScaleMeasurement(
        weightKg: o.weightKg ?? weightKg,
        impedanceOhm: o.impedanceOhm ?? impedanceOhm,
        bodyFatPct: o.bodyFatPct ?? bodyFatPct,
        fatFreeKg: o.fatFreeKg ?? fatFreeKg,
        muscleMassKg: o.muscleMassKg ?? muscleMassKg,
        musclePct: o.musclePct ?? musclePct,
        bodyWaterKg: o.bodyWaterKg ?? bodyWaterKg,
        bmrKcal: o.bmrKcal ?? bmrKcal,
        deviceTime: o.deviceTime ?? deviceTime,
        userId: o.userId ?? userId,
      );
}

/// Что видно в эфире про устройство: достаточно, чтобы выбрать драйвер без подключения.
class ScaleAdvert {
  final String name;

  /// Короткие (16 бит, строчные) или полные UUID объявленных сервисов.
  final Set<String> serviceUuids;

  /// Данные сервисов в рекламе, ключ как в [serviceUuids].
  final Map<String, List<int>> serviceData;
  const ScaleAdvert(this.name, this.serviceUuids, this.serviceData);
}

enum ScaleTransport { advertising, gatt }

abstract class ScaleDriver {
  const ScaleDriver();
  String get id;
  String get title;

  /// Проверен ли драйвер на реальных весах. Непроверенные помечаются в интерфейсе.
  bool get verified;
  ScaleTransport get transport;

  /// Подходит ли устройство по рекламным данным.
  bool matches(ScaleAdvert a);
}

const kWeightScaleService = '181d';
const kBodyCompositionService = '181b';
const kWeightMeasurementChar = '2a9d';
const kBodyCompositionChar = '2a9c';

/// Mi Body Composition Scale 2: вес в данных сервиса 0x181B (13 байт), подключение не нужно.
class MiScale2Driver extends ScaleDriver {
  const MiScale2Driver();
  @override
  String get id => 'mi_scale2';
  @override
  String get title => 'Mi Body Composition Scale 2';
  @override
  bool get verified => true;
  @override
  ScaleTransport get transport => ScaleTransport.advertising;
  @override
  bool matches(ScaleAdvert a) => a.serviceData[kBodyCompositionService]?.length == 13;
}

/// Весы со стандартными сервисами Bluetooth SIG, требующие подключения.
/// Не включает Mi Scale 2: у неё данные в рекламе, а не в характеристиках.
class StandardGattScaleDriver extends ScaleDriver {
  const StandardGattScaleDriver();
  @override
  String get id => 'gatt_standard';
  @override
  String get title => 'Весы со стандартным Bluetooth (0x181D / 0x181B)';
  @override
  bool get verified => false;
  @override
  ScaleTransport get transport => ScaleTransport.gatt;
  @override
  bool matches(ScaleAdvert a) {
    if (a.serviceData[kBodyCompositionService]?.length == 13) return false; // это Mi Scale 2
    return a.serviceUuids.contains(kWeightScaleService) ||
        a.serviceUuids.contains(kBodyCompositionService);
  }
}

const List<ScaleDriver> kScaleDrivers = [MiScale2Driver(), StandardGattScaleDriver()];

/// Драйвер для устройства по рекламным данным; null — устройство не распознано как весы.
ScaleDriver? driverFor(ScaleAdvert a) {
  for (final d in kScaleDrivers) {
    if (d.matches(a)) return d;
  }
  return null;
}

/// 16-битный UUID из полного вида 0000xxxx-0000-1000-8000-00805f9b34fb; иначе строка как есть.
String shortUuid(String u) {
  final s = u.toLowerCase();
  if (s.length == 36 && s.startsWith('0000') && s.endsWith('-0000-1000-8000-00805f9b34fb')) {
    return s.substring(4, 8);
  }
  return s;
}
