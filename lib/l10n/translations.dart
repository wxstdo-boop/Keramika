import 'package:flutter/widgets.dart';
import 'locale_provider.dart';
import '../models/alarm.dart';

part 'translations_en.dart';
part 'translations_ru.dart';
part 'translations_fr.dart';

class Translations {
  Translations._();

  /// Словари переводов в исходном виде — только для тестов.
  ///
  /// Отдаём наружу, чтобы тест паритета работал с настоящими данными
  /// приложения, а не с разбором исходника текстом: многострочные значения
  /// и значения в кавычках такой разбор ломает. Ключи приватные, поэтому
  /// наружу смотрит только сам тест.
  @visibleForTesting
  static Map<String, Map<String, String>> get rawData => _data;

  static const _data = <String, Map<String, String>>{
    'en': _en,
    'ru': _ru,
    'fr': _fr,
  };

  static String _lookup(String key, BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    // Забытый перевод НЕ должен показываться пользователю как «someKeyName».
    // Сначала пробуем текущую локаль, потом английский как надёжный
    // источник, и лишь в самом конце — сам ключ (такого ключа в словарях
    // просто нет: об этом предупреждает тест паритета локалей).
    return byLocale[key] ?? _data['en']![key] ?? key;
  }

  static String t(String key, BuildContext context, [String? fallback]) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    // Порядок: текущая локаль → явный фолбек → английский → сам ключ.
    // Фолбек раньше стоял раньше английского намеренно (вызывающий код
    // знает, что писать), поэтому его приоритет сохраняем.
    return _emdash(byLocale[key] ?? fallback ?? _data['en']![key] ?? key);
  }

  /// В приложении всё, что выглядит как «-», должно быть длинным тире «—».
  /// Проходим по строке и заменяем дефисы между словами.
  static String _emdash(String s) {
    var out = s;
    // Цифра → дефис → «слово» и «слово — слово» (вокруг — пробелы).
    out = out.replaceAllMapped(
      RegExp(r'(\d)\s*-\s*(\d|\p{L})'),
      (m) => '${m[1]}—${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'(\p{L}|,)\s+-\s+(\p{L})', unicode: true),
      (m) => '${m[1]} — ${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'(\p{L})\s+-\s(\p{L})', unicode: true),
      (m) => '${m[1]} — ${m[2]}',
    );
    return out;
  }

  static String aboutOf(BuildContext context) => _lookup('about', context);
  static String alarmsOf(BuildContext context) => _lookup('alarms', context);
  static String allOf(BuildContext context) => _lookup('all', context);
  static String backOf(BuildContext context) => _lookup('back', context);
  static String batteryOpenedOf(BuildContext context) =>
      _lookup('batteryOpened', context);
  static String batteryOptDescOf(BuildContext context) =>
      _lookup('batteryOptDesc', context);
  static String batteryOptimizationOf(BuildContext context) =>
      _lookup('batteryOptimization', context);
  static String cancelOf(BuildContext context) => _lookup('cancel', context);
  static String categoryOf(BuildContext context) =>
      _lookup('category', context);
  static String changePinOf(BuildContext context) =>
      _lookup('changePin', context);
  static String darkOf(BuildContext context) => _lookup('dark', context);
  static String deleteOf(BuildContext context) => _lookup('delete', context);
  static String diagnosticsOf(BuildContext context) =>
      _lookup('diagnostics', context);
  static String editAlarmOf(BuildContext context) =>
      _lookup('editAlarm', context);
  static String englishOf(BuildContext context) => _lookup('english', context);
  static String followSystemOf(BuildContext context) =>
      _lookup('followSystem', context);
  static String frenchOf(BuildContext context) => _lookup('french', context);
  static String fullscreenNotifDescOf(BuildContext context) =>
      _lookup('fullscreenNotifDesc', context);
  static String habitsOf(BuildContext context) => _lookup('habits', context);
  static String labelOf(BuildContext context) => _lookup('label', context);
  static String languageOf(BuildContext context) =>
      _lookup('language', context);
  static String lightOf(BuildContext context) => _lookup('light', context);
  static String madeWithLoveOf(BuildContext context) =>
      _lookup('madeWithLove', context);
  static String newAlarmOf(BuildContext context) =>
      _lookup('newAlarm', context);
  static String noAlarmsOf(BuildContext context) =>
      _lookup('noAlarms', context);
  static String noHabitsOf(BuildContext context) =>
      _lookup('noHabits', context);
  static String noRealityChecksOf(BuildContext context) =>
      _lookup('noRealityChecks', context);
  static String noTasksOf(BuildContext context) => _lookup('noTasks', context);
  static String notificationsDescOf(BuildContext context) =>
      _lookup('notificationsDesc', context);
  static String notificationsOf(BuildContext context) =>
      _lookup('notifications', context);
  static String okOf(BuildContext context) => _lookup('ok', context);
  static String peachOf(BuildContext context) => _lookup('peach', context);
  static String roseOf(BuildContext context) => _lookup('rose', context);
  static String pinDescriptionOf(BuildContext context) =>
      _lookup('pinDescription', context);
  static String pinLockOf(BuildContext context) => _lookup('pinLock', context);
  static String rcOf(BuildContext context) => _lookup('rc', context);
  static String realityChecksOf(BuildContext context) =>
      _lookup('realityChecks', context);
  static String refreshOf(BuildContext context) => _lookup('refresh', context);
  static String removePinOf(BuildContext context) =>
      _lookup('removePin', context);
  static String repeatOf(BuildContext context) => _lookup('repeat', context);
  static String russianOf(BuildContext context) => _lookup('russian', context);
  static String saveOf(BuildContext context) => _lookup('save', context);
  static String clearNoteOf(BuildContext context) =>
      _lookup('clearNote', context);
  static String taskNoteClearedOf(BuildContext context) =>
      _lookup('taskNoteCleared', context);
  static String taskNoteSavedOf(BuildContext context) =>
      _lookup('taskNoteSaved', context);
  static String setPinOf(BuildContext context) => _lookup('setPin', context);
  static String settingsOf(BuildContext context) =>
      _lookup('settings', context);
  static String soundOf(BuildContext context) => _lookup('sound', context);
  static String systemOf(BuildContext context) => _lookup('system', context);
  static String tapToChangeOf(BuildContext context) =>
      _lookup('tapToChange', context);
  static String tasksOf(BuildContext context) => _lookup('tasks', context);
  static String themeOf(BuildContext context) => _lookup('theme', context);
  static String uncategorizedOf(BuildContext context) =>
      _lookup('uncategorized', context);
  static String vibrateOf(BuildContext context) => _lookup('vibrate', context);
  static String wakeUpTaskOf(BuildContext context) =>
      _lookup('wakeUpTask', context);
  static String welcomeBodyOf(BuildContext context) =>
      _lookup('welcomeBody', context);
  static String welcomeGoOf(BuildContext context) =>
      _lookup('welcomeGo', context);
  static String welcomeSkipOf(BuildContext context) =>
      _lookup('welcomeSkip', context);
  static String welcomeTitleOf(BuildContext context) =>
      _lookup('welcomeTitle', context);

  static List<String> dayNames(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    return [
      byLocale['dayMon']!,
      byLocale['dayTue']!,
      byLocale['dayWed']!,
      byLocale['dayThu']!,
      byLocale['dayFri']!,
      byLocale['daySat']!,
      byLocale['daySun']!,
    ];
  }

  static String repeatLabel(BuildContext context) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    return byLocale['repeat'] ?? 'Repeat';
  }

  static String repeatDaysLabel(BuildContext context, Alarm alarm) {
    final code = LocaleProvider.of(context).languageCode;
    final byLocale = _data[code] ?? _data['en']!;
    if (alarm.repeatDays.isEmpty) return byLocale['labelOnce'] ?? 'Once';
    if (alarm.repeatDays.length == 7) {
      return byLocale['labelEveryDay'] ?? 'Every day';
    }
    final names = dayNames(context);
    if (alarm.repeatDays.length == 5 &&
        !alarm.repeatDays.contains(6) &&
        !alarm.repeatDays.contains(7)) {
      return byLocale['labelWeekdays'] ?? 'Weekdays';
    }
    if (alarm.repeatDays.length == 2 &&
        alarm.repeatDays.contains(6) &&
        alarm.repeatDays.contains(7)) {
      return byLocale['labelWeekends'] ?? 'Weekends';
    }
    return alarm.repeatDays.map((d) => names[d - 1]).join(', ');
  }
}
