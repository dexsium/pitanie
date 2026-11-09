import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/features/ai/gemini_service.dart';

void main() {
  test('разбор ответа: корректная позиция принимается', () {
    final r = parseFoodResponse(
        '{"items":[{"name":"Гречка","grams":200,"calories":260,"proteins":9,"fats":2,"carbs":50}],"comment":"ок"}');
    expect(r.items.length, 1);
    expect(r.items.first.kcal, closeTo(260, 0.1));
    expect(r.comment, 'ок');
  });

  test('невозможные значения отбрасываются', () {
    final r = parseFoodResponse(
        '{"items":[{"name":"Х","grams":100,"calories":50,"proteins":120,"fats":0,"carbs":0},'
        '{"name":"","grams":100,"calories":100,"proteins":1,"fats":1,"carbs":1},'
        '{"name":"Минус","grams":100,"calories":-5,"proteins":1,"fats":1,"carbs":1},'
        '{"name":"Нет граммов","grams":0,"calories":10,"proteins":1,"fats":1,"carbs":1}]}');
    expect(r.items, isEmpty);
  });

  test('калории, не сходящиеся с БЖУ, пересчитываются по БЖУ', () {
    final i = sanitizeFoodItem('Курица', 150, 900, 30, 5, 0)!;
    expect(i.kcal, closeTo(4 * 30 + 9 * 5, 0.1));
  });

  test('числа в виде строк с запятой читаются', () {
    final r = parseFoodResponse(
        '{"items":[{"name":"Яблоко","grams":"150","calories":"78,5","proteins":"0,4","fats":"0,3","carbs":"20"}]}');
    expect(r.items.length, 1);
  });

  test('мусор вместо JSON даёт понятную ошибку', () {
    expect(() => parseFoodResponse('не json'), throwsA(isA<AiException>()));
  });

  test('рекомендации ужимаются до остатка калорий', () {
    const rem = Nutrients(300, 20, 10, 30);
    final big = [
      const AiFoodItem('А', 200, 400, 20, 10, 40),
      const AiFoodItem('Б', 100, 200, 10, 5, 20),
    ];
    final fit = fitToRemaining(big, rem);
    final kcal = fit.fold<double>(0, (a, b) => a + b.kcal);
    expect(kcal, lessThanOrEqualTo(300 * 1.1 + 1));
  });

  test('рекомендации в пределах остатка не меняются', () {
    const rem = Nutrients(500, 20, 10, 30);
    final ok = [const AiFoodItem('А', 100, 200, 20, 5, 10)];
    expect(fitToRemaining(ok, rem).first.grams, 100);
  });

  test('смена массы пересчитывает состав пропорционально', () {
    const i = AiFoodItem('Рис', 100, 130, 3, 0, 28);
    final j = i.withGrams(200);
    expect(j.kcal, 260);
    expect(j.carbs, 56);
  });
}
