import 'package:flutter_test/flutter_test.dart';
import 'package:pitanie/features/wearables/app_meta.dart';

void main() {
  test('системные и известные приложения называются без сети', () {
    expect(appName('com.apple.mobilephone', {}), 'Телефон');
    expect(appName('ru.oneme.app', {}), 'MAX');
    expect(appName('ph.telegra.Telegraph', {}), 'Telegram');
  });

  test('кэш App Store используется, встроенное имя главнее', () {
    final cache = {
      'com.vk.vkclient': const AppMeta('VK', 'https://x/y.png'),
      'com.apple.mobilephone': const AppMeta('Phone'),
    };
    expect(appName('com.vk.vkclient', cache), 'VK');
    expect(appName('com.apple.mobilephone', cache), 'Телефон');
  });

  test('запасное имя из идентификатора', () {
    expect(deriveAppName('com.uvehicle.car.app'), 'Uvehicle');
    expect(deriveAppName('apps.homepreserves.prohome'), 'Homepreserves');
    expect(deriveAppName(''), '');
  });

  test('кэш сохраняется и читается', () {
    final m = {'a.b': const AppMeta('Имя', 'https://i/1.png')};
    final back = decodeAppMeta(encodeAppMeta(m));
    expect(back['a.b']!.name, 'Имя');
    expect(back['a.b']!.iconUrl, 'https://i/1.png');
    expect(decodeAppMeta('мусор'), isEmpty);
    expect(decodeAppMeta(null), isEmpty);
  });
}
