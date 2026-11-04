import 'dart:math' as math;

/// Индивидуальная базовая линия: медиана и устойчивая оценка разброса (MAD × 1,4826).
class Baseline {
  final double median, spread;
  final int n;
  const Baseline(this.median, this.spread, this.n);
}

double medianOf(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  if (n == 0) return double.nan;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double meanOf(List<double> v) => v.reduce((a, b) => a + b) / v.length;

/// Null, если достоверных значений меньше [minN].
Baseline? buildBaseline(List<double> values, {int minN = 14}) {
  if (values.length < minN) return null;
  final m = medianOf(values);
  final mad = medianOf([for (final x in values) (x - m).abs()]) * 1.4826;
  return Baseline(m, mad, values.length);
}

double stdDev(List<double> v) {
  if (v.length < 2) return 0;
  final m = meanOf(v);
  return math.sqrt(
      v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (v.length - 1));
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
