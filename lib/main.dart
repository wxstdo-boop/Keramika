import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/splash_screen.dart';
import 'utils/android_settings.dart' show setSecureWindow;
import 'screens/lock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/wake_task_screen.dart';
import 'screens/startup_recovery_screen.dart';
import 'screens/startup_diagnostic_screen.dart';
import 'widgets/mutilated_overlay.dart';
import 'widgets/metel_overlay.dart';
import 'l10n/locale_provider.dart';
import 'l10n/translations.dart';
import 'services/pin_service.dart';
import 'services/settings_service.dart';
import 'services/notification_service.dart';
import 'services/alarm_black_box.dart';
import 'services/alarm_scheduler.dart';
import 'services/haptics.dart';
import 'services/sounds.dart';
import 'theme/app_theme.dart';
import 'utils/motion_prefs.dart';
import 'models/alarm.dart';
import 'services/alarm_service.dart';
import 'services/reality_check_service.dart';
import 'services/habit_service.dart';
import 'services/task_service.dart';
import 'services/timer_service.dart';
import 'services/prefs.dart';
import 'services/ai_guide_service.dart';
import 'services/json_file.dart';
import 'services/migration.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'overlay/ada_overlay.dart'
    show
        initOverlayChannel,
        syncOverlayAvatarFromHost,
        syncOverlayModelFromHost,
        resetOverlayFromHost,
        AdaOverlayApp;
import 'overlay/overlay_bridge.dart';
import 'widgets/ada_avatars.dart';
import 'widgets/ai_guide.dart';
import 'utils/page_transitions.dart';
import 'utils/snackbar.dart';
import 'utils/jank_probe.dart';
import 'services/update_service.dart';
import 'services/installer.dart';
import 'services/app_version.dart';

final NotificationService notificationService = NotificationService();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Наблюдатель для jank-пробы: по нему в логе кадров видно, НА КАКОМ экране
/// снят каждый медленный кадр. Экземпляр — верхнего уровня намеренно:
/// `NavigatorObserver` переживает пересборки `MaterialApp`, а новый объект на
/// каждом build сбрасывал бы стек роутов.
final JankRouteObserver _jankObserver = JankRouteObserver();
Timer? _autoSaveTimer;
bool _autoSaveFailureActive = false;
// Флаг — WakeTaskScreen уже показан, не пушить второй при тапе
// по уведомлению (onNewIntent → onNewAlarmPayload).
bool _wakeScreenShowing = false;

/// Payload будильника, с которым приложение ЗАПУЩЕНО (холодный старт).
///
/// Читается из нативного intent ДО runApp. Это принципиально: раньше экран
/// задачи открывался поверх дерева, которое ещё строилось, — а параллельно
/// доигрывал SplashScreen и в конце вызывал `_goHome()` с
/// `pushAndRemoveUntil((route) => false)`, то есть стирал ВСЕ роуты вместе
/// с только что открытым экраном будильника. Будильник «срабатывал», но
/// человек видел обычный главный экран. Теперь payload известен до первого
/// кадра, и экран задачи становится домашним — сплэш и PIN не запускаются.
String? _alarmBootPayload;

/// Готовность данных к первому Home-кадру: пять сервисов + автосохранение.
///
/// Переход со сплэша ждёт этот Future ([_goHome]), чтобы Home монтировался
/// уже с загруженными списками, а не мигал пустым состоянием.
Future<void>? _dataReady;

/// Читает с диска все пять сервисов и поднимает фоновые задачи старта.
///
/// Вынесено из [_startApp], чтобы переход на Home мог дождаться результата.
Future<void> _loadStartupData() async {
  try {
    // Пять сервисов читают РАЗНЫЕ JsonFile-файлы (у каждого свой per-key lock),
    // поэтому их загрузка безопасна и быстрее когда идёт ПАРАЛЛЕЛЬНО: раньше
    // они шли строго друг за другом, и время = сумма disk-I/O + AES-декода
    // пяти файлов, что на бюджетном железе складывалось в заметную паузу до
    // первого домашнего кадра. Теперь время = только самый долгий из них.
    await Future.wait<void>([
      HabitService().load(),
      TaskService().load(),
      AlarmService().load(),
      RealityCheckService().load(),
      TimerService().load(),
    ]);

    // Дефолтные демо-записи убраны: пользователь добавляет привычки,
    // задачи и будильники сам. Чистим остатки старых демо-данных,
    // которые могли сохраниться на диск из прошлых билдов.
    await _removeLegacyDemoData();
    final autoSaveOn = await SettingsService.loadAutoSave();
    if (autoSaveOn) startAutoSave();
    final autoExportOn = await SettingsService.loadAutoExport();
    if (autoExportOn) {
      // Молча: бэкапим, только если час уже прошёл (приложение было закрыто).
      await maybeCatchUpAutoExport();
    }
  } catch (error, stackTrace) {
    _reportPersistenceFailure(error, stackTrace);
  }
}

/// Читает payload будильника из нативного intent. Возвращает null, если
/// приложение открыто не будильником.
Future<String?> _readAlarmBootPayload() async {
  // Web не поддерживает MethodChannel — сразу возвращаем null
  if (kIsWeb) return null;
  try {
    final p = await const MethodChannel(
      'com.wetidom.keramika/alarm_payload',
    ).invokeMethod<String>('getAlarmPayload');
    if (p != null && p.startsWith('alarm:')) return p;
  } catch (_) {
    // Канал не зарегистрирован (например, другой ABI-движок) — просто
    // идём обычным путём, обработчик после runApp подхватит payload.
  }
  return null;
}

/// Маппинг prefs-ключей на короткие имена, чтобы при экспорте обратно
/// в payload ключи совпадали с именами, которыми пользуется импорт
/// в settings_screen.
void startAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = null;
  _autoSaveTick();
}

Future<void> _autoSaveTick() async {
  try {
    // Параллельно — не блокируем UI последовательной записью 5 файлов
    await Future.wait([
      HabitService().forceSave(),
      TaskService().forceSave(),
      AlarmService().forceSave(),
      RealityCheckService().forceSave(),
      TimerService().forceSave(),
    ]);
    _autoSaveFailureActive = false;
  } catch (error, stackTrace) {
    if (!_autoSaveFailureActive) {
      _autoSaveFailureActive = true;
      _reportPersistenceFailure(error, stackTrace);
    }
  }
  // Увеличиваем интервал с 3 до 10 секунд, чтобы снизить нагрузку на диск.
  _autoSaveTimer = Timer(const Duration(seconds: 10), _autoSaveTick);
}

void _reportPersistenceFailure(Object error, StackTrace stackTrace) {
  debugPrint('Local data operation failed: $error\n$stackTrace');

  void show(BuildContext context) {
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'dataStorageError',
        context,
        'Local data could not be read or saved. Existing files were not changed.',
      ),
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.redAccent,
      duration: const Duration(seconds: 6),
    );
  }

  final context = navigatorKey.currentContext;
  if (context != null && context.mounted) {
    show(context);
  } else {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final retryContext = navigatorKey.currentContext;
      if (retryContext != null && retryContext.mounted) show(retryContext);
    });
  }
}

void stopAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = null;
}

/// Показывает итог самообновления, когда он приходит.
///
/// Слушатель глобальный, а не в таблетке «Обновление»: после УСПЕШНОЙ
/// установки Android подменяет процесс, и виджет, запустивший установку, уже
/// не существует. Итог прилетает либо push-вызовом, либо pull-запросом при
/// следующем запуске (см. Installer.listen) — оба пути приходят сюда.
void _watchInstallOutcome() {
  if (_watchingInstallOutcome) return;
  _watchingInstallOutcome = true;
  Installer.listen();
  Installer.outcomes.listen((outcome) {
    if (!outcome.isFailure && !outcome.isSuccess) return;
    _showInstallOutcome(outcome);
  });
}

bool _watchingInstallOutcome = false;

/// Показывает итог, дожидаясь готовности дерева.
///
/// На старте результат может прийти ДО первого кадра (pull-запрос уходит
/// сразу в listen), когда `navigatorKey.currentContext` ещё null. Поэтому
/// не теряем его, а повторяем попытку в следующих кадрах — пока контекст не
/// появится.
void _showInstallOutcome(InstallOutcome outcome, [int attempt = 0]) {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) {
    if (attempt < 120) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showInstallOutcome(outcome, attempt + 1),
      );
    }
    return;
  }
  if (outcome.isSuccess) {
    // Версия в «О приложении» берётся из манифеста — после обновления
    // подтягиваем её ДО показа, иначе в тексте останется старая.
    unawaited(
      AppVersion.refresh().then((version) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        showBeautifulSnackBar(
          ctx,
          message: Translations.t(
            'updateInstalled',
            ctx,
            'Обновлено до v{v}',
          ).replaceAll('{v}', version),
          icon: Icons.system_update_alt,
        );
      }),
    );
  } else {
    showBeautifulSnackBar(
      context,
      message: Translations.t(
        'updateInstallBlocked',
        context,
        'Система заблокировала обновление. Разрешите установку из этого источника и попробуйте снова.',
      ),
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.redAccent,
      duration: const Duration(seconds: 6),
    );
  }
}

