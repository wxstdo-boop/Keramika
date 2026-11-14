import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/translations.dart';
import '../main.dart' show navigatorKey;
import '../utils/snackbar.dart';
import 'json_file.dart';
import 'pin_service.dart';
import 'prefs.dart';
import 'settings_service.dart';

Timer? _autoExportTimer;
bool _isAutoExporting = false;
bool _autoExportEnabled = false;

const _lastAutoExportKey = 'last_auto_export_at';
// Нативка слушает saveToDownloads на канале alarm_payload (MainActivity).
// Раньше здесь был канал '.../backup' — вызов падал в MissingPluginException,
// и бэкап молча писался в невидимую папку Android/data вместо Download.
//
// Каналы создаём СРАЗУ, константами. Раньше они были `late final` и
// присваивались в `initChannels()`, но её никто не вызывал: первое же
// обращение к `_alarmPayloadChannel` в `_startApp()` падало с
// LateInitializationError, `setMethodCallHandler` не срабатывал — и тап по
// уведомлению будильника в уже запущенном приложении не открывал экран
// задачи (событие onNewAlarmPayload просто не долетало до Dart).
// `MethodChannel` создаётся дёшево и не трогает платформу до первого invoke,
// поэтому создание на web безопасно.
final MethodChannel _backupChannel = const MethodChannel(
  'com.wetcorp.agysha/alarm_payload',
);
// Канал сигналов жизненного цикла Activity → Dart (onNewIntent и т.п.).
const MethodChannel lifecycleChannel = MethodChannel(
  'com.wetcorp.agysha/lifecycle',
);

/// Включает автоэкспорт: разовый прогон (если нужно) + почасовой таймер.
/// [silent] — true для фоновых прогонов (старт/возврат в приложение),
/// чтобы не спамить снекбаром; ручное включение в настройках показывает
/// подтверждение.
void startAutoExport({bool runImmediately = true, bool silent = false}) {
  _autoExportEnabled = true;
  _autoExportTimer?.cancel();
  _autoExportTimer = null;
  if (runImmediately) {
    _autoExportTick(silent: silent);
  } else {
    _autoExportTimer = Timer(const Duration(hours: 1), _autoExportTick);
  }
}

Future<void> _autoExportTick({bool silent = false}) async {
  if (_isAutoExporting) return; // guard: не запускаем повторно
  _isAutoExporting = true;
  try {
    debugPrint('[auto-export] tick start');
    final saved = await _performAutoExport(showSnack: !silent);
    await globalPrefs.setInt(
      _lastAutoExportKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('[auto-export] OK -> $saved');
  } catch (e, st) {
    // Раньше сбой уходил ТОЛЬКО в debugPrint — в релизе пользователь не видел
    // ни файла, ни ошибки, и автоэкспорт выглядел «мёртвым». Теперь при
    // ручном включении показываем причину, чтобы сбой не был молчаливым.
    debugPrint('[auto-export] FAILED: $e\n$st');
    if (!silent) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showBeautifulSnackBar(
          ctx,
          message: Translations.t(
            'autoExportFailed',
            ctx,
            'Не удалось сохранить бэкап',
          ),
          icon: Icons.error_outline,
          iconColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        );
      }
    }
  } finally {
    _isAutoExporting = false;
    _autoExportTimer?.cancel();
    _autoExportTimer = _autoExportEnabled
        ? Timer(const Duration(hours: 1), _autoExportTick)
        : null;
  }
}

/// «Догоняющий» прогон: если автоэкспорт включён и с последнего бэкапа
/// прошёл час и больше (например, приложение было закрыто — Dart-таймер
/// в фоне не работает), делаем бэкап молча при старте или возврате в
/// приложение.
Future<void> maybeCatchUpAutoExport() async {
  final enabled = await SettingsService.loadAutoExport();
  debugPrint('[auto-export] catch-up: enabled=$enabled');
  if (!enabled) {
    stopAutoExport();
    return;
  }
  final last = globalPrefs.getInt(_lastAutoExportKey) ?? 0;
  final overdue =
      last == 0 ||
      DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(last))
              .inHours >=
          1;
  debugPrint('[auto-export] catch-up: last=$last overdue=$overdue');
  if (overdue) {
    startAutoExport(runImmediately: true, silent: true);
  } else {
    // Бэкап недавний — просто держим почасовой таймер в фоне приложения.
    startAutoExport(runImmediately: false);
  }
}

