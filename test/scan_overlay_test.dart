import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/products/barcode_scan_page.dart';

Widget host(Widget child) => MaterialApp(
    home: Scaffold(backgroundColor: Colors.black, body: SizedBox.expand(child: child)));

ScanOverlay overlay(
        {String? code, VoidCallback? onManual, ValueChanged<String>? onDone, VoidCallback? onClose}) =>
    ScanOverlay(
      code: code,
      torch: const SizedBox(width: 48, height: 48),
      onClose: onClose ?? () {},
      onManual: onManual ?? () {},
      onDone: onDone ?? (_) {},
    );

void main() {
  for (final size in const [Size(393, 852), Size(360, 640), Size(430, 932), Size(320, 568)]) {
    testWidgets('Сканер: поиск и успех без ошибок вёрстки ${size.width.toInt()}×${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      String? done;
      await tester.pumpWidget(host(overlay(onDone: (c) => done = c)));
      await tester.pump(const Duration(milliseconds: 900)); // лазер идёт
      expect(tester.takeException(), isNull);
      expect(find.text('Наведите камеру на штрихкод'), findsOneWidget);
      expect(find.text('Ввести штрихкод вручную'), findsOneWidget);

      // обнаружение штрихкода запускает анимацию успеха
      await tester.pumpWidget(host(overlay(code: '4607084351361', onDone: (c) => done = c)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('4607084351361'), findsOneWidget);
      expect(done, isNull); // сначала проигрывается анимация
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, '4607084351361'); // потом результат возвращается
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Сканер: подсказка меняется, если код долго не считывается', (tester) async {
    await tester.pumpWidget(host(overlay()));
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('фонарик'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Сканер: кнопки ввода вручную и закрытия работают', (tester) async {
    var manual = 0, closed = 0;
    await tester.pumpWidget(host(overlay(onManual: () => manual++, onClose: () => closed++)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ввести штрихкод вручную'));
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(manual, 1);
    expect(closed, 1);
  });

  testWidgets('Сканер: повторное появление кода не запускает результат дважды', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(overlay(code: '123', onDone: (_) => calls++)));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpWidget(host(overlay(code: '123', onDone: (_) => calls++)));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(calls, 1);
  });
}
