import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест на самообновление и на профиль возможностей установки APK.
///
/// История: сперва установка шла сессией `PackageInstaller` с обычным
/// подтверждением — Play Protect показывал «требуется проверка», и это было
/// терпимо. Затем был включён ТИХИЙ путь
/// (`USER_ACTION_NOT_REQUIRED` + разрешение
/// `UPDATE_PACKAGES_WITHOUT_USER_ACTION`), и вердикт сменился на «вредоносное
/// приложение заблокировано»: установка APK без подтверждения — это ровно то
/// поведение, по которому Play Protect метит незнакомые сайдлоады как malware.
///
/// Поэтому инвариант обратный: разрешения на тихую установку в манифесте быть
/// НЕ должно, а сессия обязана запрашивать обычный системный экран. Проверяем
/// тексты файлов: собрать APK и установить его в CI негде.
void main() {
  test('манифест не объявляет разрешение тихой самопереустановки', () {
    final file = File('android/app/src/main/AndroidManifest.xml');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден AndroidManifest.xml — тест запущен не из корня проекта',
    );
    final manifest = file.readAsStringSync();

    // Считаем только действующие объявления: строка `uses-permission` с этим
    // именем. Упоминание в комментарии (объяснение, почему разрешения нет)
    // тестом не считается.
    final declared = RegExp(
      r'<uses-permission[^>]*android\.permission\.UPDATE_PACKAGES_WITHOUT_USER_ACTION',
    ).hasMatch(manifest);
    expect(
      declared,
      isFalse,
      reason:
          'Разрешение UPDATE_PACKAGES_WITHOUT_USER_ACTION вернулось в манифест: '
          'тихая установка APK без подтверждения — триггер Play Protect '
          '«вредоносное приложение»',
    );

    expect(
      manifest,
      contains('android.permission.REQUEST_INSTALL_PACKAGES'),
      reason: 'Без REQUEST_INSTALL_PACKAGES самообновление не работает вовсе',
    );
  });

  test('сессия установки запрашивает обычное подтверждение', () {
    final file = File(
      'android/app/src/main/kotlin/com/wetidom/keramika/MainActivity.kt',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден MainActivity.kt — тест запущен не из корня проекта',
    );
    // Комментарии объясняют, почему тихий путь НЕ используется, и содержат
    // имя константы. Проверяем только код: строки комментариев отбрасываем,
    // иначе тест ловил бы собственное пояснение.
    final code = file
        .readAsLinesSync()
        .where((line) {
          final t = line.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
        })
        .join('\n');

    expect(
      code,
      contains('USER_ACTION_REQUIRED,'),
      reason:
          'Сессия установки больше не запрашивает системный экран — вернулся '
          'тихий путь, который Play Protect метит как вредоносное ПО',
    );
    expect(
      code,
      isNot(contains('USER_ACTION_NOT_REQUIRED')),
      reason:
          'USER_ACTION_NOT_REQUIRED снова просит тихую установку без '
          'подтверждения — это и включало «вредоносное приложение»',
    );
  });

  test('при блокировке установки есть путь в настройки Play Protect', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/wetidom/keramika/MainActivity.kt',
    ).readAsStringSync();
    final installer = File('lib/services/installer.dart').readAsStringSync();

    expect(
      mainActivity,
      contains('openPlayProtectSettings'),
      reason:
          'Нативный канал больше не умеет открыть Play Protect — тупик при '
          'блокировке установки вернётся',
    );
    expect(
      installer,
      contains('openPlayProtectSettings'),
      reason:
          'Installer больше не пробрасывает openPlayProtectSettings в '
          'интерфейс — кнопка «Открыть» в снекбаре перестанет работать',
    );
  });
}