void stopAutoExport() {
  _autoExportEnabled = false;
  _autoExportTimer?.cancel();
  _autoExportTimer = null;
}

/// Builds the full backup payload used by manual and auto export.
///
/// При экспорте читаем данные из новых JsonFile-файлов, а если их нет —
/// добираем старые ключи из globalPrefs. Это поддерживает пользователей,
/// пришедших с версии, в которой данные хранились в SharedPreferences как
/// JSON-строки, но миграция ещё не отработала (или старый билд в проекте).
Future<Map<String, dynamic>> buildBackupPayload() async {
  final out = <String, dynamic>{};

  Future<String?> readWithFallback(String key) async {
    final fromFile = await JsonFile.read(key);
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    final fromPrefs = globalPrefs.getString(key);
    return fromPrefs;
  }

  out['habits'] = await readWithFallback('habits');
  out['tasks'] = await readWithFallback('tasks');
  out['task_categories'] = await readWithFallback('task_categories');
  out['alarms'] = await readWithFallback('alarms');
  out['app_timers'] = await readWithFallback('app_timers');
  out['reality_check_data'] = await readWithFallback('reality_check_data');
  out['nutrition_meals'] = await readWithFallback('nutrition_meals');
  out['ai_chat_history'] = await readWithFallback('ai_chat_history');
  out['ai_pinned_messages'] = await readWithFallback('ai_pinned_messages');
  out['ada_sync_state'] = await readWithFallback('ada_sync_state');
  out['completion_log'] = await readWithFallback('completion_log');
  out['ny_event_2027'] = await readWithFallback('ny_event_2027');

  // Old RC format: данные лежали в 'reality_checks' (имя списка) и в
  // отдельных prefs-ключах. Если нового файла нет — собираем пакет из старых.
  if (out['reality_check_data'] == null) {
    final checks = globalPrefs.getString('reality_checks');
    if (checks != null && checks.isNotEmpty) {
      out['reality_check_data'] = jsonEncode({
        'checks': checks,
        'checksPerDay': globalPrefs.getInt('rc_checks_per_day') ?? 10,
        'timeFromHour': 8,
        'timeFromMinute': 0,
        'timeToHour': 22,
        'timeToMinute': 0,
        'useExactTimes': globalPrefs.getBool('rc_use_exact_times') ?? false,
        'exactTimes': globalPrefs.getString('rc_exact_times') ?? '',
      });
    }
  }

  final settingsRaw = await JsonFile.read('app_settings');
  // Если файла настроек нет — переносим отдельные boolean prefs в payload
  // под КЛЮЧАМИ, которые читает импорт в settings_screen.dart.
  // Это критично для кругового обмена: иначе пользователь, у которого
  // в билде нет 'app_settings.json', потеряет настройки при экспорте/импорте.
  final settings = <String, dynamic>{};
  // Строковые и булевы настройки читаем РАЗДЕЛЬНЫМИ геттерами:
  // getBool() на строковом значении (например setting_theme='rose')
  // бросает TypeError и роняет экспорт целиком.
  const stringSettingKeys = {
    'setting_theme',
    'setting_locale',
    'setting_font_family',
    'setting_ai_key',
    'setting_agnes_key',
    'setting_zen_key',
    'setting_gemini_key',
    'setting_modal_url',
    'setting_modal_key',
    'developer_prompt',
  };
  const boolSettingKeys = {
    'setting_peach_dark',
    'setting_experimental',
    'setting_auto_save',
    'setting_dev_mode',
    'setting_auto_export',
    'setting_ai_guide',
    'setting_ai_tracking',
    'perfectionism_mode',
    'berserk_mode',
    'task_quick_notes_mode',
    'setting_ada_proactive',
  };
  for (final key in stringSettingKeys) {
    final v = globalPrefs.getString(key);
    if (v != null && v.isNotEmpty && !settings.containsKey(key)) {
      settings[key] = v;
    }
  }
  for (final key in boolSettingKeys) {
    final v = globalPrefs.getBool(key);
    if (v != null && !settings.containsKey(key)) settings[key] = v;
  }

  // Пробрасываем любые поля, которые уже были в файле app_settings.json.
  if (settingsRaw != null) {
    settings.addAll(Map<String, dynamic>.from(jsonDecode(settingsRaw)));
  }
  out['app_settings'] = settings;
  for (final entry in settings.entries) {
    if (entry.value != null) out[entry.key] = entry.value;
  }

  for (final k in [
    'notifications_enabled',
    'notifications_fullscreen',
    'popup_warning_shown',
    'ai_web_search',
    'ai_liked_messages',
    'ai_liked_patterns',
    'ai_rewards_done',
    'ai_tasks_done_total',
    'ada_streak',
    'ada_streak_last',
    'ada_avatar_variant',
    'ada_proactive_day',
    'ada_track_morning',
    'ada_track_evening',
    'ai_floating',
    'ai_bubble_fx',
    'ai_bubble_fy',
    'title_blurred',
    'setting_screen_aware',
    'nutrition_calorie_norm',
    'ny_prize_2027',
  ]) {
    final v = globalPrefs.get(k);
    if (v != null) out[k] = v;
  }
  for (final key in globalPrefs.getKeys()) {
    if (key.startsWith('alarm_pin_') ||
        key.startsWith('berserk_agi_') ||
        const {
          'deleted_alarm_sounds',
          'reality_checks',
          'rc_exact_times',
        }.contains(key)) {
      final value = globalPrefs.get(key);
      if (value != null) out[key] = value;
    }
  }
  final legacyChecksPerDay = globalPrefs.getInt('rc_checks_per_day');
  if (legacyChecksPerDay != null) out['rc_checks_per_day'] = legacyChecksPerDay;
  final legacyExactTimes = globalPrefs.getBool('rc_use_exact_times');
  if (legacyExactTimes != null) out['rc_use_exact_times'] = legacyExactTimes;
  final pinVerifier = await PinService.exportVerifier();
  if (pinVerifier != null) out['app_pin'] = pinVerifier;
  return out;
}

