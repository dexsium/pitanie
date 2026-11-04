// Расчёт состава тела по весу, росту, возрасту, полу и импедансу (сопротивление тела).
//
// Весы Mi Body Composition Scale 2 передают только вес и импеданс; жир, воду, мышцы и прочее
// считает приложение. Формулы ниже — восстановленные из Mi Fit / Amazfit алгоритмы проекта
// xiaomi_mi_scale (https://github.com/lolouk44/xiaomi_mi_scale, лицензия MIT, см. NOTICE.md),
// переписанные на Dart. Это ОЦЕНКА: значения могут отличаться от приложения Zepp и не являются
// медицинскими измерениями.
import 'dart:math' as math;

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

class BodyInput {
  final double weight, height, impedance;
  final int age;
  final bool female;
  const BodyInput(
      {required this.weight,
      required this.height,
      required this.age,
      required this.female,
      required this.impedance});

  /// Входные данные в пределах, для которых формулы вообще применимы.
  bool get valid =>
      height > 90 && height <= 220 && weight >= 10 && weight <= 200 && age >= 5 && age <= 99 &&
      impedance > 0 && impedance <= 3000;
}

/// Диапазон нормы показателя и положение значения относительно него.
enum Level { low, normal, high }

class Range {
  final double lo, hi;
  const Range(this.lo, this.hi);
  Level of(double v) => v < lo ? Level.low : (v > hi ? Level.high : Level.normal);
}

class BodyScales {
  final BodyInput i;
  const BodyScales(this.i);

  List<double> get bmi => const [18.5, 25.0, 28.0, 32.0];

  /// Жир, %: [низкий|норма, норма|высокий, высокий|очень высокий, очень высокий].
  List<double> get fat {
    final a = i.age;
    final f = i.female;
    if (a < 12) return f ? const [12.0, 21.0, 30.0, 34.0] : const [7.0, 16.0, 25.0, 30.0];
    if (a < 14) return f ? const [15.0, 24.0, 33.0, 37.0] : const [7.0, 16.0, 25.0, 30.0];
    if (a < 16) return f ? const [18.0, 27.0, 36.0, 40.0] : const [7.0, 16.0, 25.0, 30.0];
    if (a < 18) return f ? const [20.0, 28.0, 37.0, 41.0] : const [7.0, 16.0, 25.0, 30.0];
    if (a < 40) return f ? const [21.0, 28.0, 35.0, 40.0] : const [11.0, 17.0, 22.0, 27.0];
    if (a < 60) return f ? const [22.0, 29.0, 36.0, 41.0] : const [12.0, 18.0, 23.0, 28.0];
    return f ? const [23.0, 30.0, 37.0, 42.0] : const [14.0, 20.0, 25.0, 30.0];
  }

  /// Мышечная масса, кг: [низкая, высокая граница нормы].
  List<double> get muscle {
    final h = i.height;
    if (i.female) {
      if (h >= 160) return const [36.5, 42.6];
      if (h >= 150) return const [32.9, 37.6];
      return const [29.1, 34.8];
    }
    if (h >= 170) return const [49.4, 59.5];
    if (h >= 160) return const [44.0, 52.5];
    return const [38.5, 46.6];
  }

  List<double> get water => i.female ? const [45.0, 60.1] : const [55.0, 65.1];
  List<double> get visceral => const [10.0, 15.0];

  List<double> get bone {
    final w = i.weight;
    if (i.female) {
      if (w >= 60) return const [1.8, 3.9];
      if (w >= 45) return const [1.5, 3.8];
      return const [1.3, 3.6];
    }
    if (w >= 75) return const [2.0, 4.2];
    if (w >= 60) return const [1.9, 4.1];
    return const [1.6, 3.9];
  }

  /// Нормальный основной обмен, ккал/сут (ниже — штраф в оценке).
  double get bmrNormal {
    final c = i.female
        ? const {30: 21.24, 50: 19.53, 100: 18.63}
        : const {30: 21.6, 50: 20.07, 100: 19.35};
    for (final e in c.entries) {
      if (i.age < e.key) return i.weight * e.value;
    }
    return 0;
  }

  List<double> get protein => const [16.0, 20.0];
}

class BodyMetrics {
  final BodyInput input;
  final double bmi, fat, water, bone, muscle, visceral, bmr, protein, bodyAge;
  final int bodyType; // 0..8, см. [bodyTypeNames]
  final double score;
  final BodyScales scales;
  const BodyMetrics._(this.input, this.bmi, this.fat, this.water, this.bone, this.muscle,
      this.visceral, this.bmr, this.protein, this.bodyAge, this.bodyType, this.score, this.scales);

  /// Диапазоны нормы для отображения и оценки (нижняя граница, верхняя граница).
  Range get fatRange => Range(scales.fat[0], scales.fat[2]);
  Range get muscleRange => Range(scales.muscle[0], scales.muscle[1]);
  Range get waterRange => Range(scales.water[0], scales.water[1]);
  Range get boneRange => Range(scales.bone[0], scales.bone[1]);
  Range get proteinRange => Range(scales.protein[0], scales.protein[1]);
  Range get visceralRange => const Range(1, 9);