Timer? _autoExportTimer;
bool _isAutoExporting = false;
bool _autoExportEnabled = false;
// Время последнего автоэкспорта — чтобы не «забывать» час, пока приложение
// было закрыто, и не делать лишние бэкапы при каждом запуске.
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
  'com.wetidom.keramika/alarm_payload',
);
// Канал сигналов жизненного цикла Activity → Dart (onNewIntent и т.п.).
final MethodChannel _lifecycleChannel = const MethodChannel(
  'com.wetidom.keramika/lifecycle',
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
    debugPrint('[auto-export] FAILED: $e\n$st');
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
/// Android → Download/Keramika via MediaStore; desktop → Downloads/Keramika;
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
            'subDir': 'Keramika',
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
      dir = Directory('${downloads.path}${Platform.pathSeparator}Keramika');
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
  // easy to find in Download/Keramika/.
  const fileName = 'keramika-auto-backup.json';
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
        'Backup saved to Download/Keramika',
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

String? _pendingAlarmPayload;
// Канал будильника: getAlarmPayload / stopAlarmSound / onNewAlarmPayload.
// Создаётся СРАЗУ (см. комментарий у [_backupChannel]) — иначе первый invoke
// падал с LateInitializationError и обработчик onNewAlarmPayload не вставал.
final MethodChannel _alarmPayloadChannel = const MethodChannel(
  'com.wetidom.keramika/alarm_payload',
);

Future<void> _handleNotificationTap(String? payload) async {
  if (payload == null) return;
  if (payload.startsWith('ada:')) {
    // Уведомление Ада-трекинга (утренний отчёт / вечерний разбор) —
    // открываем мини-чат с Адой, чтобы можно было продолжить диалог.
    for (int i = 0; i < 30; i++) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        showAiGuideChat(context);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return;
  }
  if (payload.startsWith('alarm:')) {
    final id = payload.substring('alarm:'.length);
    final svc = AlarmService();
    await svc.load();
    final alarm = svc.getById(id);
    if (alarm == null) return;
    for (int i = 0; i < 30; i++) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        // Если WakeTaskScreen уже показан — не открываем повторно.
        // Флаг сбрасывается вручную через 500мс после pop,
        // чтобы Android не переотправил intent.
        if (_wakeScreenShowing) return;
        _wakeScreenShowing = true;
        Navigator.of(context, rootNavigator: true)
            .push<void>(
              // Плавный fade+подъём вместо стандартного MaterialPageRoute:
              // срабатывающий будильник появляется мягко, без резкого скачка.
              fadeRoute(
                WakeTaskScreen(
                  taskType: alarm.taskType,
                  isTest: false,
                  soundName: alarm.soundName,
                  customSoundPath: alarm.customSoundPath,
                ),
              ),
            )
            .then((_) {
              Future.delayed(const Duration(milliseconds: 500), () {
                _wakeScreenShowing = false;
              });
            });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }
}

Future<void> _rescheduleRealityChecks() async {
  final rcSvc = RealityCheckService();
  await rcSvc.load();
  if (rcSvc.checks.isEmpty) return;
  if (rcSvc.notificationsDoneForToday) {
    await notificationService.cancelAllRealityChecks();
    return;
  }
  final lang = await SettingsService.loadLanguageCode();
  final title = switch (lang) {
    'ru' => 'Проверка реальности',
    'fr' => 'Test de réalité',
    _ => 'Reality Check',
  };
  try {
    await notificationService.scheduleRealityChecks(
      rcSvc.todaySchedule,
      rcSvc.checks.map((c) => c.question).toList(),
      title: title,
      cancelExisting: true,
    );
  } catch (_) {}
}

/// Перепланировка на старте: будильники/проверки + ежедневные отчёты Ады
/// (утро 08:00, вечер 21:00) со свежим содержанием.
Future<void> _rescheduleAllOnStart() async {
  // После переустановки APK prefs живут (auto-backup), а ОС-разрешение на
  // уведомления — нет: _enabled сбрасывается в false и scheduleAlarm МОЛЧА
  // возвращает false — будильник «не сработал», хотя был сохранён.
  // Восстанавливаем по НАМЕРЕНИЮ пользователя (pref), а не по Ada-трекингу.
  final wantNotifs = globalPrefs.getBool('notifications_enabled') ?? true;
  if (wantNotifs && !notificationService.enabled) {
    try {
      // Восстанавливаем намерение пользователя БЕЗ системного диалога:
      // запрос разрешения уведомлений показывается только по явному
      // действию в настройках (кнопка «Выдать»), а не при каждом запуске.
      await notificationService.setEnabled(true, requestPermission: false);
    } catch (_) {}
  }
  await rescheduleAllNotifications();
  debugPrint(
    '[ada-tracking] wantNotifs=$wantNotifs enabled=${notificationService.enabled}',
  );
  // Ада-трекинг больше НЕ зависит от уведомлений: Ада пишет утренний
  // и вечерний отчёты прямо в ЧАТ. Если время уже наступило (08:00/21:00),
  // догоняем сразу при старте — сообщение появляется в истории чата.
  if (await SettingsService.loadAiTracking()) {
    try {
      final lang = await SettingsService.loadLanguageCode();
      debugPrint('[ada-tracking] chat catch-up lang=$lang');
      await AiGuideService.maybeDeliverAdaReports(lang);
    } catch (e) {
      debugPrint('[ada-tracking] catch-up error: $e');
    }
  }
  // Пуши Ада-трекинга: в 08:00 и 21:00 приходят РЕАЛЬНЫЕ ответы Ады
  // (утренний план и вечерний разбор), сгенерированные при последнем
  // старте/возврате из фона. Не блокирует запуск (фоновый unawaited).
  unawaited(_scheduleAdaTrackingNotifs());
}

/// Планирует утренний (08:00) и вечерний (21:00) пуши Ада-трекинга с
/// живым текстом отчётов. Если трекинг выключен — снимает оба.
Future<void> _scheduleAdaTrackingNotifs() async {
  try {
    final tracking = await SettingsService.loadAiTracking();
    if (!tracking) {
      await notificationService.cancelReminder(90);
      await notificationService.cancelReminder(91);
      return;
    }
    final lang = await SettingsService.loadLanguageCode();
    final morningTitle = switch (lang) {
      'ru' => 'Ада ☀️ Доброе утро!',
      'fr' => 'Ada ☀️ Bonjour !',
      _ => 'Ada ☀️ Good morning!',
    };
    final eveningTitle = switch (lang) {
      'ru' => 'Ада 🌙 Вечерний разбор',
      'fr' => 'Ada 🌙 Bilan du soir',
      _ => 'Ada 🌙 Evening review',
    };
    final morning = await AiGuideService.morningReportText(lang);
    final evening = await AiGuideService.eveningReportText(lang);
    await notificationService.scheduleDailyReminder(
      90,
      8,
      0,
      morningTitle,
      morning,
      payload: 'ada_morning',
    );
    await notificationService.scheduleDailyReminder(
      91,
      21,
      0,
      eveningTitle,
      evening,
      payload: 'ada_evening',
    );
    debugPrint('[ada-tracking] daily pushes scheduled');
  } catch (e) {
    debugPrint('[ada-tracking] push scheduling error: $e');
  }
}

Future<void> rescheduleAllNotifications() async {
  final alarmSvc = AlarmService();
  await alarmSvc.load();
  // СНАЧАЛА гасим одноразовые будильники, которые уже прозвенели: иначе
  // цикл ниже взведёт их заново на ближайшее будущее время, и «один раз»
  // превратится в «звонит каждый день».
  try {
    await alarmSvc.disarmFiredOneShots();
  } catch (_) {}
  var armed = 0;
  var failed = 0;
  for (final a in alarmSvc.alarms) {
    if (a.enabled) {
      try {
        if (await notificationService.scheduleAlarm(a)) {
          armed++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
  }
  // Итоговая проверка: что по мнению САМОЙ системы сейчас взведено. Если
  // строк SCHEDULE/DART ARM в журнале полно, а здесь next=none — будильники
  // стёрла система (агрессивная очистка MIUI/HyperOS), а не приложение.
  try {
    final next = await AlarmScheduler.nextAlarmTime();
    await AlarmBlackBox.log(
      'DART RESUME alarms=${alarmSvc.alarms.length} armed=$armed failed=$failed '
      'next=${next > 0 ? DateTime.fromMillisecondsSinceEpoch(next) : "none"}',
    );
  } catch (_) {}
  // Напоминания привычек «Вспомнить всё» — перепланируем, чтобы система
  // не потеряла их после перезагрузки/нескольких дней в фоне.
  try {
    await HabitService().rescheduleAllReminders();
  } catch (_) {}
  await _rescheduleRealityChecks();
}

/// Одноразовая чистка: удаляет дефолтные «демо»-записи из старых билдов
/// (id фиксированы — пользователь такие через UI создать не может).
Future<void> _removeLegacyDemoData() async {
  const taskIds = {'t1', 't2', 't3', 't4'};
  const alarmIds = {'a1', 'a2', 'a3'};
  const habitIds = {'h1', 'h2', 'h3'};
  try {
    final tasks = TaskService();
    for (final id in taskIds) {
      if (tasks.tasks.any((t) => t.id == id)) await tasks.remove(id);
    }
    final alarms = AlarmService();
    for (final id in alarmIds) {
      if (alarms.alarms.any((a) => a.id == id)) await alarms.remove(id);
    }
    final habits = HabitService();
    for (final id in habitIds) {
      if (habits.habits.any((h) => h.id == id)) await habits.remove(id);
    }
  } catch (_) {}
}

/// Предзагружает логотип в кэш изображений ДО первого кадра,
/// чтобы сплэш-экран показывал картинку сразу, а не после белой паузы.
Future<void> _precacheLogo() async {
  final provider = const AssetImage('assets/keramika.png');
  final completer = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
    onError: (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
  );
  stream.addListener(listener);
  // Страховка: не блокируем запуск дольше 3 секунд.
  await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
}

/// Точка входа системного оверлея Ады — запускается плагином
/// flutter_overlay_window в ОТДЕЛЬНОМ Flutter-движке поверх других
/// приложений. Живёт, пока пользователь не закроет его кнопкой — даже
/// после выхода из основного приложения.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализируем канал (если Android/iOS)
  if (!kIsWeb) initOverlayChannel();
  // Сигнал от главного приложения: «окно пересоздано — сбросься и
  // покажись». Это единственный надёжный канал между движками: lifecycle
  // при повторном открытии может не долететь, и окошко оставалось бы
  // невидимым (анимация появления не стартовала).
  FlutterOverlayWindow.overlayListener.listen((msg) {
    // Команды живой синхронизации из ГЛАВНОГО чата: аватарка и модель
    // сменяются в мини-окошке МГНОВЕННО (без переоткрытия окна).
    if (msg is Map) {
      final cmd = msg['cmd'];
      if (cmd == 'sync_avatar') {
        final v = msg['variant'];
        if (v is int) syncOverlayAvatarFromHost(v);
        return;
      }
      if (cmd == 'sync_model') {
        final l = msg['label'];
        if (l is String) {
          // ГЛАВНЫЙ движок запоминает модель (общий сервис) и уведомляет
          // открытый чат — лейбл «кто ответил» меняется сразу.
          AiGuideService.recordModelUsed(l);
          syncOverlayModelFromHost(l);
        }
        return;
      }
    }
    // Окно пересоздано — сбросься и покажись.
    resetOverlayFromHost();
  });
  runApp(const AdaOverlayApp());
}

/// Заранее декодированный логотип сплэша — первый кадр рисуется с ним
/// МГНОВЕННО, без «мигания» и подгрузки картинки в рантайме.
ui.Image? preDecodedLogo;

/// Всё, что обязано быть прочитано до `runApp`.
class _StartupState {
  const _StartupState({
    required this.hasPin,
    required this.theme,
    required this.lang,
    required this.peachDark,
    required this.fontFamily,
    required this.launchedByNotification,
    required this.notificationPayload,
  });

  final bool hasPin;
  final String theme;
  final String lang;
  final bool peachDark;
  final String fontFamily;

  /// Запуск тапом по уведомлению будильника — сам обработчик навешивается
  /// ПОСЛЕ runApp (там уже есть дерево виджетов), сюда кладём только факт.
  final bool launchedByNotification;
  final String? notificationPayload;
}

/// Декодируем логотип ДО первого кадра: на слабых телефонах Image.asset
/// не успевает прогрузиться к началу сплэша и картинка мигает.
Future<void> _predecodeSplashLogo() async {
  try {
    final data = await rootBundle.load('assets/keramika.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    preDecodedLogo = frame.image;
    codec.dispose();
  } catch (_) {
    // Если декод не удался — сплэш просто покажет Image.asset как раньше.
  }
}

/// Чтение стартового состояния. Независимые шаги запускаются параллельно:
/// раньше они шли строго друг за другом, и время до первого кадра было их
/// суммой (миграция JSON + инициализация плагина уведомлений + пин + шесть
/// настроек), что на слабом железе ощутимо задерживало сплэш.
Future<_StartupState> _loadStartupState() async {
  // Инициализируем SharedPreferences ОДИН раз ДО всего.
  await initPrefs();
  await JsonFile.initialize();
  // Режим плавающего окошка Ады переживает перезапуск приложения.
  // Окошко — внутренний пузырь (одинаково на web и Android): он рисуется
  aiFloating.value = globalPrefs.getBool('ai_floating') ?? false;
  // Если флаг «в окне» остался от прошлой сессии, но системный оверлей
  // уже не живой (пользователь закрыл его или приложение перезапустилось)
  // — сбрасываем, чтобы значок проводника у «+» вернулся.
  // Проверка НЕ блокирует первый кадр: это MethodChannel-запрос к плагину,
  // на слабых телефонах он добавлял задержку перед белым окном.
  if (!kIsWeb && aiFloating.value) {
    unawaited(() async {
      try {
        final active = await isAdaOverlayActive();
        if (!active) {
          aiFloating.value = false;
          await globalPrefs.setBool('ai_floating', false);
        }
      } catch (_) {
        aiFloating.value = false;
      }
    }());
  }

  // Данные старых версий переезжают в JSON-файлы до того, как их начнут
  // читать сервисы (те стартуют после runApp).
  final migration = migrateFromPrefs();
  final notifications = notificationService.init().then((_) {
    notificationService.onNotificationTap = _handleNotificationTap;
    return notificationService.getLaunchDetails();
  });
  final hasPin = PinService.hasPin();
  final theme = SettingsService.loadThemeMode();
  final lang = SettingsService.loadLanguageCode();
  final peachDark = SettingsService.loadPeachDark();
  final fontFamily = SettingsService.loadFontFamily();
  // Прогреваем живые флаги режимов до первого Home-кадра:
  // кнопка BERSERK и карточки не ждут открытия настроек.
  // Вибрация, звуки и «убрать анимации» тоже читаются ДО первого кадра:
  // плеск кнопок не должен успеть дать один лишний отклик, декоративные
  // петли — один лишний виток, а звук — прозвучать до применения настройки.
  final modes = Future.wait<void>([
    SettingsService.loadPerfectionism(),
    SettingsService.loadBerserk(),
    SettingsService.loadHaptics().then((v) => Haptics.enabled = v),
    SettingsService.loadSounds().then((v) => Sounds.enabled = v),
    SettingsService.loadReduceMotion().then((v) => MotionPrefs.enabled.value = v),
  ]);

  await Future.wait<void>([
    migration,
    notifications,
    hasPin,
    theme,
    lang,
    peachDark,
    fontFamily,
    modes,
  ]);
  final details = await notifications;
  return _StartupState(
    hasPin: await hasPin,
    theme: await theme,
    lang: await lang,
    peachDark: await peachDark,
    fontFamily: await fontFamily,
    launchedByNotification: details?.didNotificationLaunchApp == true,
    notificationPayload: details?.notificationResponse?.payload,
  );
}

Future<void> _restoreStartupBackup(Map<String, dynamic> backup) async {
  await JsonFile.beginBackupRecovery();
  // Keep any remaining legacy SharedPreferences data in the fresh encrypted
  // store before applying the selected backup on top of it.
  await migrateFromPrefs();

  const fileKeys = {
    'habits',
    'tasks',
    'task_categories',
    'alarms',
    'app_timers',
    'reality_check_data',
    'nutrition_meals',
    'ai_chat_history',
    'ai_pinned_messages',
    'ada_sync_state',
    'completion_log',
    'ny_event_2027',
  };
  const settingsKeys = {
    'setting_theme',
    'setting_locale',
    'setting_font_family',
    'setting_peach_dark',
    'setting_experimental',
    'setting_auto_save',
    'setting_dev_mode',
    'developer_prompt',
    'setting_auto_export',
    'setting_ai_guide',
    'setting_ai_key',
    'setting_ada_proactive',
    'setting_ai_tracking',
    'setting_agnes_key',
    'setting_zen_key',
    'setting_gemini_key',
    'setting_modal_url',
    'setting_modal_key',
    'perfectionism_mode',
    'berserk_mode',
    'task_quick_notes_mode',
  };
  final settings = backup['app_settings'] is Map
      ? Map<String, dynamic>.from(backup['app_settings'] as Map)
      : <String, dynamic>{};

  for (final entry in backup.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value == null || key == 'app_settings') continue;
    if (fileKeys.contains(key)) {
      if (value is String) await JsonFile.write(key, value);
    } else if (settingsKeys.contains(key)) {
      settings[key] = value;
    } else if (key == 'app_pin' && value is String) {
      await PinService.importBackupValue(value);
    } else if (value is String) {
      await globalPrefs.setString(key, value);
    } else if (value is bool) {
      await globalPrefs.setBool(key, value);
    } else if (value is int) {
      await globalPrefs.setInt(key, value);
    } else if (value is double) {
      await globalPrefs.setDouble(key, value);
    } else if (value is List && value.every((item) => item is String)) {
      await globalPrefs.setStringList(key, value.cast<String>());
    }
  }

  if (settings.isNotEmpty) {
    await JsonFile.write('app_settings', jsonEncode(settings));
  }
  await globalPrefs.setBool('migrated_to_json_file_v1', true);
  await JsonFile.completeBackupRecovery();

  final startup = await _loadStartupState();
  _alarmBootPayload = await _readAlarmBootPayload();
  runApp(
    KeramikaApp(
      initialLocked: startup.hasPin,
      initialTheme: startup.theme,
      initialLanguageCode: startup.lang,
      initialPeachDark: startup.peachDark,
      initialFontFamily: startup.fontFamily,
      alarmBootPayload: _alarmBootPayload,
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _startApp();
}

/// Локаль для экрана диагностики сбоя старта.
///
/// Сбой мог произойти ДО того, как настройки прочитались, поэтому здесь
/// ничего не бросаем: prefs могут быть недоступны, а значение — пустым или
/// мусорным. Нужен просто «разумный» язык для текста ошибки.
Locale _startupDiagnosticLocale() {
  try {
    final code = globalPrefs.getString('setting_locale') ?? '';
    if (code == 'ru' || code == 'fr' || code == 'en') return Locale(code);
  } catch (_) {
    // Настройки недоступны — показываем английский.
  }
  return const Locale('en');
}

/// Запуск приложения. Вынесено из [main], чтобы экран диагностики сбоя
/// старта мог повторить попытку: `onRetry` вызывает эту же функцию, и
/// успешный запуск просто заменяет диагностический корень рабочим.
Future<void> _startApp() async {
  // Edge-to-edge: контент рисуется ПОД системным статус-баром, чтобы
  // глобальное скругление углов (ClipRRect в корне) доходило и до верхних
  // углов экрана. Без этого сверху остаётся чёрная квадратная полоса
  // статус-бара, и при оттягивании крайних разделов (Будильники/РП)
  // верхние края выглядят незакруглёнными.
  // Вызов ДО runApp может быть сброшен первым кадром Flutter, поэтому
  // повторяем его в postFrameCallback сразу после первого кадра.
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // Запуск — два независимых берега вместо одной цепочки.
  //
  // Раньше шаги шли строго последовательно: декод PNG → initPrefs →
  // миграция JSON → инициализация уведомлений → детали тапа → пин →
  // чтения настроек. Время до первого кадра = СУММА всех шагов, а на
  // слабом железе (Redmi с бюджетной flash) каждое обращение к диску и
  // каждый вызов плагина стоит миллисекунды, и они складывались в
  // заметные «чёрные/белые» доли секунды до сплэша.
  //
  // Декод логотипа не зависит ни от чего; prefs → миграция/настройки/
  // уведомления зависят от prefs, и этот порядок сохранён внутри
  // [_loadStartupState].
  late final _StartupState startup;
  try {
    await Future.wait(<Future<void>>[
      _predecodeSplashLogo(),
      _loadStartupState().then((value) => startup = value),
    ]);
  } catch (error, stackTrace) {
    debugPrint('Application startup failed: $error\n$stackTrace');
    if (JsonFile.canRecoverFromBackup(error)) {
      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: StartupRecoveryScreen(onRestore: _restoreStartupBackup),
        ),
      );
      return;
    }
    // Любой другой сбой старта — не «чёрный экран»: показываем экран
    // диагностики с текстом ошибки, стеком и кнопкой «Попробовать снова».
    // Раньше здесь был `rethrow`, и главный изолят умирал молча — пользователь
    // видел только тёмное окно приложения без единого слова.
    runApp(
      StartupDiagnosticApp(
        locale: _startupDiagnosticLocale(),
        error: '$error',
        stack: '$stackTrace',
        onRetry: _startApp,
      ),
    );
    return;
  }
  // Payload будильника читаем до первого кадра: от него зависит, что
  // станет домашним экраном (см. [_AlarmBootHost]).
  _alarmBootPayload = await _readAlarmBootPayload();

  runApp(
    KeramikaApp(
      initialLocked: startup.hasPin,
      initialTheme: startup.theme,
      initialLanguageCode: startup.lang,
      initialPeachDark: startup.peachDark,
      initialFontFamily: startup.fontFamily,
      alarmBootPayload: _alarmBootPayload,
    ),
  );
  // Замер кадров включаем ПОСЛЕ runApp: до первого кадра нет ни одного
  // замера, а `addTimingsCallback` живёт на binding'е. Пишет только кадры
  // дольше бюджета, поэтому в обычной сборке молчит.
  JankProbe.start();
  // Тихая проверка обновлений раз в сутки (БЕЗ диалогов): если на GitHub есть
  // релиз новее, таблетка в Настройках сразу предложит обновиться.
  // В сборке для F-Droid самообновление выключено — проверку не запускаем.
  if (kSelfUpdateEnabled) {
    unawaited(UpdateService.instance.silentDailyCheck());
    // Слушаем итог самообновления: успех показываем «обновлено», а отказ
    // системы (Play Protect и т. п.) — понятной подсказкой. В F-Droid
    // самообновления нет, поэтому и слушатель не нужен.
    _watchInstallOutcome();
  }
  // Повторный edge-to-edge ПОСЛЕ первого кадра — на MIUI/HyperOS вызов  // до runApp не применяется (Flutter сбрасывает системный UI при старте).
  // Без него сверху остаётся чёрная квадратная полоса статус-бара, и
  // верхние углы экрана не закруглены при оттягивании крайних разделов.
  if (!kIsWeb) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );
    });
  }
  // Логотип прогреваем НЕ блокируя старт: сплэш анимируется 1.8с,
  // картинка успеет загрузиться к первому кадру. Так окно Android
  // (теперь фирменного цвета) не висит лишние секунды перед runApp.
  _precacheLogo();

  // Обратная живая синхронизация: мини-окошко (отдельный движок) сообщает
  // о смене аватарки — применяем к общему notifier'у, все аватарки главного
  // чата обновляются мгновенно.
  if (!kIsWeb) {
    FlutterOverlayWindow.overlayListener.listen((msg) {
      if (msg is Map && msg['cmd'] == 'sync_avatar') {
        final v = msg['variant'];
        if (v is int) {
          final clamped = v.clamp(0, adaVariants.length - 1);
          adaAvatarVariant.value = clamped;
          try {
            globalPrefs.setInt('ada_avatar_variant', clamped);
          } catch (_) {}
        }
      }
    });
  }

  // Разрешения на уведомления и будильники пользователь включает сам
  // в настройках приложения (SettingsScreen). Здесь только перепланировка.
  Future.delayed(const Duration(milliseconds: 500), _rescheduleAllOnStart);

  // Автосохранение — загружаем данные ПЕРВЫМ ДЕЛОМ, потом стартуем таймер
  // только если пользователь включал autosave. Future сохраняем: переход на
  // Home ждёт его (см. [_goHome]) — иначе на слабом железе сплэш заканчивался
  // раньше загрузки, Home монтировался с пустыми сервисами и списки «мигали»
  // пустым состоянием, пока данные не доедут.
  _dataReady = _loadStartupData();

  // Флаг — уже обработали запуск от будильника, чтобы не открыть
  // WakeTaskScreen дважды (из getLaunchDetails и getAlarmPayload).
  bool alarmHandled = false;

  if (startup.launchedByNotification) {
    _pendingAlarmPayload = startup.notificationPayload;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(_pendingAlarmPayload);
      _pendingAlarmPayload = null;
      alarmHandled = true;
    });
  }

  // Также проверяем payload из intent (для fullScreenIntent).
  if (!kIsWeb) {
    try {
      final intentPayload = await _alarmPayloadChannel.invokeMethod<String>(
        'getAlarmPayload',
      );
      if (!alarmHandled && intentPayload != null && intentPayload.isNotEmpty) {
        _pendingAlarmPayload = intentPayload;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleNotificationTap(_pendingAlarmPayload);
          _pendingAlarmPayload = null;
        });
      }
    } catch (_) {}
  }
}

