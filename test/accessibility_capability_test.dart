import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест на минимальность профиля «Специальных возможностей».
///
/// Play Protect судит о приложении по тому, ЧТО оно объявляет уметь, а не
/// по тому, как его ставят. Чтение чужого экрана — самая чувствительная
/// возможность из всего манифеста, поэтому объявленный доступ должен быть
/// ровно таким, каким его использует код:
///
///  * `ScreenReaderService` обходит дерево от `event.source` /
///    `rootInActiveWindow` и читает только `text` и `contentDescription`;
///  * `getWindows()` не вызывается → `flagRetrieveInteractiveWindows` не нужен;
///  * ресурсные id вью не читаются → `flagReportViewIds` не нужен;
///  * жесты и перехват клавиш не используются.
///
/// Лишняя объявленная возможность не даёт приложению ничего, но расширяет
/// профиль до «шпионского». Тест падает, если флаги вернут «на всякий случай».
void main() {
  late String config;

  setUpAll(() {
    final file = File(
      'android/app/src/main/res/xml/screen_reader_config.xml',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Не найден screen_reader_config.xml — тест запущен не из корня проекта',
    );
    // Комментарии объясняют, чего здесь НЕТ, и упоминают имена флагов —
    // проверяем только действующие атрибуты, без текста комментариев.
    config = file.readAsStringSync().replaceAll(
      RegExp(r'<!--.*?-->', dotAll: true),
      '',
    );
  });

  test('сервис чтения экрана просит только то, что использует', () {
    for (final flag in const [
      'flagReportViewIds',
      'flagRetrieveInteractiveWindows',
    ]) {
      expect(
        config,
        isNot(contains(flag)),
        reason:
            'Конфиг снова просит $flag, хотя код это не использует: '
            'расширяет профиль приложения без пользы',
      );
    }
    expect(config, contains('flagDefault'));
  });

  test('жесты и перехват клавиш сервису не выданы', () {
    for (final capability in const [
      'canPerformGestures',
      'canRequestFilterKeyEvents',
      'canTakeScreenshot',
      'canRequestTouchExplorationMode',
    ]) {
      expect(
        config,
        isNot(contains(capability)),
        reason: 'Сервису выдана возможность $capability — она не нужна',
      );
    }
  });

  test('чтение текста и описание для пользователя на месте', () {
    expect(
      config,
      contains('canRetrieveWindowContent="true"'),
      reason: 'Без чтения контента сервис бесполезен',
    );
    expect(
      config,
      contains('screen_reader_desc'),
      reason: 'У сервиса должно быть понятное описание для пользователя',
    );
  });
}
