// Gemini API: распознавание еды по фото и подбор продуктов для добора нормы.
// Ключ пользователь вводит сам, он хранится в защищённом хранилище устройства и уходит
// только в Google (заголовок x-goog-api-key). Ответ модели всегда проверяется локально:
// ему нельзя доверять числа без проверки.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/nutrition.dart';
import '../../database/database.dart';

const kAiEnabledKey = 'ai_enabled';
const kAiModelKey = 'ai_model';
const kAiKeyStorage = 'gemini_api_key';

/// Псевдоним «последней быстрой модели» Gemini: не устаревает вместе с версиями.
const kDefaultAiModel = 'gemini-flash-latest';

const _storage = FlutterSecureStorage();

Future<String?> readAiKey() async {
  try {
    final k = await _storage.read(key: kAiKeyStorage);
    return (k == null || k.trim().isEmpty) ? null : k.trim();
  } catch (_) {
    return null;
  }
}

Future<void> writeAiKey(String? key) async {
  if (key == null || key.trim().isEmpty) {
    await _storage.delete(key: kAiKeyStorage);
  } else {
    await _storage.write(key: kAiKeyStorage, value: key.trim());
  }
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// Позиция еды: значения указаны на всю порцию [grams], а не на 100 г.
class AiFoodItem {
  final String name;
  final double grams, kcal, proteins, fats, carbs;
  const AiFoodItem(this.name, this.grams, this.kcal, this.proteins, this.fats, this.carbs);

  Nutrients get total => Nutrients(kcal, proteins, fats, carbs);

  /// Та же еда в другой массе: состав пропорционален.
  AiFoodItem withGrams(double g) {
    final k = grams <= 0 ? 0.0 : g / grams;
    return AiFoodItem(name, g, kcal * k, proteins * k, fats * k, carbs * k);
  }

  AiFoodItem withName(String n) => AiFoodItem(n, grams, kcal, proteins, fats, carbs);
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').trim());
  return null;
}

/// Проверяет и исправляет одну позицию. Возвращает null, если данные невозможны.
/// Калории, не сходящиеся с БЖУ более чем на 20 %, пересчитываются по БЖУ (4/9/4 ккал на грамм).
AiFoodItem? sanitizeFoodItem(
    String name, double? grams, double? kcal, double? p, double? f, double? c) {
  final n = name.trim();
  if (n.isEmpty || grams == null || kcal == null || p == null || f == null || c == null) {
    return null;
  }
  final all = [grams, kcal, p, f, c];
  if (all.any((v) => v.isNaN || v.isInfinite || v < 0)) return null;
  if (grams < 1 || grams > 3000) return null;
  // Белки, жиры и углеводы вместе не могут весить больше самой порции.
  if (p + f + c > grams * 1.02) return null;
  final byMacros = 4 * p + 9 * f + 4 * c;
  var k = kcal;
  if (byMacros > 20) {
    if ((k - byMacros).abs() > 0.2 * byMacros) k = byMacros;
  }
  // Больше 9 ккал на грамм (чистый жир ~ 9) невозможно.
  if (k > grams * 9.2) return null;
  return AiFoodItem(n.length > 80 ? n.substring(0, 80) : n, grams, k, p, f, c);
}

({List<AiFoodItem> items, String comment}) parseFoodResponse(String jsonText) {
  final Object? j;
  try {
    j = jsonDecode(jsonText);
  } catch (_) {
    throw const AiException('Ответ ИИ не удалось прочитать. Попробуйте ещё раз.');
  }
  final list = j is Map ? j['items'] : (j is List ? j : null);
  if (list is! List) {
    throw const AiException('Ответ ИИ не удалось прочитать. Попробуйте ещё раз.');
  }
  final items = <AiFoodItem>[];
  for (final e in list) {
    if (e is! Map) continue;
    final it = sanitizeFoodItem('${e['name'] ?? ''}', _num(e['grams']), _num(e['calories']),
        _num(e['proteins']), _num(e['fats']), _num(e['carbs']));
    if (it != null) items.add(it);
  }
  final comment = j is Map ? '${j['comment'] ?? ''}'.trim() : '';
  return (items: items, comment: comment);
}

/// Ужимает набор рекомендаций, чтобы он не превышал остаток: ИИ иногда «перебирает» порции.
/// Если сумма калорий больше остатка более чем на 10 %, все порции уменьшаются пропорционально.
List<AiFoodItem> fitToRemaining(List<AiFoodItem> items, Nutrients remaining) {
  if (items.isEmpty || remaining.calories <= 0) return items;
  final kcal = items.fold<double>(0, (a, b) => a + b.kcal);
  final limit = remaining.calories * 1.1;
  if (kcal <= limit) return items;
  final k = remaining.calories / kcal;
  double step(double g) {
    final v = (g * k / 5).round() * 5.0;
    return v < 5 ? 5 : v;
  }

  return [for (final i in items) i.withGrams(step(i.grams))];
}

class GeminiClient {
  final String apiKey;
  final String model;
  GeminiClient(this.apiKey, {this.model = kDefaultAiModel});

  static const _host = 'generativelanguage.googleapis.com';

  Future<String> _generate(List<Map<String, Object?>> parts, Map<String, Object?> schema) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .postUrl(Uri.https(_host, '/v1beta/models/$model:generateContent'))
          .timeout(const Duration(seconds: 15));
      req.headers
        ..set('Content-Type', 'application/json; charset=utf-8')
        ..set('x-goog-api-key', apiKey);
      req.add(utf8.encode(jsonEncode({
        'contents': [
          {'role': 'user', 'parts': parts}
        ],
        'generationConfig': {
          'temperature': 0.3,
          'responseMimeType': 'application/json',
          'responseSchema': schema,
        },
      })));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw AiException(_httpError(res.statusCode, body));
      final j = jsonDecode(body) as Map<String, dynamic>;
      final block = (j['promptFeedback'] as Map?)?['blockReason'];
      if (block != null) {
        throw const AiException('Google отклонил запрос (фото или текст не прошли проверку).');
      }
      final cands = j['candidates'] as List?;
      final text = cands == null || cands.isEmpty
          ? null
          : ((cands.first as Map)['content'] as Map?)?['parts'] is List
              ? (((cands.first as Map)['content'] as Map)['parts'] as List)
                  .map((p) => (p as Map)['text'] ?? '')
                  .join()
              : null;
      if (text == null || text.trim().isEmpty) {
        throw const AiException('ИИ не вернул ответ. Попробуйте ещё раз.');
      }
      return text;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw const AiException('Нет ответа от Google. Проверьте интернет и повторите.');
    } on SocketException {
      throw const AiException('Нет соединения с интернетом.');
    } on HandshakeException {
      throw const AiException('Не удалось установить защищённое соединение.');
    } catch (_) {
      throw const AiException('Не удалось получить ответ ИИ. Попробуйте ещё раз.');
    } finally {
      client.close(force: true);
    }
  }

  static String _httpError(int code, String body) {
    String detail = '';
    try {
      detail = ((jsonDecode(body) as Map)['error'] as Map)['message']?.toString() ?? '';
    } catch (_) {}
    final lower = detail.toLowerCase();
    if (code == 400 && lower.contains('api key')) {
      return 'Ключ не принят Google. Проверьте, что он скопирован целиком.';
    }
    if (code == 401 || code == 403) {
      return 'Ключ не подходит или доступ запрещён. Проверьте ключ и регион.';
    }
    if (code == 404) {
      return 'Модель недоступна. Укажите другую модель в настройках ИИ.';
    }
    if (code == 429) {
      return 'Исчерпан бесплатный лимит запросов. Подождите минуту или до завтра.';
    }
    if (code >= 500) return 'Сервис Google временно недоступен. Повторите позже.';
    return 'Ошибка Google ($code). Повторите позже.';
  }

  static const _itemSchema = {
    'type': 'OBJECT',
    'properties': {
      'name': {'type': 'STRING'},
      'grams': {'type': 'NUMBER'},
      'calories': {'type': 'NUMBER'},
      'proteins': {'type': 'NUMBER'},
      'fats': {'type': 'NUMBER'},
      'carbs': {'type': 'NUMBER'},
    },
    'required': ['name', 'grams', 'calories', 'proteins', 'fats', 'carbs'],
  };

  static const _listSchema = {
    'type': 'OBJECT',
    'properties': {
      'items': {'type': 'ARRAY', 'items': _itemSchema},
      'comment': {'type': 'STRING'},
    },
    'required': ['items'],
  };

  /// Проверка ключа: короткий запрос без картинки.
  Future<void> ping() async {
    await _generate([
      {'text': 'Верни JSON {"items": [], "comment": "ok"}'}
    ], _listSchema);
  }

  Future<({List<AiFoodItem> items, String comment})> recognizeFood(
      Uint8List image, String mime) async {
    const prompt = 'Ты помощник по питанию. На фото еда. Определи каждое отдельное блюдо или '
        'продукт, оцени массу порции в граммах по размеру на фото и посуде, и посчитай '
        'пищевую ценность именно этой порции (не на 100 г): калории, белки, жиры, углеводы '
        'в граммах. Названия на русском, коротко. Не выдумывай то, чего не видно. '
        'Если на фото нет еды, верни пустой список items. В comment кратко напиши, '
        'насколько ты уверен и что могло исказить оценку (соус, скрытые ингредиенты).';
    final text = await _generate([
      {'text': prompt},
      {
        'inline_data': {'mime_type': mime, 'data': base64Encode(image)}
      },
    ], _listSchema);
    return parseFoodResponse(text);
  }

  /// Подбор еды, чтобы добрать [remaining]. [mine] — продукты пользователя на 100 г,
  /// [eatenToday] — что уже съедено, чтобы не повторяться.
  Future<({List<AiFoodItem> items, String comment})> suggestMeals({
    required Nutrients remaining,
    required GoalValues goal,
    required List<({String name, Nutrients per100})> mine,
    required List<String> eatenToday,
    String? wish,
  }) async {
    String r(double v) => v.round().toString();
    final b = StringBuffer()
      ..writeln('Ты помощник по питанию. Человеку до суточной нормы не хватает: '
          '${r(remaining.calories)} ккал, белка ${r(remaining.proteins)} г, '
          'жиров ${r(remaining.fats)} г, углеводов ${r(remaining.carbs)} г.')
      ..writeln('Суточная норма: ${r(goal.calories)} ккал, Б ${r(goal.proteins)}, '
          'Ж ${r(goal.fats)}, У ${r(goal.carbs)}.')
      ..writeln('Предложи 2–5 продуктов или простых блюд с массой порции в граммах, которые '
          'вместе закрывают недостающее. Главное: суммарные калории не больше '
          '${r(remaining.calories)} ккал, сначала закрой белок, потом остальное. '
          'Реалистичные порции, продукты, которые легко купить в России. '
          'Значения calories/proteins/fats/carbs указывай на всю порцию, не на 100 г. '
          'Если остаток почти нулевой, верни пустой список.');
    if (mine.isNotEmpty) {
      b.writeln('Продукты, которые человек уже ест (значения на 100 г), предпочитай их:');
      for (final m in mine.take(40)) {
        b.writeln('- ${m.name}: ${r(m.per100.calories)} ккал, Б ${m.per100.proteins.toStringAsFixed(1)}, '
            'Ж ${m.per100.fats.toStringAsFixed(1)}, У ${m.per100.carbs.toStringAsFixed(1)}');
      }
    }
    if (eatenToday.isNotEmpty) {
      b.writeln('Сегодня уже съедено: ${eatenToday.take(25).join(', ')}.');
    }
    if (wish != null && wish.trim().isNotEmpty) {
      b.writeln('Пожелание: ${wish.trim()}');
    }
    b.writeln('В comment одной-двумя фразами объясни выбор. Названия на русском.');
    final text = await _generate([
      {'text': b.toString()}
    ], _listSchema);
    final parsed = parseFoodResponse(text);
    return (items: fitToRemaining(parsed.items, remaining), comment: parsed.comment);
  }
}

/// Клиент, если ИИ включён и ключ сохранён.
Future<GeminiClient?> loadGeminiClient(AppDatabase db) async {
  final s = await db.allSettings();
  if (s[kAiEnabledKey] != '1') return null;
  final key = await readAiKey();
  if (key == null) return null;
  final m = (s[kAiModelKey] ?? '').trim();
  return GeminiClient(key, model: m.isEmpty ? kDefaultAiModel : m);
}
