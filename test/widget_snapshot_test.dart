import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/core/labels.dart';
import 'package:pitanie/core/nutrition.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/nutrition/diary_actions.dart';
import 'package:pitanie/features/widgets/widget_sync.dart';
import 'package:pitanie/core/dates.dart';
import 'package:pitanie/features/dashboard/day_data.dart';
import 'package:pitanie_widgets/pitanie_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('показ данных в виджетах по умолчанию выключен', () {
    expect(widgetsEnabled({}), isFalse);
    expect(widgetsEnabled({kWidgetsEnabledKey: '0'}), isFalse);
    expect(widgetsEnabled({kWidgetsEnabledKey: '1'}), isTrue);
  });

  test('в снимке выключенных виджетов нет данных о питании и воде', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final key = dayKey(DateTime.now());
    await addManualEntry(db, day: key, meal: Meal.lunch, name: 'Суп', kcal: 500, p: 20);
    await db.addWater(key, 300);
    final d = await loadDayData(db, key);
    final off = buildWidgetSnapshot(d, enabled: false);
    expect(off, {'enabled': false, 'day': key});
    final on = buildWidgetSnapshot(d, enabled: true);
    expect(on['kcal'], 500);
    expect(on['p'], 20);
    expect(on['water'], 300);
    expect(on['kcalGoal'], greaterThan(0));
    expect(on['waterGoal'], greaterThan(0));
    expect(on['day'], key);
  });

  test('отправка в виджет: при отсутствии платформенной части ничего не падает', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect(await pushWidgetsNow(db), isFalse);
    expect(await PitanieWidgets.isSupported(), isFalse);
    expect(await PitanieWidgets.takeInitialAction(), isNull);
  });

  test('отправка в виджет: снимок передаётся как JSON, действия приходят потоком', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    String? sent;
    const ch = MethodChannel('pitanie_widgets');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch,
        (call) async {
      if (call.method == 'update') {
        sent = (call.arguments as Map)['json'] as String;
        return true;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null));
    await db.setSetting(kWidgetsEnabledKey, '1');
    expect(await pushWidgetsNow(db), isTrue);
    final m = jsonDecode(sent!) as Map<String, dynamic>;
    expect(m['enabled'], isTrue);
    expect(m['day'], dayKey(DateTime.now()));

    final got = <String>[];
    final sub = PitanieWidgets.actions.listen(got.add);
    addTearDown(sub.cancel);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
        'pitanie_widgets',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('onAction', 'water')),
        (_) {});
    await Future<void>.delayed(Duration.zero);
    expect(got, ['water']);
  });
}
