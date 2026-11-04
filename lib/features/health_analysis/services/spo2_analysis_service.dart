import '../domain/models/health_models.dart';
import 'health_data_quality_service.dart';

enum Spo2Level { normal, repeatMeasure, repeatedLow, repeatedVeryLow }

class Spo2Analysis {
  final Spo2Level level;
  final Sample? latest;
  final int valid;
  final int rejected; // отброшено как недостоверные
  final int lowCount;
  final String note;
  const Spo2Analysis(this.level, this.latest, this.valid, this.rejected,
      this.lowCount, this.note);
}

const kSpo2Low = 92.0;
const kSpo2VeryLow = 88.0;

/// SpO₂ по часам зависит от движения, посадки и датчика, поэтому вывод по одному измерению не
/// делается. Одиночное низкое — только предложение повторить измерение. Повторные низкие:
/// не менее 3 значений ниже 92 % за 3 суток, разнесённых минимум на час. Повторные очень низкие:
/// не менее 3 значений ≤ 88 % за 24 часа.
Spo2Analysis analyzeSpo2(List<Sample> raw, DateTime now) {
  final valid = cleanSpo2(raw).toList()..sort((a, b) => a.at.compareTo(b.at));
  final rejected = raw.length - valid.length;
  if (valid.isEmpty) {
    return Spo2Analysis(
        Spo2Level.normal, null, 0, rejected, 0, 'Нет достоверных измерений.');
  }
  List<Sample> spaced(List<Sample> s) {
    final out = <Sample>[];
    for (final x in s) {
      if (out.isEmpty || x.at.difference(out.last.at).inMinutes >= 60)
        out.add(x);
    }
    return out;
  }

  final d3 = valid
      .where((s) => now.difference(s.at).inHours <= 72 && s.v < kSpo2Low)
      .toList();
  final d1vl = valid
      .where((s) => now.difference(s.at).inHours <= 24 && s.v <= kSpo2VeryLow)
      .toList();
  final low3 = spaced(d3);
  final vlow = spaced(d1vl);
  final latest = valid.last;
  if (vlow.length >= 3) {
    return Spo2Analysis(Spo2Level.repeatedVeryLow, latest, valid.length,
        rejected, vlow.length, 'Повторные очень низкие значения');
  }
  if (low3.length >= 3) {
    return Spo2Analysis(Spo2Level.repeatedLow, latest, valid.length, rejected,
        low3.length, 'Повторные низкие значения');
  }
  final recentLow = latest.v < kSpo2Low &&
      now.difference(latest.at).inHours <= 24 &&
      low3.length < 2;
  if (recentLow) {
    return Spo2Analysis(Spo2Level.repeatMeasure, latest, valid.length, rejected,
        low3.length, 'Одиночное низкое значение: повторите измерение');
  }
  return Spo2Analysis(Spo2Level.normal, latest, valid.length, rejected,
      low3.length, 'Без отклонений');
}