/// Слушает сигналы нативной стороны, пока приложение живо: новый payload
/// будильника при `onNewIntent` (тап по уведомлению, когда приложение уже
/// запущено) и `onBootCompleted` (перезагрузка телефона/обновление APK).
///
/// Регистрируется при монтировании [KeramikaAppState] — раньше это стояло в
/// [_startApp] ПОСЛЕ `runApp` и молча не срабатывало: канал был `late final`
/// и первый же `setMethodCallHandler` падал с LateInitializationError, из-за
/// чего тап по уведомлению не открывал экран задачи. Каналы теперь создаются
/// сразу (см. [_alarmPayloadChannel]), а обработчик ставится на монтировании.
void _listenForAlarmPayloads() {
  if (kIsWeb) return;
  _alarmPayloadChannel.setMethodCallHandler((call) async {
    if (call.method == 'onNewAlarmPayload') {
      // Если WakeTaskScreen уже виден — игнорируем повторный payload
      // (пользователь тапнул по уведомлению, пока будильник уже звонит).
      if (_wakeScreenShowing) return;
      final payload = call.arguments as String?;
      if (payload != null && payload.isNotEmpty) {
        await _handleNotificationTap(payload);
      }
    } else if (call.method == 'onBootCompleted') {
      // Телефон перезагрузился (или приложение обновилось) — система
      // стёрла ВСЕ одноразовые setAlarmClock. Перепланируем будильники
      // и проверки реальности, иначе они молча пропадут до ручного
      // открытия приложения.
      await rescheduleAllNotifications();
    }
  });

  // Канал жизненного цикла от нативной стороны. Раньше по нему приходили
  // userLeaveHint/windowFocus для PIN-размытия в «недавных» — размытие
  // удалено, нативные вызовы больше не нужны. Обработчик оставлен, чтобы
  // invoke не падал в MissingPluginException.
  _lifecycleChannel.setMethodCallHandler((call) async {});
}

