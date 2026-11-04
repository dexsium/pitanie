/// Ориентир по воде: 30–35 мл на кг массы тела (не медицинская норма).
/// Активность, жара и ограничения учитываются только добавкой [extraMl], которую
/// пользователь задаёт сам: произвольной воды «за каждый шаг» не добавляется.
double calcWaterMl(
    {required double weightKg, double mlPerKg = 33, double extraMl = 0}) {
  final k = mlPerKg.clamp(30.0, 35.0);
  final extra = extraMl < 0 ? 0.0 : extraMl;
  return weightKg * k + extra;
}
