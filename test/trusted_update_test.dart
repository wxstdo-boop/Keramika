import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест на самообновление и на профиль возможностей установки APK.
///
/// История вердиктов Play Protect:
///  * сессия `PackageInstaller` с обычным подтверждением — «требуется
///    проверка», установка шла, но система считала нас владельцем своих
///    обновлений (`ENFORCE_UPDATE_OWNERSHIP`) и трактовала установку как
///    самообновление в обход пользователя;
///  * тихий путь (`USER_ACTION_NOT_REQUIRED` + разрешение
///    `UPDATE_PACKAGES_WITHOUT_USER_ACTION`) — вердикт сменился на
///    «вредоносное приложение заблокировано», установка перестала проходить.
///
/// Итог: самообновление ставит ОБЫЧНЫЙ системный установщик
/// (`Intent.ACTION_VIEW` через FileProvider). Никаких разрешений на установку
/// без подтверждения и никакого объявления себя владельцем обновлений в
/// манифесте быть не должно — именно они ужесточают вердикт. Проверяем тексты
/// файлов: собрать APK и установить его в CI негде.
void main() {
  test('манифест не просит разрешений, ужесточающих вердикт Play Protect', () {
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
    for (final perm in const [
      'UPDATE_PACKAGES_WITHOUT_USER_ACTION',
      'ENFORCE_UPDATE_OWNERSHIP',
    ]) {
      final declared = RegExp(
        r'<uses-permission[^>]*android\.permission\.$perm',
      ).hasMatch(manifest);
      expect(
        declared,
        isFalse,
        reason:
            'Разрешение $perm вернулось в манифест: оно включает установку без '
            'подтверждения/в обход пользователя — триггер Play Protect '
            '«вредоносное приложение»',
      );
    }

    expect(
      manifest,
      contains('android.permission.REQUEST_INSTALL_PACKAGES'),
      reason: 'Без REQUEST_INSTALL_PACKAGES система не покажет экран установки',
    );
  });

  test('установку ставит обычный системный установщик, а не сессия', () {
    final file = File(
      'android/app/src/main/kotlin/com/wetcorp/agysha/MainActivity.kt',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден MainActivity.kt — тест запущен не из корня проекта',
    );
    // Комментарии объясняют, почему сессии нет, и содержат её имя. Проверяем
    // только код: строки комментариев отбрасываем, иначе тест ловил бы
    // собственное пояснение.
    final code = file
        .readAsLinesSync()
        .where((line) {
          final t = line.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              !t.startsWith('/*');
        })
        .join('\n');

    expect(
      code,
      contains('installWithSystemInstaller'),
      reason:
          'Установка больше не идёт обычным системным установщиком — вернулась '
          'сессия PackageInstaller, которая ужесточает вердикт Play Protect',
    );
    expect(
      code,
      isNot(contains('PackageInstaller.SessionParams')),
      reason:
          'В коде снова создаётся сессия PackageInstaller — самообновление '
          'опять выглядит как установка в обход пользователя',
    );
    expect(
      code,
      isNot(contains('USER_ACTION_NOT_REQUIRED')),
      reason:
          'USER_ACTION_NOT_REQUIRED снова просит тихую установку без '
          'подтверждения — это и включало «вредоносное приложение»',
    );
  });

  test('приёмник и мост сессии PackageInstaller удалены', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/wetcorp/agysha/MainActivity.kt',
    ).readAsStringSync();

    expect(
      manifest,
      isNot(contains('InstallResultReceiver')),
      reason:
          'Приёмник результатов сессии снова объявлен в манифесте: система '
          'опять увидит путь самообновления через PackageInstaller',
    );
    expect(
      File(
        'android/app/src/main/kotlin/com/wetcorp/agysha/'
        'InstallResultReceiver.kt',
      ).existsSync(),
      isFalse,
      reason:
          'Файл приёмника сессии вернулся — это запасной путь тихой установки, '
          'который ужесточает вердикт Play Protect',
    );
    expect(
      File(
        'android/app/src/main/kotlin/com/wetcorp/agysha/UpdaterBridge.kt',
      ).existsSync(),
      isFalse,
      reason:
          'Мост сессии вернулся — значит в код снова пишется придержанный '
          'результат установки, то есть вернулся путь PackageInstaller',
    );
    expect(
      mainActivity,
      isNot(contains('UpdaterBridge')),
      reason: 'MainActivity снова тянется к мосту сессии PackageInstaller',
    );
  });
}
