import 'package:flutter/foundation.dart';

import 'installer.dart';

/// Версия приложения, которую видит пользователь.
///
/// Источник истины — `pubspec.yaml`. Значение [kAppVersion] ДОЛЖНО совпадать
/// с ним: регрессия `app_version_test.dart` сверяет оба и падает при
/// расхождении. Так забытая строка версии ловится на CI, а не глазами
/// пользователя в «О приложении».
///
/// На Android во время работы значение уточняется из установленного APK
/// ([Installer.appInfo]) — это снимает расхождение даже в сборке, собранной
/// из другой ветки. На web и десктопе канала нет, поэтому остаётся
/// константа.
const String kAppVersion = '1.6.78';

/// Текущая версия: константа, уточнённая данными из манифеста, если они
/// доступны.
class AppVersion {
  AppVersion._();

  static final ValueNotifier<String> _current = ValueNotifier<String>(
    kAppVersion,
  );

  /// Версия, которую сейчас показываем пользователю.
  static String get current => _current.value;

  /// Подписчик на смену версии (экран настроек перерисовывается сам).
  static ValueListenable<String> get listenable => _current;

  /// Уточняет версию по установленному APK. Ошибка канала — не повод
  /// ничего ломать: остаётся значение из `pubspec.yaml`.
  static Future<String> refresh() async {
    try {
      final info = await Installer.appInfo();
      final name = info?.versionName.trim() ?? '';
      if (name.isNotEmpty && name != _current.value) {
        _current.value = name;
      }
    } catch (_) {
      // Канал недоступен (web, тесты, десктоп) — оставляем константу.
    }
    return _current.value;
  }
}
