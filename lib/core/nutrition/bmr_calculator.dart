import '../nutrition.dart' show Sex;

/// Минимальный возраст, для которого применима взрослая формула.
const kAdultAge = 18;

bool isAdultAge(int age) => age >= kAdultAge;

/// Формула Миффлина — Сан Жеора для взрослых (ккал/сут, оценка).
/// Для несовершеннолетних возвращает null: взрослая формула к ним не применяется.
double? bmrAdult({
  required Sex sex,
  required double weightKg,
  required double heightCm,
  required int age,
}) {
  if (!isAdultAge(age)) return null;
  return 10 * weightKg +
      6.25 * heightCm -
      5 * age +
      (sex == Sex.male ? 5 : -161);
}
