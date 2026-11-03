import 'dart:convert';
import 'dart:io';

class OffResult {
  final String? name, brand;
  final double? kcal, proteins, fats, carbs;
  const OffResult(this.name, this.brand, this.kcal, this.proteins, this.fats, this.carbs);
  bool get complete =>
      name != null && kcal != null && proteins != null && fats != null && carbs != null;

  /// Нутриенты физически возможны (см. [validateOffNutrients]); неполные данные недопустимы.
  bool get usable =>
      complete && validateOffNutrients(kcal!, proteins!, fats!, carbs!).isValid;

  /// Предупреждение о подозрительных, но возможных значениях (null — всё согласовано).
  String? get warning => complete ? validateOffNutrients(kcal!, proteins!, fats!, carbs!).warning : null;
}

/// Атрибуция по условиям ODbL / Open Food Facts: источник и лицензия показываются
/// рядом с данными, продукт сохраняется как копия записи для личного использования.
const offAttribution =
    'Данные: Open Food Facts (участники проекта), лицензия ODbL 1.0 — https://world.openfoodfacts.org';

class NutrientCheck {
  final bool isValid;
  final String? warning;
  const NutrientCheck(this.isValid, [this.warning]);
}

/// Проверка значений на 100 г из пользовательской базы. Невозможные значения отклоняются,
/// заметное расхождение калорий с БЖУ даёт предупреждение (оболочка, клетчатка, спирт и т. п.).
NutrientCheck validateOffNutrients(double kcal, double p, double f, double c) {
  if ([kcal, p, f, c].any((v) => v.isNaN || v.isInfinite || v < 0)) {
    return const NutrientCheck(false);
  }
  if (p + f + c > 100.5 || kcal > 902) return const NutrientCheck(false);
  final expected = 4 * p + 4 * c + 9 * f;
  final diff = (kcal - expected).abs();
  if (diff > 40 && diff > 0.3 * (expected > kcal ? expected : kcal)) {
    return NutrientCheck(true,
        'Калории (${kcal.round()}) заметно расходятся с расчётом по БЖУ (~${expected.round()}). Проверьте по упаковке.');
  }
  return const NutrientCheck(true);
}

/// Запрос к Open Food Facts. Отправляется только штрихкод.
/// Возвращает null, если продукт не найден или сеть недоступна.
Future<OffResult?> lookupOpenFoodFacts(String code) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$code.json'
        '?fields=product_name,brands,nutriments'));
    req.headers.set('User-Agent', 'Pitanie/1.0 (Flutter diary app)');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body) as Map<String, dynamic>;
    if (j['status'] != 1) return null;
    final p = j['product'] as Map<String, dynamic>;
    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
    double? g(String k) => (n[k] as num?)?.toDouble();
    final name = (p['product_name'] as String?)?.trim();
    final brand = (p['brands'] as String?)?.split(',').first.trim();
    // Если калории не указаны, энергия в кДж пересчитывается (1 ккал = 4,184 кДж).
    final kj = g('energy-kj_100g') ?? g('energy_100g');
    return OffResult(
      (name == null || name.isEmpty) ? null : name,
      (brand == null || brand.isEmpty) ? null : brand,
      g('energy-kcal_100g') ?? (kj == null ? null : kj / 4.184),
      g('proteins_100g'),
      g('fat_100g'),
      g('carbohydrates_100g'),
    );
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
