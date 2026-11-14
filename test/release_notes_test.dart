import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест заметок релиза: служебные коммиты не должны попадать в
/// «Что нового» ни на GitHub, ни в fastlane-changelog для F-Droid.
///
/// Раньше фильтр был одной строкой `grep -v '^- release:'` прямо в ship.yml,
/// и в релиз утекали заголовки вида «F-Droid: рецепт на тег…» и
/// «docs(AGENTS): …» — пользователь видел внутреннюю кухню. Теперь фильтр
/// живёт в `tool/release_notes.sh` и проверяется здесь на реальном запуске.
void main() {
  /// Есть ли в системе настоящий `bash`.
  ///
  /// Скрипт фильтра — POSIX-shell, и на Windows (`bash` нет в PATH) проверка
  /// не запускается, а падала бы тройным падением «exit code 1» с пустым
  /// выводом: тест выглядел красным, хотя код в порядке. В CI (ubuntu) bash
  /// есть, поэтому там проверки идут в полном объёме; локально на Windows
  /// они честно помечаются как пропущенные, а не «сломанные».
  final skipWithoutBash = _bashAvailable() ? null : 'нужен bash (есть в CI)';

  /// Прогоняет настоящий скрипт (не мок) и возвращает его stdout.
  ///
  /// Вызывается только когда bash доступен (см. [skipWithoutBash]).
  String filter(String input) {
    final script = File('tool/release_notes.sh');
    expect(script.existsSync(), isTrue,
        reason: 'tool/release_notes.sh не найден — тест не из корня');

    // Скрипт читает stdin; Process.runSync не умеет его заполнять, поэтому
    // подаём вход через временный файл.
    final tmp = File('${Directory.systemTemp.path}/release_notes_in.txt')
      ..writeAsStringSync(input);
    final res = Process.runSync('bash', [
      '-c',
      'bash ${script.path} < ${tmp.path}',
    ]);
    tmp.deleteSync();
    expect(res.exitCode, 0,
        reason: 'фильтр заметок обязан завершаться успешно');
    return res.stdout as String;
  }

  test('служебные коммиты отсеиваются, пользовательские остаются', () {
    // Ниже — реальные заголовки из истории Agysha, включая те, что уже
    // протекали в changelog 45243.
    const input = '''
- Зайчик обновления ожил: живой подскок и читаемый глиф
- F-Droid: зафиксировать результаты валидации и шаги подачи
- F-Droid: рецепт на тег v1.6.170+45242
- docs(AGENTS): Impeller-блюр, дыхание значка
- docs: актуализировать счётчики и версию Dart
- ship: класть changelog версии в релизный коммит
- release: v1.6.171+45243
- Переименование: пакет com.wetcorp.agysha
- chore: поднять зависимости
- ci: кэш pub
- style: формат
- test: покрыть зайчика
- build: NDK
- refactor: вынести хелпер
- feat: экспорт привычек в CSV
- fix(storage): не терять данные при апдейте
- Питание: строка БЖУ без переполнения
- Полировка 12-го круга: канты и свечение
''';
    final out = filter(input);
    final lines = out.trim().split('\n');

    // Осталось ровно то, что интересно пользователю.
    expect(lines, [
      '- Зайчик обновления ожил: живой подскок и читаемый глиф',
      '- feat: экспорт привычек в CSV',
      '- fix(storage): не терять данные при апдейте',
      '- Питание: строка БЖУ без переполнения',
      '- Полировка 12-го круга: канты и свечение',
    ]);
  }, skip: skipWithoutBash);

  test('пустой вход — пустой выход и нулевой код возврата', () {
    // Пустой changelog F-Droid отбрасывает; вызывающая сторона подставляет
    // «- Обновление». Скрипт при этом не должен падать.
    expect(filter(''), '');
  }, skip: skipWithoutBash);

  test('в репозитории нет changelog со служебными пунктами', () {
    // Историю уже чистили вручную: до появления фильтра в changelog успели
    // просочиться «F-Droid: …» и «docs(AGENTS): …». Тест не даёт им вернуться.
    final dir = Directory('fastlane/metadata/android');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        // Путь под Windows приходит с обратными слэшами: без нормализации
        // список файлов оказывался пустым и тест падал на «не нашли ни
        // одного changelog» вместо проверки содержимого.
        .where((f) =>
            f.path.replaceAll('\\', '/').contains('/changelogs/') &&
            f.path.endsWith('.txt'))
        .toList();
    expect(files, isNotEmpty, reason: 'не нашли ни одного changelog');

    final dirty = <String>[];
    for (final f in files) {
      final body = f.readAsStringSync();
      for (final line in body.split('\n')) {
        if (line.trim().isEmpty) continue;
        if (filter('$line\n').trim().isEmpty) {
          dirty.add('${f.path}: $line');
        }
      }
    }
    expect(dirty, isEmpty, reason: 'служебные пункты в changelog: $dirty');
  }, skip: skipWithoutBash);
}

/// Проверяет, что `bash` реально запускается.
///
/// `Process.runSync` бросает `ProcessException`, если бинарника нет в PATH
/// (типичный Windows без Git Bash) — это и есть сигнал «пропустить прогон».
bool _bashAvailable() {
  try {
    return Process.runSync('bash', ['-c', 'exit 0']).exitCode == 0;
  } catch (_) {
    return false;
  }
}
