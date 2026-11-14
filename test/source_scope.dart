import 'dart:io';

/// Исходник экрана настроек ВМЕСТЕ со всеми его part-файлами.
///
/// Экран разбит на части (`settings_section_*.dart`, `settings_*.dart`), и
/// тест, который проверяет код по тексту, не должен зависеть от того, в каком
/// именно файле лежит строка: собираем библиотеку целиком в порядке объявления
/// `part`-директив. Иначе вынос раздела в отдельный файл ломает регресс-тест,
/// хотя поведение не менялось.
String readSettingsLibrary() {
  const mainPath = 'lib/screens/settings_screen.dart';
  final main = File(mainPath);
  if (!main.existsSync()) {
    throw StateError('$mainPath не найден — тест не из корня проекта');
  }
  final mainSource = main.readAsStringSync();
  final parts = RegExp(r"^part '([^']+)';", multiLine: true)
      .allMatches(mainSource)
      .map((m) => m.group(1)!)
      .toList();

  final buffer = StringBuffer(mainSource);
  for (final part in parts) {
    final file = File('lib/screens/$part');
    if (!file.existsSync()) {
      throw StateError('part-файл lib/screens/$part не найден');
    }
    buffer
      ..write('\n')
      ..write(file.readAsStringSync());
  }
  return buffer.toString();
}
