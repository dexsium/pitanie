import '../domain/models/health_models.dart';

/// Проверка качества измерений. Недостоверные значения в анализ не попадают.
bool validHeartRate(double bpm) => bpm >= 30 && bpm <= 220;

/// SpO₂ ниже 70 % или выше 100 % для часов — почти наверняка ошибка датчика.
bool validSpo2(double v) => v >= 70 && v <= 100;

List<Sample> cleanHeartRate(Iterable<Sample> s) => [
      for (final x in s)
        if (validHeartRate(x.v)) x
    ];

List<Sample> cleanSpo2(Iterable<Sample> s) => [
      for (final x in s)
        if (validSpo2(x.v)) x
    ];
