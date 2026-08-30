import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'prefs.dart';
import 'json_file.dart';

class SettingsService {
  static const _keyTheme = 'setting_theme';
  static const _keyLocale = 'setting_locale';
  static const _keyPeachDark = 'setting_peach_dark';
  static const _keyFontFamily = 'setting_font_family';
  static const _keyExperimental = 'setting_experimental';
  static const _keyAutoSave = 'setting_auto_save';
  static const _keyDevMode = 'setting_dev_mode';
  static const _keyAutoExport = 'setting_auto_export';
  static const _keyAiGuide = 'setting_ai_guide';
  static const _keyAiKey = 'setting_ai_key';
  static const _keyAiTracking = 'setting_ai_tracking';
  static const _keyPerfectionism = 'perfectionism_mode';
  static const _keyBerserk = 'berserk_mode';
  static const _keyTaskNotes = 'task_quick_notes_mode';
  static const _settingsFile = 'app_settings';

  /// Безопасное чтение bool из SharedPreferences: принимает true/false
  /// (bool) и 0/1 (int), иначе возвращает [defaultValue].
  static bool _bool(dynamic v, bool defaultValue) => v is bool
      ? v
      : v is num
      ? v != 0
      : defaultValue;

  static Future<Map<String, dynamic>> _loadSettings() async {
    try {
      final raw = await JsonFile.read(_settingsFile);
      if (raw != null && raw.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    return {};
  }

  static Future<void> _saveSettings(Map<String, dynamic> map) async {
    await JsonFile.write(_settingsFile, jsonEncode(map));
  }

  static Future<String> loadThemeMode() async {
    final map = await _loadSettings();
    final val = map[_keyTheme] as String? ?? globalPrefs.getString(_keyTheme);
    switch (val) {
      case 'mutilated':
        return 'mutilated';
      case 'light':
        return 'light';
      case 'dark':
        return 'dark';
      case 'grok':
        return 'grok';
      case 'darkGrok':
        return 'darkGrok';
      case 'systemLight':
        return 'systemLight';
      case 'system':
        return 'system';
      case 'rose':
        return 'rose';
      case 'peach':
        return 'peach';
      default:
        return 'peach';
    }
  }

  static Future<void> saveThemeMode(String mode) async {
    final map = await _loadSettings();
    map[_keyTheme] = mode;
    await _saveSettings(map);
  }

  static Future<String> loadFontFamily() async {
    final map = await _loadSettings();
    final value = map[_keyFontFamily] as String? ??
        globalPrefs.getString(_keyFontFamily);
    return value == 'caveat' ? 'caveat' : 'ordinary';
  }

  static Future<void> saveFontFamily(String family) async {
    final map = await _loadSettings();
    map[_keyFontFamily] = family == 'caveat' ? 'caveat' : 'ordinary';
    await _saveSettings(map);
  }

  static Future<String> loadLanguageCode() async {
    final map = await _loadSettings();
    final val = map[_keyLocale] as String? ?? globalPrefs.getString(_keyLocale);
    switch (val) {
      case 'en':
        return 'en';
      case 'ru':
        return 'ru';
      case 'fr':
        return 'fr';
      case 'system':
        return 'system';
      default:
        return 'system';
    }
  }

  /// Конкретный код языка ('ru'/'en'/'fr'): если пользователь выбрал
  /// «как в системе» ('system'), резолвим через язык устройства.
  /// Используется везде, где нужен реальный язык: награды Ады, промпт
  /// модели и т.п. — иначе 'system' превращал награды в английские.
  static Future<String> resolveLanguageCode() async {
    final code = await loadLanguageCode();
    if (code != 'system') return code;
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    for (final l in [dispatcher.locale, ...dispatcher.locales]) {
      final lang = l.languageCode;
      if (lang.startsWith('ru')) return 'ru';
      if (lang.startsWith('fr')) return 'fr';
      if (lang == 'en') return 'en';
    }
    return 'ru';
  }

  static Future<void> saveLanguageCode(String code) async {
    final map = await _loadSettings();
    map[_keyLocale] = code;
    await _saveSettings(map);
  }

  static Future<bool> loadPeachDark() async {
    final map = await _loadSettings();
    return _bool(map[_keyPeachDark], false);
  }

  static Future<void> savePeachDark(bool dark) async {
    final map = await _loadSettings();
    map[_keyPeachDark] = dark;
    await _saveSettings(map);
  }

  /// Живой флаг «экспериментальные таймеры» — секция таймеров появляется
  /// сразу при включении в настройках, без перезапуска.
  static final ValueNotifier<bool> experimentalEnabled = ValueNotifier<bool>(
    false,
  );

  static Future<bool> loadExperimental() async {
    final map = await _loadSettings();
    final v = _bool(map[_keyExperimental], false);
    experimentalEnabled.value = v;
    return v;
  }

  static Future<void> saveExperimental(bool value) async {
    final map = await _loadSettings();
    map[_keyExperimental] = value;
    await _saveSettings(map);
    experimentalEnabled.value = value;
  }

  static Future<bool> loadAutoSave() async {
    final map = await _loadSettings();
    return _bool(map[_keyAutoSave], false);
  }

  static Future<void> saveAutoSave(bool value) async {
    final map = await _loadSettings();
    map[_keyAutoSave] = value;
    await _saveSettings(map);
  }

  static Future<bool> loadDevMode() async {
    final map = await _loadSettings();
    return _bool(map[_keyDevMode], false);
  }

  static Future<void> saveDevMode(bool value) async {
    final map = await _loadSettings();
    map[_keyDevMode] = value;
    await _saveSettings(map);
  }

  /// Живой режим ежедневных карточек: экран привычек реагирует сразу,
  /// без перезапуска приложения.
  static final ValueNotifier<bool> perfectionismEnabled = ValueNotifier<bool>(
    false,
  );

  static Future<bool> loadPerfectionism() async {
    final map = await _loadSettings();
    final value = _bool(
      map[_keyPerfectionism],
      globalPrefs.getBool(_keyPerfectionism) ?? false,
    );
    perfectionismEnabled.value = value;
    return value;
  }

  static Future<void> savePerfectionism(bool value) async {
    final map = await _loadSettings();
    map[_keyPerfectionism] = value;
    await _saveSettings(map);
    perfectionismEnabled.value = value;
  }

  /// Разблокированный режим BERSERK — общий живой флаг для настроек и FAB.
  static final ValueNotifier<bool> berserkEnabled = ValueNotifier<bool>(false);

  static Future<bool> loadBerserk() async {
    final map = await _loadSettings();
    final value = _bool(
      map[_keyBerserk],
      globalPrefs.getBool(_keyBerserk) ?? false,
    );
    berserkEnabled.value = value;
    return value;
  }

  static Future<void> saveBerserk(bool value) async {
    final map = await _loadSettings();
    map[_keyBerserk] = value;
    await _saveSettings(map);
    berserkEnabled.value = value;
  }

  /// «Вспомнил, что использую…» — зажатие задачи (5 сек) открывает меню
  /// быстрого списка с красивой заметкой до 150 символов. Общий живой флаг
  /// для настроек и экрана задач.
  static final ValueNotifier<bool> taskNotesEnabled = ValueNotifier<bool>(
    false,
  );

  static Future<bool> loadTaskNotes() async {
    final map = await _loadSettings();
    final value = _bool(
      map[_keyTaskNotes],
      globalPrefs.getBool(_keyTaskNotes) ?? false,
    );
    taskNotesEnabled.value = value;
    return value;
  }

  static Future<void> saveTaskNotes(bool value) async {
    final map = await _loadSettings();
    map[_keyTaskNotes] = value;
    await _saveSettings(map);
    taskNotesEnabled.value = value;
  }

  static Future<bool> loadAutoExport() async {
    final map = await _loadSettings();
    return _bool(map[_keyAutoExport], false);
  }

  static Future<void> saveAutoExport(bool value) async {
    final map = await _loadSettings();
    map[_keyAutoExport] = value;
    await _saveSettings(map);
  }

  /// Живой флаг «проводник включён». Виджеты (кружок у «+») слушают его
  /// и появляются МГНОВЕННО при переключении в настройках — без перезапуска.
  static final ValueNotifier<bool> aiGuideEnabled = ValueNotifier<bool>(false);
  static Future<bool>? _aiGuideLoad;

  static Future<bool> loadAiGuide() {
    // Главный экран заранее держит несколько разделов; не запускаем один и
    // тот же JSON-read по одному разу для каждой кнопки Ады.
    return _aiGuideLoad ??= _readAiGuide();
  }

  static Future<bool> _readAiGuide() async {
    final map = await _loadSettings();
    final v = _bool(map[_keyAiGuide], false);
    aiGuideEnabled.value = v;
    return v;
  }

  static Future<void> saveAiGuide(bool value) async {
    final map = await _loadSettings();
    map[_keyAiGuide] = value;
    await _saveSettings(map);
    _aiGuideLoad = Future<bool>.value(value);
    aiGuideEnabled.value = value;
  }

  static Future<String> loadAiKey() async {
    final map = await _loadSettings();
    return (map[_keyAiKey] as String?) ?? '';
  }

  static Future<void> saveAiKey(String value) async {
    final map = await _loadSettings();
    map[_keyAiKey] = value.trim();
    await _saveSettings(map);
  }

  /// Ада-трекинг: утренний отчёт «что сегодня по плану» + вечерний разбор.
  static Future<bool> loadAiTracking() async {
    final map = await _loadSettings();
    return _bool(map[_keyAiTracking], true);
  }

  static Future<void> saveAiTracking(bool value) async {
    final map = await _loadSettings();
    map[_keyAiTracking] = value;
    await _saveSettings(map);
  }

  static Future<bool> loadAdaProactive() async => true;

  static Future<void> saveAdaProactive(bool value) async {}
}