/// Поведение скролла для всего приложения: iOS-стиль «баунса»/натяжения
/// на краях (как у горизонтального PageView главного экрана) вместо
/// Android-глоу. Работает для всех вертикальных списков.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // ВАЖНО: БЕЗ AlwaysScrollableScrollPhysics. Диалог тайм-пикера обёрнут
    // в SingleChildScrollView, и с AlwaysScrollable он перехватывает
    // вертикальные драги у стрелки часов (зажатие не меняет время).
    // Обычный BouncingScrollPhysics даёт натяжение на краях всем спискам
    // с переполнением, но не крадёт жесты у дочерних pan-виджетов.
    return const BouncingScrollPhysics();
  }
}

class KeramikaApp extends StatefulWidget {
  final bool initialLocked;
  final String initialTheme;
  final String initialLanguageCode;
  final bool initialPeachDark;
  final String initialFontFamily;

  /// Не-null, если приложение открыто срабатыванием будильника (холодный
  /// старт по full-screen intent или по тапу на уведомление).
  final String? alarmBootPayload;

  const KeramikaApp({
    super.key,
    this.initialLocked = false,
    this.initialTheme = 'light',
    this.initialLanguageCode = 'system',
    this.initialPeachDark = false,
    this.initialFontFamily = 'ordinary',
    this.alarmBootPayload,
  });

