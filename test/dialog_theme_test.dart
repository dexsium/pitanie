import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/app/theme.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('Окна в стиле приложения без ошибок вёрстки, $b', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(b),
        home: Builder(
          builder: (c) => Scaffold(
            body: Column(children: [
              TextButton(
                  onPressed: () => showDialog(
                      context: c,
                      builder: (_) => AlertDialog(
                            title: const Text('Заголовок'),
                            content: const TextField(),
                            actions: [
                              TextButton(onPressed: () {}, child: const Text('Отмена')),
                              FilledButton(
                                  style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
                                  onPressed: () {},
                                  child: const Text('Готово')),
                            ],
                          )),
                  child: const Text('d')),
              TextButton(
                  onPressed: () => showModalBottomSheet(
                      context: c, builder: (_) => const SizedBox(height: 200, child: Text('s'))),
                  child: const Text('s')),
              TextButton(
                  onPressed: () => showDatePicker(
                      context: c,
                      initialDate: DateTime(2026, 11, 10),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030)),
                  child: const Text('p')),
            ]),
          ),
        ),
      ));
      for (final k in ['d', 's', 'p']) {
        await tester.tap(find.text(k));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
    });
  }
}
