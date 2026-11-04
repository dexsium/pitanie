import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pitanie/database/database.dart';
import 'package:pitanie/features/profile/plan_explain.dart';
import 'package:pitanie/services/health/plan_service.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
      'объяснение расчёта: формула, коэффициент, источники, достоверность',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 4, 12);
    final db = AppDatabase(NativeDatabase.memory());
    late PlanSnapshot p;
    await tester.runAsync(() async {
      await db.saveUser(UsersCompanion(
          sex: const Value('male'),
          birthDate: Value(DateTime(1991, 1, 1)),
          heightCm: const Value(175),
          goalType: const Value('gain'),
          activityLevel: const Value('light')));
      await db.addWeight(now, 70.3);
      p = await loadPlan(db, now);
    });
    expect(planExplanation(p).map((e) => e.$1),
        containsAll(['Базовый обмен (BMR)', 'Источники данных']));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (c) => Scaffold(
                body: Center(
                    child: ElevatedButton(
                        onPressed: () => showPlanExplanation(c, p),
                        child: const Text('открыть')))))));
    await tester.tap(find.text('открыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Миффлина'), findsOneWidget);
    expect(find.textContaining('1627'), findsWidgets);
    expect(find.textContaining('ручной ввод'), findsOneWidget);
    expect(find.textContaining('Индивидуальный расход не определён'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => db.close());
  });
}
