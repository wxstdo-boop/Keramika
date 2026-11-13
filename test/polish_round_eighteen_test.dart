import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест круга 18: окна события, плавность и единый стиль
/// подтверждений.
///
/// Каждая проверка закрывает конкретную жалобу владельца:
///  * обводка карточки события — полупрозрачно-АЛАЯ, а не сиреневая;
///  * цифры в событии меняются ПО ЦИФРАМ (кроссфейд), а не «колесом»;
///  * бейдж дня перекатывается вместе с волной, а не щёлкает;
///  * капсула подарка перетекает на 12-й день и при сбросе;
///  * переход скелетон → карточка (и кнопка «Забрать») идёт кроссфейдом;
///  * окна удаления/подтверждения — ЕДИНАЯ «стеклянная» карточка вместо
///    системного `AlertDialog`;
///  * в окне подтверждения кнопки отдают под пальцем.
void main() {
  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path не найден — тест не из корня',
    );
    return f.readAsStringSync();
  }

  /// Код без строк-комментариев: иначе проверки на подстроки ловят сами
  /// пояснения, в которых эти подстроки упомянуты.
  String code(String path) => read(
    path,
  ).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('обводка карточки события — полупрозрачно-алая', () {
    final src = code('lib/widgets/new_year_event_banner.dart');
    final start = src.indexOf('Widget _card(');
    expect(start, greaterThan(0));
    final body = src.substring(start, (start + 2600).clamp(0, src.length));
    expect(
      body.contains('BrandColors.red.withValues(alpha: isDark ? 0.42 : 0.34)'),
      isTrue,
      reason: 'кант карточки обязан быть алым и полупрозрачным',
    );
    expect(
      RegExp(r'border: Border\.all\(').hasMatch(body),
      isTrue,
      reason: 'кант остаётся, меняется только цвет',
    );
  });

  test('цифры события меняются посимвольно, а не «колесом»', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(src.contains('class _RollDigits'), isTrue);
    expect(src.contains('class _DigitSlot'), isTrue);
    expect(
      src.contains('RollingCounter('),
      isFalse,
      reason: 'барабан читался перекатыванием всего числа',
    );
    expect(
      src.contains("import '../widgets/rolling_counter.dart';"),
      isFalse,
      reason: 'мёртвый импорт барабана',
    );
    // Разряд оживает только если реально меняется при +1.
    expect(
      src.contains('final f = d0 == d1 ? 0.0 : fraction;'),
      isTrue,
      reason: 'иначе «3 → 4» крутило бы все разряды',
    );
    // Прозрачность — цветом, а не Opacity: saveLayer на разряд в каждом
    // кадре и был «лагом» события.
    final slot = src.substring(src.indexOf('class _DigitSlot'));
    expect(
      slot.contains('Opacity('),
      isFalse,
      reason: 'Opacity на разряд заводит saveLayer каждый кадр',
    );
    expect(
      slot.contains('withValues(alpha: fade.a *'),
      isTrue,
      reason: 'кроссфейд считается в альфе цвета',
    );
  });

  test('бейдж дня перекатывается вместе с волной', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final badge = src.substring(src.indexOf('class _DayBadge'));
    expect(
      badge.contains('_RollDigits('),
      isTrue,
      reason: 'день тоже меняется по цифрам, а не кадром',
    );
    expect(
      badge.contains('final double dayShown;'),
      isTrue,
      reason: 'бейдж идёт за дробным значением волны',
    );
    // В карточке бейдж обёрнут в AnimatedBuilder волны.
    final card = src.substring(
      src.indexOf('Widget _card('),
      src.indexOf('class _DayBadge'),
    );
    expect(
      RegExp(r'AnimatedBuilder\([\s\S]*?_DayBadge\(').hasMatch(card),
      isTrue,
      reason: 'бейдж обязан перестраиваться от _hatsCtrl',
    );
  });

  test('капсула подарка перетекает, а не переключается кадром', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final anchor = src.indexOf("Translations.t('nyGiftHint'");
    final gift = src.substring((anchor - 700).clamp(0, src.length), anchor);
    expect(
      gift.contains('_SwapBox('),
      isTrue,
      reason: 'текст подарка меняется кроссфейдом',
    );
  });

  test('переход скелетон → карточка идёт кроссфейдом', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final start = src.indexOf('_loading || !NewYearEventService.isActive');
    expect(start, greaterThan(0));
    final around = src.substring((start - 900).clamp(0, src.length), start);
    expect(
      around.contains('AnimatedSwitcher('),
      isTrue,
      reason: 'кнопка «Забрать» не должна выскакивать одним кадром',
    );
  });

  test('кривая длинных волн — симметричная, без рывка на краях', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(
      src.contains('delta >= 4 ? Curves.easeInOutCubic : Curves.easeOutCubic'),
      isTrue,
      reason: '0→12 и сброс обязаны трогаться и останавливаться мягко',
    );
  });

  test('окна удаления/подтверждения — единая «стеклянная» карточка', () {
    final src = read('lib/widgets/agysha_confirm_dialog.dart');
    expect(src.contains('class AgyshaConfirmDialog'), isTrue);
    expect(src.contains('Future<bool?> showAgyshaConfirm('), isTrue);
    expect(
      src.contains('BrandColors.red'),
      isTrue,
      reason: 'кант и подложка — в брендовом алом',
    );
    expect(
      src.contains('PressScale('),
      isTrue,
      reason: 'кнопки обязаны отдавать под пальцем',
    );
    expect(
      src.contains('pressedScale: 0.97'),
      isTrue,
      reason: 'отдача нарочно слабая',
    );
    expect(
      src.contains('showGeneralDialog<bool>('),
      isTrue,
      reason: 'барьер затемняет сам маршрут, без двойного скрима',
    );
    expect(
      src.contains('showDialog<bool>('),
      isFalse,
      reason: 'системный путь не используется',
    );
  });

  test('окна удаления/сброса переведены на общий вид', () {
    // Файлы, где окна удаления/подтверждения были ЕДИНСТВЕННЫМИ окнами:
    // системного `AlertDialog` там остаться не должно вовсе.
    const clean = {
      'lib/screens/tasks_screen.dart',
      'lib/screens/habits_screen.dart',
      'lib/screens/alarms_screen.dart',
      'lib/screens/reality_checks_screen.dart',
      'lib/screens/nutrition_screen.dart',
      'lib/screens/settings_screen.dart',
      'lib/screens/startup_recovery_screen.dart',
      'lib/widgets/ai_guide.dart',
    };
    for (final path in clean) {
      final src = code(path);
      expect(
        src.contains('showAgyshaConfirm('),
        isTrue,
        reason: '$path ещё на системном окне',
      );
      expect(
        src.contains('AlertDialog('),
        isFalse,
        reason: '$path не должен оставлять системное окно',
      );
    }
    // Здесь кроме удаления категории есть ещё окна ВВОДА имени (они остаются
    // системными: в них живёт поле ввода): проверяем только удаление.
    final addTask = code('lib/screens/add_task_screen.dart');
    expect(addTask.contains('showAgyshaConfirm('), isTrue);
    expect(
      addTask.contains("'deleteCategory'"),
      isTrue,
      reason: 'удаление категории осталось, но уже на общей карточке',
    );
    // Там остались ТОЛЬКО окна ВВОДА имени — на общей карточке их нет.
    expect(
      RegExp(r'AlertDialog\(').allMatches(addTask).length,
      2,
      reason: 'два окна ввода имени (создание и переименование)',
    );
  });
}
