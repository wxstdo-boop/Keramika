import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест на «доверенную» самопереустановку.
///
/// Тихий путь обновления держится на двух вещах, которые легко случайно
/// снести при правках нативной части:
///
///  1. разрешения `UPDATE_PACKAGES_WITHOUT_USER_ACTION` и
///     `ENFORCE_UPDATE_OWNERSHIP` в манифесте (оба `normal`, выдаются сами);
///  2. `setRequireUserAction(USER_ACTION_NOT_REQUIRED)` в сессии
///     `PackageInstaller` — с `USER_ACTION_REQUIRED` система показывает
///     диалог на КАЖДОМ обновлении, и тихая установка становится
///     невозможной.
///
/// Проверяем тексты файлов: собрать APK и установить его в CI негде, а эти
/// две строки — единственное, что отличает «тихое» обновление от «спросить
/// каждый раз». Падение теста означает, что фичу сломали молча.
void main() {
  test('манифест объявляет разрешения доверенного самообновления', () {
    final file = File('android/app/src/main/AndroidManifest.xml');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден AndroidManifest.xml — тест запущен не из корня проекта',
    );
    final manifest = file.readAsStringSync();

    for (final permission in const [
      'android.permission.REQUEST_INSTALL_PACKAGES',
      'android.permission.ENFORCE_UPDATE_OWNERSHIP',
      'android.permission.UPDATE_PACKAGES_WITHOUT_USER_ACTION',
    ]) {
      expect(
        manifest,
        contains(permission),
        reason:
            'В манифесте нет разрешения $permission — тихое самообновление '
            'перестанет работать',
      );
    }
  });

  test('сессия установки просит систему обойтись без подтверждения', () {
    final file = File(
      'android/app/src/main/kotlin/com/wetidom/keramika/MainActivity.kt',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден MainActivity.kt — тест запущен не из корня проекта',
    );
    final source = file.readAsStringSync();

    expect(
      source,
      contains('USER_ACTION_NOT_REQUIRED'),
      reason:
          'Сессия установки больше не просит тихий путь — вернулся диалог '
          'на каждом обновлении',
    );
    expect(
      source,
      isNot(contains('USER_ACTION_REQUIRED,')),
      reason:
          'USER_ACTION_REQUIRED гарантирует подтверждение на каждом '
          'обновлении: это ломает доверенную установку',
    );
  });
}