/// Writes [bytes] to a user-visible location.
/// Android → Download/Agysha via MediaStore; desktop → Downloads/Agysha;
/// final fallback → app documents.
Future<String> saveBackupBytes(List<int> bytes, String fileName) async {
  if (kIsWeb) {
    // Web doesn't support file system access the same way
    // This will be handled by the browser's download mechanism
    throw UnsupportedError('File operations not supported on web');
  }
  if (Platform.isAndroid && !kIsWeb) {
    try {
      final path = await _backupChannel
          .invokeMethod<String>('saveToDownloads', {
            'fileName': fileName,
            'bytes': Uint8List.fromList(bytes),
            'subDir': 'Agysha',
          });
      debugPrint('[auto-export] saveToDownloads native -> $path');
      if (path != null && path.isNotEmpty) return path;
    } catch (e) {
      debugPrint('[auto-export] saveToDownloads native FAILED: $e');
    }
  }

  Directory? dir;
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      dir = Directory('${downloads.path}${Platform.pathSeparator}Agysha');
    }
  } catch (_) {}

  if (dir == null && Platform.isAndroid) {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        dir = Directory('${ext.path}${Platform.pathSeparator}backups');
      }
    } catch (_) {}
  }

  dir ??= await getApplicationDocumentsDirectory();
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  // Direct write (overwrite) — rename-over-existing is unreliable on Windows.
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<String> _performAutoExport({bool showSnack = false}) async {
  final out = await buildBackupPayload();
  final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(out));
  // Fixed name so each hourly export overwrites the previous one —
  // easy to find in Download/Agysha/.
  const fileName = 'agysha-auto-backup.json';
  // БЫЛ БАГ: saveBackupBytes возвращает Future, но он не awaited — ошибки
  // записи терялись (не попадали в try/catch), а снекбар показывал
  // строковое представление Future вместо пути. Теперь ждём результат.
  final savedPath = await saveBackupBytes(bytes, fileName);

  if (showSnack) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      final label = Translations.t(
        'autoExportDone',
        ctx,
        'Backup saved to Download/Agysha',
      );
      showBeautifulSnackBar(
        ctx,
        message: '$label\n$savedPath',
        icon: Icons.backup_outlined,
        iconColor: Colors.green,
        duration: const Duration(seconds: 3),
      );
    }
  }
  return savedPath;
}