  static const bodyTypeNames = [
    'Ожирение',
    'Избыточный вес',
    'Плотное',
    'Малоподвижное',
    'Нормальное',
    'Атлетичное',
    'Худощавое',
    'Худощавое сбалансированное',
    'Худощавое мускулистое',
  ];

  static BodyMetrics? compute(BodyInput i) {
    if (!i.valid) return null;
    final w = i.weight, h = i.height, age = i.age.toDouble();
    final female = i.female;

    // Коэффициент безжировой массы
    var lbm = (h * 9.058 / 100) * (h / 100);
    lbm += w * 0.32 + 12.226;
    lbm -= i.impedance * 0.0068;
    lbm -= age * 0.0542;

    // Основной обмен
    double bmr;
    if (female) {
      bmr = 864.6 + w * 10.2036;
      bmr -= h * 0.39336;
      bmr -= age * 6.204;
    } else {
      bmr = 877.8 + w * 14.916;
      bmr -= h * 0.726;
      bmr -= age * 8.976;
    }
    if (female && bmr > 2996) {
      bmr = 5000;
    } else if (!female && bmr > 2322) {
      bmr = 5000;
    }
    bmr = _clamp(bmr, 500, 10000);

    // Жир, %
    final double fconst = female ? (i.age <= 49 ? 9.25 : 7.25) : 0.8;
    double coef;
    if (!female && w < 61) {
      coef = 0.98;
    } else if (female && w > 60) {
      coef = 0.96;
      if (h > 160) coef *= 1.03;
    } else if (female && w < 50) {
      coef = 1.02;
      if (h > 160) coef *= 1.03;
    } else {
      coef = 1.0;
    }
    var fat = (1.0 - (((lbm - fconst) * coef) / w)) * 100;
    if (fat > 63) fat = 75;
    fat = _clamp(fat, 5, 75);

    // Вода, %
    var water = (100 - fat) * 0.7;
    final wcoef = water <= 50 ? 1.02 : 0.98;
    if (water * wcoef >= 65) water = 75;
    water = _clamp(water * wcoef, 35, 75);

    // Костная масса, кг
    final base = female ? 0.245691014 : 0.18016894;
    var bone = (base - (lbm * 0.05158)) * -1;
    bone += bone > 2.2 ? 0.1 : -0.1;
    if (female && bone > 5.1) {
      bone = 8;
    } else if (!female && bone > 5.2) {
      bone = 8;
    }
    bone = _clamp(bone, 0.5, 8);

    // Мышечная масса, кг
    var muscle = w - ((fat * 0.01) * w) - bone;
    if (female && muscle >= 84) {
      muscle = 120;
    } else if (!female && muscle >= 93.5) {
      muscle = 120;
    }
    muscle = _clamp(muscle, 10, 120);

    // Висцеральный жир, уровень
    double vfal;
    if (female) {
      if (w > (13 - (h * 0.5)) * -1) {
        final subsub = ((h * 1.45) + (h * 0.1158) * h) - 120;
        final sub = w * 500 / subsub;
        vfal = (sub - 6) + (age * 0.07);
      } else {
        final sub = 0.691 + (h * -0.0024) + (h * -0.0024);
        vfal = (((h * 0.027) - (sub * w)) * -1) + (age * 0.07) - age;
      }
    } else {
      if (h < w * 1.6) {
        final sub = ((h * 0.4) - (h * (h * 0.0826))) * -1;
        vfal = ((w * 305) / (sub + 48)) - 2.9 + (age * 0.15);
      } else {
        final sub = 0.765 + h * -0.0015;
        vfal = (((h * 0.143) - (w * sub)) * -1) + (age * 0.15) - 5.0;
      }
    }
    final visceral = _clamp(vfal, 1, 50);

    // ИМТ
    final bmi = _clamp(w / ((h / 100) * (h / 100)), 10, 90);

    // Белок, %
    final protein = _clamp((muscle / w) * 100 - water, 5, 32);

    // Возраст тела
    final bodyAge = _clamp(
        female
            ? (h * -1.1165) + (w * 1.5784) + (age * 0.4615) + (i.impedance * 0.0415) + 83.2548
            : (h * -0.7471) + (w * 0.9161) + (age * 0.4184) + (i.impedance * 0.0517) + 54.2267,
        15,
        80);

    final scales = BodyScales(i);

    // Тип телосложения (из девяти)
    final int factor;
    if (fat > scales.fat[2]) {
      factor = 0;
    } else if (fat < scales.fat[1]) {
      factor = 2;
    } else {
      factor = 1;
    }
    final int type;
    if (muscle > scales.muscle[1]) {
      type = 2 + (factor * 3);
    } else if (muscle < scales.muscle[0]) {
      type = factor * 3;
    } else {
      type = 1 + (factor * 3);
    }

    final score = _score(scales, i, bmi, fat, muscle, water, visceral, bone, bmr, protein);
    return BodyMetrics._(
        i, bmi, fat, water, bone, muscle, visceral, bmr, protein, bodyAge, type, score, scales);
  }