  @override
  State<KeramikaApp> createState() => KeramikaAppState();

  static KeramikaAppState of(BuildContext context) {
    return context.findAncestorStateOfType<KeramikaAppState>()!;
  }
}

class KeramikaAppState extends State<KeramikaApp>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late String _themeKey;
  late String _languageCode;
  late bool _peachDark;
  late String _fontFamily;
  Key _appKey = UniqueKey();
  bool _locked = false;

  /// Переход на Home уже запланирован (ждём [_dataReady]): не пушим дважды,
  /// если [_goHome] вызван и сплэшем, и решением будильника.
  bool _homeScheduled = false;

  /// Приложение ушло в фон (экран погас / свёрнуто) — при возврате нужно
  /// снова спросить PIN. Не ставим, если уходили в системный диалог/настройки
  /// ([systemUiActive]) или на экране будильника ([_wakeScreenShowing]):
  /// будильник специально обходит блокировку, а возврат из настроек не должен
  /// запирать приложение.
  bool _relockPending = false;

  /// Момент ухода в фон. Пока с него прошло меньше [kRelockGrace], возврат
  /// в приложение НЕ требует PIN: короткий взгляд в уведомления/на часы не
  /// должен выкидывать на замок. Раньше запирало мгновенно на любом уходе.
  DateTime? _backgroundedAt;

  /// Когда последний раз перепланировали уведомления на возврате из фона.
  /// Полный обход будильников/напоминаний/проверок — это десятки platform-
  /// каналов на каждый канал, и на слабом телефоне он приходился ровно на
  /// первый видимый кадр после возврата: экран «мигал» и дёргался. Частые
  /// возвраты (свернул/развернул, посмотрел уведомление) в пределах
  /// [kResumeRescheduleGrace] больше не перепланируют — порядок взведённых
  /// будильников за пару минут не меняется.
  DateTime? _lastResumeReschedule;

  static const Duration kResumeRescheduleGrace = Duration(seconds: 45);

  /// Сколько можно не вводить PIN после ухода в фон. Три минуты — компромисс:
  /// быстрый возврат не раздражает, а забытый на столе телефон сам запирается.
  static const Duration kRelockGrace = Duration(minutes: 3);

  /// Подпись последнего применённого системного UI-стиля (яркость +
  /// цвет статуса-бара). Платформ-вызов `setSystemUIOverlayStyle` дёшев,
  /// но в первые кадры после сплэша лишних platform-каналов — как раз
  /// те «подтормозы», которые видит пользователь. Шлём только когда
  /// параметры реально изменились (смена темы/языка), а не на каждый
  /// ребилд дерева.
  String? _lastSysUiSig;
  ColorScheme? _lightDynamic;
  ColorScheme? _darkDynamic;
  Timer? _overlayCheckTimer;

  Timer? _adaTrackTimer;
  ThemeData? _lightThemeCache;
  ThemeData? _darkThemeCache;
  String? _lightThemeCacheKey;
  String? _darkThemeCacheKey;

  static const List<String> _supported = ['en', 'ru', 'fr'];

  ThemeMode get themeMode {
    switch (_themeKey) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'grok':
        return ThemeMode.light;
      case 'darkGrok':
        return ThemeMode.dark;
      case 'systemLight':
        return ThemeMode.light;
      case 'peach':
        return _peachDark ? ThemeMode.dark : ThemeMode.light;
      case 'rose':
        return ThemeMode.light; // Rose — всегда светлая, воздушная тема
      case 'mutilated':
        // MUTILATED — всегда светлая, кроваво-красная, еле заметные пятна.
        return ThemeMode.light;
      case 'metel':
        // «Метель» — подарок 12-го дня: холодный белый снег, поэтому только
        // светлая.
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  String get themeKey => _themeKey;

  String get fontFamily => _fontFamily;

  void setFontFamily(String family) {
    final next = family == 'caveat' ? 'caveat' : 'ordinary';
    if (next == _fontFamily) return;
    setState(() => _fontFamily = next);
    SettingsService.saveFontFamily(next);
  }

  /// Current language code.
  /// If 'system', the app will pick the preferred locale from the device
  /// (e.g. Russian if the phone is set to Russian).
  /// It is saved via SettingsService.saveLanguageCode().
  String get languageCode => _languageCode;

  Locale _resolveLocale() {
    if (_languageCode != 'system') return Locale(_languageCode);
    // Use PlatformDispatcher for web compatibility (Platform.localeName crashes on web)
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final candidates = [dispatcher.locale, ...dispatcher.locales];
    for (final l in candidates) {
      final langCode = l.languageCode;
      if (langCode.startsWith('ru')) return const Locale('ru');
      if (langCode.startsWith('fr')) return const Locale('fr');
      if (_supported.contains(langCode)) return Locale(langCode);
    }
    // Если ничего не подошло — дефолт русский
    return const Locale('ru');
  }

  Locale get locale => _resolveLocale();

  bool get locked => _locked;

  void setThemeMode(String key) {
    setState(() => _themeKey = key);
    SettingsService.saveThemeMode(key);
    // Тема перетекает сама — MaterialApp анимирует ThemeData (AnimatedTheme),
    // без своих затемнений и вспышек.
  }

  void togglePeachDark() {
    setState(() => _peachDark = !_peachDark);
    SettingsService.savePeachDark(_peachDark);
  }

  void setLanguageCode(String code) {
    if (code == _languageCode) return;
    // Язык просто плавно меняется: все тексты обновляются на месте,
    // без переходов, размытий и вспышек.
    setState(() => _languageCode = code);
    SettingsService.saveLanguageCode(code);
  }

  /// Будильник отзвонил и задача решена — уводим на обычный старт.
  ///
  /// PIN показываем принудительно: запуск по будильнику обходит экран
  /// блокировки приложения (иначе звонящий будильник оказался бы заперт),
  /// поэтому после решения задачи возвращаем привычную защиту.
  void _afterAlarmSolved() {
    _wakeScreenShowing = false;
    _alarmBootPayload = null;
    if (PinService.hasPinSync()) {
      _goLock();
    } else {
      _goHome();
    }
  }

  void _goHome() {
    // Экран будильника живёт поверх — перестраивать навигацию под ним
    // нельзя: pushAndRemoveUntil стёр бы его вместе со всем стеком.
    if (_wakeScreenShowing) return;
    aiLockScreenVisible.value = false;
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    // Ждём готовности данных, чтобы Home смонтировался сразу со списками:
    // на слабом железе сплэш заканчивался раньше загрузки, и разделы
    // мелькали пустым состоянием до прихода данных (те самые «флики»).
    // Сплэш уже погасил тяжёлую левитацию, так что ожидание почти незаметно.
    final ready = _dataReady;
    if (ready == null) {
      _pushHome(nav);
      return;
    }
    // Ожидание асинхронное: повторный вызов (сплэш + решение будильника)
    // не должен запушить Home дважды.
    if (_homeScheduled) return;
    _homeScheduled = true;
    unawaited(
      ready.whenComplete(() {
        _homeScheduled = false;
        if (!mounted) return;
        _pushHome(nav);
      }),
    );
  }

  void _pushHome(NavigatorState nav) {
    // Лёгкий кросс-фейд (без slide+scale на весь 4-экранный дом):
    // тяжёлый [slideUpRoute] на большом PageView давал «подтормоз» на
    // первом кадре после сплэша.
    nav.pushAndRemoveUntil(
      homeEntryRoute(const HomeScreen()),
      (route) => false,
    );
  }

  void _goSplash() {
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // Тот же [lockRoute], что и у ПИН-экрана: блокировка и разблокировка —
      // одна и та же мягкая проявка в обе стороны. Раньше сюда шёл fadeRoute
      // с другой длительностью, и «обратно» выглядело иначе, чем «в блок» —
      // переход читался как два разных жеста.
      nav.pushAndRemoveUntil(
        lockRoute(SplashScreen(onDone: _goHome)),
        (route) => false,
      );
    }
  }

  void _goLock() {
    // PIN-локскрин: плавающее окошко Ады скрываем (нельзя открыть чат
    // в обход блокировки), а в «недавних» Android покажет красиво размытый
    // снимок приложения вместо приватных данных.
    aiLockScreenVisible.value = true;
    setSecureWindow(true);
    // Держим флаг в актуальном состоянии: по нему решается, нужен ли
    // повторный запрос PIN при следующем возврате из фона.
    if (!_locked) setState(() => _locked = true);
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // Плавная симметричная проявка (см. [lockRoute]) вместо выезда снизу:
      // «в блок» и «из блока» — одно движение, без рывка на разблокировке.
      nav.pushAndRemoveUntil(
        lockRoute(LockScreen(onUnlock: () => unlock())),
        (route) => false,
      );
    }
  }

  Future<void> refreshApp() async {
    setState(() {
      _appKey = UniqueKey();
    });
    rescheduleAllNotifications();
    final hasPin = await PinService.hasPin();
    if (hasPin) {
      _goLock();
    } else {
      _goSplash();
    }
  }

  void lock() {
    _goLock();
  }

  void unlock() {
    aiLockScreenVisible.value = false;
    setState(() {
      _locked = false;
    });
    _goSplash();
  }

  @override
  void initState() {
    super.initState();
    _themeKey = widget.initialTheme;
    _languageCode = widget.initialLanguageCode;
    _peachDark = widget.initialPeachDark;
    _fontFamily = widget.initialFontFamily == 'caveat' ? 'caveat' : 'ordinary';
    _locked = widget.initialLocked;
    aiLockScreenVisible.value = _locked;
    WidgetsBinding.instance.addObserver(this);
    // Слушаем payload'и будильника, пока приложение живо (тап по уведомлению
    // при работающем приложении → onNewIntent → onNewAlarmPayload).
    _listenForAlarmPayloads();
    // Polling: проверяем каждые 2 сек, жив ли оверлей Ады.
    // Lifecycle resumed НЕ fire при закрытии системного оверлея
    // (main app уже в resumed), поэтому нужен polling.
    aiFloating.addListener(_onAiFloatingChanged);
    if (aiFloating.value) _startOverlayCheck();
    // platformDispatcher.locale may not be populated on the very first
    // build frame. Re-resolve once the first frame is drawn so the
    // "Phone language" (system) option picks up the real device locale
    // (e.g. Russian) even if it was unavailable at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _languageCode == 'system') setState(() {});
    });
    _armAdaTrackingTimer();
  }

  /// Ставит таймер до следующего отчёта Ады (ближайшие 08:00 или 21:00).
  void _armAdaTrackingTimer() {
    _adaTrackTimer?.cancel();
    final now = DateTime.now();
    final candidates = <DateTime>[];
    for (final h in [8, 21]) {
      var t = DateTime(now.year, now.month, now.day, h, 0);
      if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
      candidates.add(t);
    }
    candidates.sort();
    _adaTrackTimer = Timer(candidates.first.difference(now), _adaTrackTick);
  }

  /// Сработал таймер: доставляем положенные отчёты в чат и ставим следующий.
  Future<void> _adaTrackTick() async {
    try {
      final lang = await SettingsService.loadLanguageCode();
      await AiGuideService.maybeDeliverAdaReports(lang);
      await AiGuideService.maybeDeliverAdaNudge(lang);
    } catch (_) {}
    _armAdaTrackingTimer();
  }

  void _onAiFloatingChanged() {
    if (aiFloating.value) {
      _startOverlayCheck();
    } else {
      _stopOverlayCheck();
    }
  }

  void _startOverlayCheck() {
    _stopOverlayCheck();
    _overlayCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!aiFloating.value) {
        _stopOverlayCheck();
        return;
      }
      isAdaOverlayActive().then((active) {
        if (!active && aiFloating.value) {
          aiFloating.value = false;
          globalPrefs.setBool('ai_floating', false);
          _stopOverlayCheck();
        }
      });
    });
  }

  void _stopOverlayCheck() {
    _overlayCheckTimer?.cancel();
    _overlayCheckTimer = null;
  }

  @override
  void dispose() {
    _stopOverlayCheck();
    _adaTrackTimer?.cancel();
    aiFloating.removeListener(_onAiFloatingChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_languageCode == 'system') setState(() {});
    super.didChangeLocales(locales);
  }

  /// При возврате из фона перепланируем все будильники и проверки реальности:
  /// система могла удалить/пропустить их, если приложение лежало в фоне несколько дней.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Уход в фон (погас экран / приложение свёрнуто): запоминаем, что при
    // возврате нужен PIN. Это закрывает обход блокировки «включил телефон —
    // приложение уже открыто без PIN». Исключения: системный диалог/настройки
    // (возврат из них не должен запирать) и экран будильника (он специально
    // открывается без PIN). Если PIN-экран уже на экране — не дублируем.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!systemUiActive &&
          !_wakeScreenShowing &&
          !_locked &&
          PinService.hasPinSync()) {
        _relockPending = true;
        _backgroundedAt = DateTime.now();
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      // Приложение снова на переднем плане.
      // Системный UI (файл-пикер и т.п.) закрылся — флаг сбрасываем.
      systemUiActive = false;
      // Возврат из фона с включённым PIN: показываем блокировку ДО того,
      // как человек увидит содержимое. Будильник сюда не попадает
      // (_wakeScreenShowing), системные экраны — тоже (флаг выше).
      if (_relockPending) {
        _relockPending = false;
        // Грейс-период: если вернулись раньше [kRelockGrace], PIN не
        // спрашиваем — просто продолжаем с того же места. Флаг всё равно
        // снимаем, иначе следующий уход посчитает время от старой метки.
        final away = _backgroundedAt;
        _backgroundedAt = null;
        final awayMs = away == null
            ? kRelockGrace.inMilliseconds
            : DateTime.now().difference(away).inMilliseconds;
        if (awayMs >= kRelockGrace.inMilliseconds) _goLock();
      }
      HabitService().normalizeIfDayChanged();
      // Тяжёлая перепланировка — НЕ на первый видимый кадр: сначала даём
      // кадру отрисоваться (addPostFrameCallback), и только если с прошлого
      // раза прошло больше [kResumeRescheduleGrace]. Иначе десятки
      // platform-вызовов приходились ровно на кадр возврата и экран мигал.
      final now = DateTime.now();
      final last = _lastResumeReschedule;
      if (last == null ||
          now.difference(last) >= kResumeRescheduleGrace) {
        _lastResumeReschedule = now;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(rescheduleAllNotifications());
        });
      }
      // Ада-трекинг: догоняем пропущенный отчёт (приложение лежало в фоне)
      // и перезаводим таймер на ближайшие 08:00/21:00.
      unawaited(_adaTrackTick());
      unawaited(_scheduleAdaTrackingNotifs());
      // Автоэкспорт «догоняет» пропущенный час, пока приложение было
      // закрыто или в фоне — Dart-таймер там не срабатывает.
      maybeCatchUpAutoExport();
      // Если системный оверлей Ады закрыли — возвращаем значок ИИ
      // плавно через AnimatedSwitcher.
      if (!kIsWeb && aiFloating.value) {
        isAdaOverlayActive().then((active) {
          if (!active && aiFloating.value) {
            aiFloating.value = false;
            globalPrefs.setBool('ai_floating', false);
          }
        });
      }
    }
  }

  ThemeData _buildCachedTheme(
    ColorScheme scheme, {
    required bool isDark,
    required bool isGrokStyle,
  }) {
    // Шрифт задаётся ПРЯМО в текстовых стилях темы (copyWith ниже):
    // AnimatedTheme не умеет интерполировать fontFamily (строка), поэтому
    // смена шрифта происходит мгновенно, а палитра тем перетекает плавно.
    // cacheKey включает _fontFamily, чтобы при переключении шрифта тема
    // пересобиралась с новым шрифтом (иначе остаётся закэшированная тема
    // со старым шрифтом — Caveat не переключался).
    final cacheKey = '${scheme.hashCode}|$isGrokStyle|$_fontFamily';
    final cached = isDark ? _darkThemeCache : _lightThemeCache;
    final cachedKey = isDark ? _darkThemeCacheKey : _lightThemeCacheKey;
    if (cached != null && cachedKey == cacheKey) return cached;

    final built = buildKeramikaTheme(
      scheme,
      isDark: isDark,
      isGrokStyle: isGrokStyle,
      fontFamily: _fontFamily,
    );
    if (isDark) {
      _darkThemeCache = built;
      _darkThemeCacheKey = cacheKey;
    } else {
      _lightThemeCache = built;
      _lightThemeCacheKey = cacheKey;
    }
    return built;
  }

  @override
  Widget build(BuildContext context) {
    // Корень — само приложение. Раньше здесь был Stack с репозиторием
    // снимка и размытым оверлеем для «недавных» (PIN) — размытие удалено,
    // остался прямой вызов _buildApp.
    return _buildApp(context);
  }

  Widget _buildApp(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        _lightDynamic = lightDynamic;
        _darkDynamic = darkDynamic;
        final useDynamic = _themeKey == 'system' || _themeKey == 'systemLight';
        final isPeach = _themeKey == 'peach';
        final isGrok = _themeKey == 'grok';
        final isDarkGrok = _themeKey == 'darkGrok';
        // Grok-стиль (светлый или тёмный): острые 12px-углы вместо скруглённых 24px.
        final isGrokStyle = isGrok || isDarkGrok;
        final resolved = _resolveLocale();

        final lightScheme = (useDynamic && _lightDynamic != null)
            ? _lightDynamic!
            : (() {
                if (isPeach) {
                  return ColorScheme.fromSeed(
                    seedColor: const Color(0xFFFFAB91),
                    brightness: Brightness.light,
                  );
                }
                if (isGrok) {
                  // Grok (xAI) — светлая тема: почти белый фон, тёмный текст,
                  // фирменный синий акцент #78B4FF. Все иконки контрастные.
                  return ColorScheme.light(
                    primary: const Color(
                      0xFF0F1419,
                    ), // почти чёрный — кнопки/акценты
                    onPrimary: const Color(0xFFFFFFFF),
                    primaryContainer: const Color(0xFFE1E8F0),
                    onPrimaryContainer: const Color(0xFF0F1419),
                    secondary: const Color(
                      0xFF3A7CA5,
                    ), // приглушённый Grok-синий
                    onSecondary: const Color(0xFFFFFFFF),
                    secondaryContainer: const Color(0xFFD6E8F5),
                    onSecondaryContainer: const Color(0xFF0B1F30),
                    surface: const Color(0xFFF7F8FA),
                    onSurface: const Color(
                      0xFF11151A,
                    ), // основной текст — тёмный
                    onSurfaceVariant: const Color(
                      0xFF4A5560,
                    ), // иконки — тёмные, видно
                    outline: const Color(0xFFB8C0C9),
                    outlineVariant: const Color(0xFFDDE3E9),
                    surfaceContainerHighest: const Color(0xFFEAEEF2),
                  );
                }
                if (_themeKey == 'rose') {
                  // Rose — светлая, воздушная и контрастная: глубокий розовый
                  // для акцентов, почти белый фон, тёмно-розовый текст.
                  return ColorScheme.light(
                    primary: const Color(
                      0xFFC2185B,
                    ), // глубокий розовый — видно иконки
                    onPrimary: const Color(0xFFFFFFFF),
                    primaryContainer: const Color(0xFFFFD9E6),
                    onPrimaryContainer: const Color(0xFF3E0A1E),
                    secondary: const Color(0xFFE91E63),
                    onSecondary: const Color(0xFFFFFFFF),
                    secondaryContainer: const Color(0xFFFFE3EC),
                    onSecondaryContainer: const Color(0xFF3E0A1E),
                    surface: const Color(
                      0xFFFFF8FB,
                    ), // почти белый с розовым отливом
                    onSurface: const Color(
                      0xFF3E0D20,
                    ), // тёмно-бордовый текст — чёткий
                    onSurfaceVariant: const Color(
                      0xFF7D2A45,
                    ), // иконки/вторичный текст — контрастные
                    outline: const Color(0xFFE8A7BE),
                    outlineVariant: const Color(0xFFF6D9E3),
                    surfaceContainerHighest: const Color(0xFFFBE7EE),
                  );
                }
                if (_themeKey == 'mutilated') {
                  // MUTILATED — светлая, кроваво-красная, на грани.
                  // Глубокий вишнёвый акцент, очень светлый фон с тёплым
                  // розовым оттенком. Сами «кровавые пятна» рендерим
                  // отдельным слоем поверх scaffold (см. _MutilatedSplatter).
                  return ColorScheme.light(
                    primary: const Color(0xFFB8122C),
                    onPrimary: const Color(0xFFFFFFFF),
                    primaryContainer: const Color(0xFFFFD6DC),
                    onPrimaryContainer: const Color(0xFF4A0A18),
                    secondary: const Color(0xFF7E0E22),
                    onSecondary: const Color(0xFFFFFFFF),
                    secondaryContainer: const Color(0xFFFFB6BF),
                    onSecondaryContainer: const Color(0xFF3A0A14),
                    surface: const Color(0xFFFFF1F2),
                    onSurface: const Color(0xFF2A0610),
                    onSurfaceVariant: const Color(0xFF6E142D),
                    outline: const Color(0xFFE09098),
                    outlineVariant: const Color(0xFFF1C3C9),
                    surfaceContainerHighest: const Color(0xFFFFE4E7),
                  );
                }
                // «Метель» — подарок 12-го дня ивента. Северное сияние по
                // белому снегу: холодный почти белый фон (ни желтинки, ни
                // розового отлива), акценты — мята/лазурь/фиолет из той же
                // палитры, что и скин скважины на ПИН-экране, чтобы подарок
                // выглядел ОДНИМ набором. `tertiary` и всю лесенку
                // `surfaceContainer*` задаём явно: ColorScheme.light()
                // додумывает их как `secondary` и `surface`, и карточки
                // получились бы одного цвета с фоном.
                if (_themeKey == 'metel') {
                  return const ColorScheme.light(
                    primary: Color(0xFF0E7C6B),
                    onPrimary: Color(0xFFFFFFFF),
                    primaryContainer: Color(0xFFC9EFE6),
                    onPrimaryContainer: Color(0xFF00201A),
                    secondary: Color(0xFF3A6FA8),
                    onSecondary: Color(0xFFFFFFFF),
                    secondaryContainer: Color(0xFFD6E9FA),
                    onSecondaryContainer: Color(0xFF001E33),
                    tertiary: Color(0xFF6B5BC4),
                    onTertiary: Color(0xFFFFFFFF),
                    tertiaryContainer: Color(0xFFE6E0FB),
                    onTertiaryContainer: Color(0xFF150D47),
                    surface: Color(0xFFFAFDFE),
                    onSurface: Color(0xFF122029),
                    onSurfaceVariant: Color(0xFF42565F),
                    outline: Color(0xFF8FA8B2),
                    outlineVariant: Color(0xFFD5E5EA),
                    surfaceContainerLowest: Color(0xFFFFFFFF),
                    surfaceContainerLow: Color(0xFFF3F9FB),
                    surfaceContainer: Color(0xFFEDF5F7),
                    surfaceContainerHigh: Color(0xFFE6F0F3),
                    surfaceContainerHighest: Color(0xFFDFEBEF),
                  );
                }
                // Обычная СВЕТЛАЯ — светло-сиреневая: фиолетовый акцент и
                // лавандовый фон. Собрана явными ролями, а не fromSeed, по
                // той же причине, что и остальные темы: от стального seedа
                // Material выдавал серо-голубую палитру, и «починить» её
                // можно было только заданными цветами.
                return const ColorScheme.light(
                  primary: Color(0xFF6750A4),
                  onPrimary: Color(0xFFFFFFFF),
                  primaryContainer: Color(0xFFEADDFF),
                  onPrimaryContainer: Color(0xFF21005D),
                  secondary: Color(0xFF625B71),
                  onSecondary: Color(0xFFFFFFFF),
                  secondaryContainer: Color(0xFFE8DEF8),
                  onSecondaryContainer: Color(0xFF1D192B),
                  surface: Color(0xFFFEF7FF),
                  onSurface: Color(0xFF1D1B20),
                  onSurfaceVariant: Color(
                    0xFF49454F,
                  ), // вторичный текст/иконки — контрастные
                  outline: Color(0xFF79747E),
                  outlineVariant: Color(0xFFCAC4D0),
                  surfaceContainerHighest: Color(0xFFE7E0EC),
                );
              })();

        final darkScheme = (useDynamic && _darkDynamic != null)
            ? _darkDynamic!
            : (() {
                if (isDarkGrok) {
                  // Grok Dark (xAI) — настоящие цвета grok.com: плоский
                  // нейтральный тёмный #17181C, карточки чуть светлее,
                  // НИКАКОЙ синевы. Акценты — белый/почти белый (кнопки,
                  // ссылки) и приглушённый серо-голубой для второстепенного.
                  return ColorScheme.dark(
                    primary: const Color(
                      0xFFEDEDF0,
                    ), // почти белый — кнопки/акценты как в Grok
                    onPrimary: const Color(0xFF101013),
                    primaryContainer: const Color(0xFF26272C),
                    onPrimaryContainer: const Color(0xFFF0F1F3),
                    secondary: const Color(
                      0xFF8B93A1,
                    ), // приглушённый нейтральный серый
                    onSecondary: const Color(0xFF121316),
                    secondaryContainer: const Color(0xFF2B2D33),
                    onSecondaryContainer: const Color(0xFFD9DCE1),
                    surface: const Color(0xFF17181C), // фирменный фон Grok
                    surfaceContainerLowest: const Color(0xFF121316),
                    surfaceContainerLow: const Color(0xFF1D1E22), // карточки
                    surfaceContainer: const Color(0xFF212227),
                    surfaceContainerHigh: const Color(0xFF26272C),
                    surfaceContainerHighest: const Color(0xFF2B2C31),
                    onSurface: const Color(
                      0xFFEFEFF1,
                    ), // основной текст — почти белый
                    onSurfaceVariant: const Color(
                      0xFFA3A7AE,
                    ), // иконки/вторичный текст — читаемые
                    outline: const Color(0xFF33353B),
                    outlineVariant: const Color(0xFF26282D),
                  );
                }
                if (isPeach) {
                  return ColorScheme.fromSeed(
                    seedColor: const Color(0xFFFFAB91),
                    brightness: Brightness.dark,
                  );
                }
                if (_themeKey == 'rose') {
                  return ColorScheme.dark(
                    primary: const Color(0xFFFF80AB),
                    onPrimary: const Color(0xFF3A0A1E),
                    primaryContainer: const Color(0xFF5C1F38),
                    onPrimaryContainer: const Color(0xFFFFD9E6),
                    secondary: const Color(0xFFFF9EBB),
                    onSecondary: const Color(0xFF3A0A1E),
                    secondaryContainer: const Color(0xFF59223A),
                    onSecondaryContainer: const Color(0xFFFFD9E6),
                    surface: const Color(0xFF26121C),
                    onSurface: const Color(0xFFFBE4EC),
                    onSurfaceVariant: const Color(0xFFF3C1D3),
                    outline: const Color(0xFF8A5A6E),
                    outlineVariant: const Color(0xFF5C2C3E),
                    surfaceContainerHighest: const Color(0xFF3A1C28),
                  );
                }
                if (isGrok) {
                  // Тёмная версия Grok-темы (используется для grok-пары при system).
                  return ColorScheme.dark(
                    primary: const Color(0xFF78B4FF),
                    onPrimary: const Color(0xFF0B1B2E),
                    primaryContainer: const Color(0xFF23466B),
                    onPrimaryContainer: const Color(0xFFD6E9FF),
                    secondary: const Color(0xFF9FB6CC),
                    onSecondary: const Color(0xFF0B1B2E),
                    secondaryContainer: const Color(0xFF2A3B4E),
                    onSecondaryContainer: const Color(0xFFDCEAF8),
                    surface: const Color(0xFF17181C),
                    onSurface: const Color(0xFFF2F4F7),
                    onSurfaceVariant: const Color(0xFFB4BEC9),
                    outline: const Color(0xFF3E454E),
                    outlineVariant: const Color(0xFF2C3138),
                    surfaceContainerHighest: const Color(0xFF23252B),
                  );
                }
                return ColorScheme.fromSeed(
                  seedColor: const Color(
                    0xFF6750A4,
                  ), // фирменный фиолетовый: даже без dynamic color
                  // тёмная «системная» не выглядит чёрной/стальной —
                  // поверхности и primary имеют цветовой подмес.
                  brightness: Brightness.dark,
                );
              })();

        return MaterialApp(
          key: _appKey,
          title: 'Keramika',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          navigatorObservers: [_jankObserver],
          // Такой же эффект «натяжения» при перетягивании краёв, как у
          // горизонтального PageView на главном экране, но для вертикальных
          // списков во всех разделах (Android-глоу заменяется на баунс).
          scrollBehavior: const _AppScrollBehavior(),
          locale: resolved,
          supportedLocales: const [Locale('en'), Locale('ru'), Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _buildCachedTheme(
            lightScheme,
            isDark: false,
            isGrokStyle: isGrokStyle,
          ),
          darkTheme: _buildCachedTheme(
            darkScheme,
            isDark: true,
            isGrokStyle: isGrokStyle,
          ),
          themeMode: themeMode,
          // Цвета тем переходят плавно. Шрифт не входит в ThemeData и не
          // участвует в этом переходе — он меняется сразу, как язык.
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeInOutCubic,
          // Холодный старт по будильнику: домашним становится ЭКРАН ЗАДАЧИ,
          // а не сплэш и не PIN. Иначе сплэш доигрывал свою анимацию и
          // `_goHome()` стирал все роуты вместе с экраном будильника —
          // звонок шёл, а человек видел обычный главный экран.
          home: widget.alarmBootPayload != null
              ? _AlarmBootHost(
                  payload: widget.alarmBootPayload!,
                  onFinished: _afterAlarmSolved,
                )
              : _locked
              ? LockScreen(onUnlock: () => unlock())
              : SplashScreen(onDone: _goHome),
          builder: (context, child) {
            // Глобальный множитель шрифта убран: TextScaler.linear(1.35)
            // НЕ применялся к виджетам, оборачивающим текст в собственный
            // MediaQuery (поэтому в привычках/задачах шрифт «не менялся»).
            // Базовые размеры теперь подняты в самой теме (_buildThemeData)
            // и точечно в проблемных местах — работает везде одинаково.
            // Системную навигационную панель красим в цвет фона приложения:
            // иначе внизу (под контентом) видна белая полоса, за которую
            // «залезает» экран при pull-to-refresh. Платформ-вызов
            // [SystemChrome.setSystemUIOverlayStyle] шлём ТОЛЬКО когда
            // параметры реально изменились (смена темы/языка): до этого
            // он улетал на каждый ребилд дерева (каждый кадр скролла), и
            // в первые кадры после сплэша эти лишние platform-каналы
            // читались как «подтормозы». Гвард по подписи [sig] — яркость
            // + цвет статус-бара.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
              final sig =
                  '${isDark ? 'd' : 'l'}|${theme.scaffoldBackgroundColor.toARGB32()}';
              if (sig == _lastSysUiSig) return; // ничего не изменилось
              _lastSysUiSig = sig;
              // Навбар делаем ПРОЗРАЧНЫМ (не просто в цвет фона): на светлых
              // темах полоса навбара всё равно выглядела белой, и при скролле
              // контент статистики «залезал» за неё. Прозрачный навбар
              // показывает тот же фон приложения — никакой отдельной полосы
              // нет. Экран статистики дополнительно защищён SafeArea снизу.
              SystemChrome.setSystemUIOverlayStyle(
                SystemUiOverlayStyle(
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarDividerColor: Colors.transparent,
                  systemNavigationBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  // Android 15+ (targetSdk 35+) накладывает СВОЮ контрастную
                  // белую подложку на навбар поверх нашего цвета — отключаем,
                  // иначе внизу всё равно видна белая полоса.
                  systemNavigationBarContrastEnforced: false,
                  // Статус-бар красим в цвет фона приложения (не transparent):
                  // MIUI/HyperOS игнорирует прозрачный статус-бар и рисует
                  // чёрную квадратную полосу, из-за которой верхние углы
                  // экрана не выглядят закруглёнными при оттягивании
                  // крайних разделов. С фоном приложения полоса сливается.
                  statusBarColor: theme.scaffoldBackgroundColor,
                  statusBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                ),
              );
            });
            // Системный textScaler оставляем как есть — пользователь мог
            // включить крупный шрифт в системе; дополнительно не трогаем.
            // Шрифт живёт в DefaultTextStyle — НЕ в ThemeData. AnimatedTheme
            // тогда не интерполирует fontFamily, и шрифт меняется мгновенно
            // (как язык), а палитра тем перетекает плавно.
            final appFontFamily = _fontFamily == 'caveat' ? 'Caveat' : null;
            return DefaultTextStyle.merge(
              style: TextStyle(fontFamily: appFontFamily),
              child: LocaleProvider(
                locale: resolved,
                // БЕЗ меняющегося key: при смене темы/языка не пересоздаём
                // Navigator и плавающее окошко (иначе открытый чат закрывался,
                // а пузырь терял состояние).
                // Тема перетекает штатной анимацией MaterialApp (AnimatedTheme),
                // язык — просто мгновенной плавной сменой текста. Никаких
                // своих затемнений, размытий и вспышек.
                child: KeyedSubtree(
                  key: const ValueKey('app_root'),
                  // Глобальное скругление углов приложения: при оттягивании
                  // у крайних разделов (Будильники слева / РП справа) края
                  // экрана остаются мягко закруглёнными, а не квадратными.
                  // Радиус 22px — аккуратный «современный» скруглённый экран.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Контент (Navigator) — всегда ОДИН слой, без анимации:
                        // раньше AnimatedSwitcher оборачивал и контент, и пятна,
                        // поэтому при смене темы ВЕСЬ экран «вспыхивал» (fade
                        // контента + дубль двух subtree).
                        child!,
                        // Пятна крови темы MUTILATED — ОТДЕЛЬНЫЙ слой поверх
                        // Navigator (включая drag-прокси при перетаскивании).
                        // Анимируется ТОЛЬКО слой пятен: плавно проявляются при
                        // включении темы и гаснут при выключении (450 мс).
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: _themeKey == 'mutilated'
                              ? const MutilatedSplatter(
                                  key: ValueKey('splatter'),
                                  child: SizedBox.expand(),
                                )
                              : _themeKey == 'metel'
                              ? const MetelAurora(
                                  key: ValueKey('metel_aurora'),
                                  child: SizedBox.expand(),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('no_splatter'),
                                ),
                        ),
                        // Плавающее мини-окошко Ады — поверх всех экранов.
                        // На Android сворачивание чата показывает СИСТЕМНЫЙ
                        // оверлей (вне приложения), поэтому внутренний пузырь
                        // монтируется только на web (плагин оверлея не
                        // поддерживает web — там пузырь внутриприложенный).
                        if (kIsWeb)
                          AiFloatingBubble(
                            onOpen: () {
                              aiFloating.value = false;
                              globalPrefs.setBool('ai_floating', false);
                              final ctx = navigatorKey.currentContext;
                              if (ctx != null) showAiGuideChat(ctx);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Домашний экран при запуске по будильнику (холодный старт).
///
/// Зачем отдельный виджет вместо «пушить WakeTaskScreen поверх»: сплэш,
/// который раньше был домашним, в конце вызывал `_goHome()` с
/// `pushAndRemoveUntil((route) => false)` и стирал экран будильника вместе
/// со всем стеком. Здесь экран задачи — И есть домашний: его некому снести,
/// а после решения задачи управление уходит в [_afterAlarmSolved].
///
/// Звук не играем: его крутит нативный AlarmForegroundService, который
/// уже запущен приёмником будильника (и работает даже с выключенным
/// экраном). Раньше параллельно играл ещё и Flutter-плеер, и втроём они
/// звучали как «какой-то другой звук».
class _AlarmBootHost extends StatefulWidget {
  final String payload;
  final VoidCallback onFinished;

  const _AlarmBootHost({required this.payload, required this.onFinished});

  @override
  State<_AlarmBootHost> createState() => _AlarmBootHostState();
}

class _AlarmBootHostState extends State<_AlarmBootHost> {
  // Future создаётся ОДИН раз: в build он пересоздавался бы на каждой
  // перестройке, и FutureBuilder заново читал бы будильники с диска.
  late final Future<Alarm?> _alarmFuture;

  @override
  void initState() {
    super.initState();
    _wakeScreenShowing = true;
    final id = widget.payload.substring('alarm:'.length);
    _alarmFuture = AlarmService().load().then(
      (_) => AlarmService().getById(id),
    );
  }

  @override
  void dispose() {
    _wakeScreenShowing = false;
    super.dispose();
  }

  Future<void> _finish() async {
    // На всякий случай глушим нативный звонок: если экран закрыли системной
    // кнопкой «Назад», сервис иначе гудел бы до своего таймаута.
    try {
      const MethodChannel(
        'com.wetidom.keramika/alarm_payload',
      ).invokeMethod('stopAlarmSound');
    } catch (_) {}
    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Alarm?>(
      future: _alarmFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          // Данные ещё читаются: показываем нейтральный фон, без сплэша и
          // без мигания (первый кадр будильника должен быть спокойным).
          return const Scaffold(body: SizedBox.expand());
        }
        final alarm = snap.data;
        if (alarm == null) {
          // Будильник уже удалён — просто уходим в обычный старт.
          WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
          return const Scaffold(body: SizedBox.expand());
        }
        return WakeTaskScreen(
          taskType: alarm.taskType,
          isTest: false,
          soundName: alarm.soundName,
          customSoundPath: alarm.customSoundPath,
          onDismissed: _finish,
        );
      },
    );
  }
}
