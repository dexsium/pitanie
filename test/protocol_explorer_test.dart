import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/protocol_explorer_page.dart';

void main() {
  test('стандартные UUID SIG отличаются от собственных', () {
    expect(isSigUuid('0000180a-0000-1000-8000-00805f9b34fb'), isTrue);
    expect(isSigUuid('0000fee1-0000-1000-8000-00805f9b34fb'), isTrue);
    expect(isSigUuid('00000009-0000-3512-2118-0009af100700'), isFalse);
  });

  test('разбор реального ответа GTR 4 выделяет неизвестные поля', () {
    final p = [0x02, 0x05, 0x64, 0x00, 0x01, 0x01, 0x05, 0x00, 1, 2, 3, 4, 5, 1, 1];
    final l = explainCaps(p);
    expect(l.first, contains('версия протокола 5'));
    expect(l.where((x) => x.startsWith('НЕИЗВЕСТНО')).length, 2);
    expect(l.any((x) => x.contains('значки приложений: поддерживаются')), isTrue);
    expect(l.any((x) => x.contains('01 02 03 04 05')), isTrue);
  });

  test('оборванный ответ не падает', () {
    expect(explainCaps([0x02]), isNotEmpty);
    expect(explainCaps([0x02, 0x05, 1, 2]).last, contains('оборван'));
  });

  test('статусы называются как в ТЗ', () {
    expect(probeStatusName(ProbeStatus.timeout), 'TIMEOUT');
    expect(probeStatusName(ProbeStatus.unsupported), 'UNSUPPORTED');
  });
}