  // ---- Оценка состояния тела (восстановлена из Mi Fit, 100 минус штрафы) ----
  static double _malus(double data, double minD, double maxD, double maxM, double minM) {
    final r = ((data - maxD) / (minD - maxD)) * (maxM - minM);
    return r >= 0 ? r : 0;
  }

  static double _score(BodyScales sc, BodyInput i, double bmi, double fat, double muscle,
      double water, double visceral, double bone, double bmr, double protein) {
    var score = 100.0;
    final fs = sc.fat;

    // ИМТ
    double bmiMalus = 0;
    if (i.height >= 90) {
      if (bmi >= 18.5 && i.age >= 18 && fat < fs[2]) {
        bmiMalus = 0;
      } else if (bmi >= 14 && i.age < 18 && fat < fs[2]) {
        bmiMalus = 0;
      } else if (bmi <= 14) {
        bmiMalus = 30;
      } else if (bmi > 14 && bmi < 15) {
        bmiMalus = _malus(bmi, 14, 15, 30, 15) + 15;
      } else if (bmi >= 15 && bmi < 18.5 && i.age >= 18) {
        bmiMalus = _malus(bmi, 15, 18.5, 15, 5) + 5;
      } else if (((bmi >= 15 && i.age < 18) || (bmi >= 18.5 && i.age >= 18)) && fat >= fs[2]) {
        if (bmi >= 32) {
          bmiMalus = 10;
        } else if (bmi > 28) {
          bmiMalus = _malus(bmi, 28, 25, 5, 10) + 5;
        } else {
          bmiMalus = 0;
        }
      }
    }
    score -= bmiMalus;

    // Жир
    final best = i.female ? fs[2] - 2.0 : fs[2] - 3.0;
    double fatMalus;
    if (fat >= fs[0] && fat < best) {
      fatMalus = 0;
    } else if (fat >= fs[3]) {
      fatMalus = 20;
    } else {
      // Как в оригинале: остальные ветки там недостижимы, поэтому и «чуть выше нормы»,
      // и «ниже нормы» дают не меньше 10 штрафных баллов.
      fatMalus = _malus(fat, fs[3], fs[2], 20, 10) + 10;
    }
    score -= fatMalus;

    // Мышцы
    final ms = sc.muscle;
    if (muscle >= ms[0]) {
      // нет штрафа
    } else if (muscle < ms[0] - 5) {
      score -= 10;
    } else {
      score -= _malus(muscle, ms[0] - 5, ms[0], 10, 5) + 5;
    }

    // Вода
    final ws = sc.water;
    if (water >= ws[0]) {
      // нет штрафа
    } else if (water <= ws[0] - 5) {
      score -= 10;
    } else {
      score -= _malus(water, ws[0] - 5, ws[0], 10, 5) + 5;
    }

    // Висцеральный жир
    final vs = sc.visceral;
    if (visceral < vs[0]) {
      // нет штрафа
    } else if (visceral >= vs[1]) {
      score -= 15;
    } else {
      score -= _malus(visceral, vs[1], vs[0], 15, 10) + 10;
    }

    // Кости
    final bs = sc.bone;
    if (bone >= bs[0]) {
      // нет штрафа
    } else if (bone <= bs[0] - 0.3) {
      score -= 10;
    } else {
      score -= _malus(bone, bs[0] - 0.3, bs[0], 10, 5) + 5;
    }

    // Основной обмен
    final normal = sc.bmrNormal;
    if (bmr >= normal) {
      // нет штрафа
    } else if (bmr <= normal - 300) {
      score -= 6;
    } else {
      score -= _malus(bmr, normal - 300, normal, 6, 3) + 5;
    }

    // Белок
    if (protein > 17.0) {
      // нет штрафа
    } else if (protein < 10.0) {
      score -= 10;
    } else if (protein <= 16.0) {
      score -= _malus(protein, 10, 16, 10, 5) + 5;
    } else {
      score -= _malus(protein, 16, 17, 5, 3) + 3;
    }
    return math.max(0, score);
  }
}

/// Категория ИМТ (ВОЗ) для подписи рядом со значением.
String bmiCategory(double bmi) {
  if (bmi < 18.5) return 'Дефицит';
  if (bmi < 25) return 'Норма';
  if (bmi < 30) return 'Избыток';
  return 'Ожирение';
}

/// ИМТ без импеданса: нужен только рост.
double? bmiOf(double weightKg, double? heightCm) =>
    heightCm == null || heightCm <= 0 ? null : weightKg / ((heightCm / 100) * (heightCm / 100));
