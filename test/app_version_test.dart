import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/services/app_version.dart';

/// Регресс-тест: версия в приложении и версия в `pubspec.yaml` не должны
/// расходиться.
///
/// История: в `lib/l10n/translations.dart` жила константа
/// `const appVersion = '1.3';`, и экран «О приложении» показывал «v1.3»
/// даже когда приложение было на 1.6.72. Константа была единственным
/// экземпляром версии в коде, поэтому забыть её обновить было легко, а
/// заметить — невозможно.
///
/// Тест сверяет `kAppVersion` с `pubspec.yaml`: расхождение валит CI.
void main() {
  test('kAppVersion совпадает с версией в pubspec.yaml', () {
    final file = File('pubspec.yaml');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден pubspec.yaml — тест запущен не из корня проекта',
    );

    final match = RegExp(
      r'^version:\s*([0-9][^+\s]*)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(file.readAsStringSync());

    expect(
      match,
      isNotNull,
      reason:
          'В pubspec.yaml нет строки вида "version: 1.2.3+456" — формат '
          'версии нарушен',
    );

    final versionName = match!.group(1)!;
    expect(
      kAppVersion,
      versionName,
      reason:
          'kAppVersion в lib/services/app_version.dart ($kAppVersion) не '
          'совпадает с версией в pubspec.yaml ($versionName). '
          'Обнови константу — иначе приложение покажет не ту версию.',
    );
  });

  test('версия выглядит как versionName, а не как versionCode', () {
    // versionCode в приложении — с прибавкой индекса ABI (Flutter делает
    // это для split-APK), поэтому показывать его нельзя. Показываем имя.
    expect(
      kAppVersion,
      isNot(contains('+')),
      reason: 'kAppVersion — это versionName, без build number',
    );
    expect(
      RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kAppVersion),
      isTrue,
      reason: 'Ожидался вид «major.minor.patch», получено «$kAppVersion»',
    );
  });

  test('AppVersion.current доступен без канала', () {
    // На web/десктопе и в тестах нативного канала нет — значение всё
    // равно должно быть осмысленным, а не пустым.
    expect(AppVersion.current, isNotEmpty);
    expect(AppVersion.current, kAppVersion);
  });
}
