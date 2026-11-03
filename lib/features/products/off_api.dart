import 'dart:convert';
import 'dart:io';

class OffResult {
  final String? name, brand;
  final double? kcal, proteins, fats, carbs;
  const OffResult(this.name, this.brand, this.kcal, this.proteins, this.fats, this.carbs);
  bool get complete =>
      name != null && kcal != null && proteins != null && fats != null && carbs != null;
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
    return OffResult(
      (name == null || name.isEmpty) ? null : name,
      (brand == null || brand.isEmpty) ? null : brand,
      g('energy-kcal_100g'),
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
