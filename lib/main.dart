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
import 'utils/android_settings.dart'
    show setSecureWindow;
import 'screens/lock_screen.dart';
import 'screens/home_screen.dart';
import 'screens/wake_task_screen.dart';
import 'widgets/mutilated_overlay.dart';
import 'l10n/locale_provider.dart';
import 'l10n/translations.dart';
import 'services/pin_service.dart';
import 'services/settings_service.dart';
import 'services/notification_service.dart';
import 'services/alarm_service.dart';
import 'services/reality_check_service.dart';
import 'services/habit_service.dart';
import 'services/task_service.dart';
import 'services/timer_service.dart';
import 'services/prefs.dart';
import 'services/ai_guide_service.dart';
import 'services/json_file.dart';
import 'services/migration.dart';
import 'overlay/ada_overlay.dart';
import 'overlay/overlay_bridge.dart';
import 'widgets/ai_guide.dart';
import 'utils/page_transitions.dart';
import 'utils/snackbar.dart';

final NotificationService notificationService = NotificationService();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
Timer? _autoSaveTimer;
// Флаг — WakeTaskScreen уже показан, не пушить второй при тапе
// по уведомлению (onNewIntent → onNewAlarmPayload).
bool _wakeScreenShowing = false;
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
  } catch (_) {}
  // Увеличиваем интервал с 3 до 10 секунд, чтобы снизить нагрузку на диск.
  _autoSaveTimer = Timer(const Duration(seconds: 10), _autoSaveTick);
}

void stopAutoSave() {
  _autoSaveTimer?.cancel();
  _autoSaveTimer = null;
}

Timer? _autoExportTimer;
bool _isAutoExporting = false;
// Время последнего автоэкспорта — чтобы не «забывать» час, пока приложение
// было закрыто, и не делать лишние бэкапы при каждом запуске.
const _lastAutoExportKey = 'last_auto_export_at';
// Нативка слушает saveToDownloads на канале alarm_payload (MainActivity).
// Раньше здесь был канал '.../backup' — вызов падал в MissingPluginException,
// и бэкап молча писался в невидимую папку Android/data вместо Download.
const _backupChannel = MethodChannel('com.wetidom.keramika/alarm_payload');
// Канал сигналов жизненного цикла Activity → Dart: onUserLeaveHint —
// пользователь реально покидает приложение (Home/«недавние»/другое
// приложение), но НЕ при открытии шторки и системных диалогов.
const _lifecycleChannel = MethodChannel('com.wetidom.keramika/lifecycle');

/// Включает автоэкспорт: разовый прогон (если нужно) + почасовой таймер.
/// [silent] — true для фоновых прогонов (старт/возврат в приложение),
/// чтобы не спамить снекбаром; ручное включение в настройках показывает
/// подтверждение.
void startAutoExport({bool runImmediately = true, bool silent = false}) {
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
    globalPrefs.setInt(
      _lastAutoExportKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('[auto-export] OK -> $saved');
  } catch (e, st) {
    debugPrint('[auto-export] FAILED: $e\n$st');
  }
  _isAutoExporting = false;
  _autoExportTimer?.cancel();
  _autoExportTimer = Timer(const Duration(hours: 1), _autoExportTick);
}

/// «Догоняющий» прогон: если автоэкспорт включён и с последнего бэкапа
/// прошёл час и больше (например, приложение было закрыто — Dart-таймер
/// в фоне не работает), делаем бэкап молча при старте или возврате в
/// приложение.
Future<void> maybeCatchUpAutoExport() async {
  final enabled = await SettingsService.loadAutoExport();
  debugPrint('[auto-export] catch-up: enabled=$enabled');
  if (!enabled) return;
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
  _isAutoExporting = false;
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
  if (settingsRaw == null) {
    // Строковые и булевы настройки читаем РАЗДЕЛЬНЫМИ геттерами:
    // getBool() на строковом значении (например setting_theme='rose')
    // бросает TypeError и роняет экспорт целиком.
    const stringSettingKeys = {'setting_theme', 'setting_locale'};
    const boolSettingKeys = {
      'setting_peach_dark',
      'setting_experimental',
      'setting_auto_save',
      'setting_dev_mode',
      'setting_auto_export',
    };
    for (final key in stringSettingKeys) {
      final v = globalPrefs.getString(key);
      if (v != null && v.isNotEmpty) out[key] = v;
    }
    for (final key in boolSettingKeys) {
      final v = globalPrefs.getBool(key);
      if (v != null) out[key] = v;
    }
  }

  // Пробрасываем любые поля, которые уже были в файле app_settings.json.
  if (settingsRaw != null) {
    final settings = jsonDecode(settingsRaw) as Map<String, dynamic>;
    for (final entry in settings.entries) {
      if (entry.value != null) out[entry.key] = entry.value;
    }
  }

  for (final k in [
    'notifications_enabled',
    'notifications_fullscreen',
    'welcome_shown',
    'popup_warning_shown',
    'app_pin',
  ]) {
    final v = globalPrefs.get(k);
    if (v != null) out[k] = v;
  }
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
  if (Platform.isAndroid) {
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
const _alarmPayloadChannel = MethodChannel(
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

Future<void> _rescheduleAll() async {
  final alarmSvc = AlarmService();
  await alarmSvc.load();
  for (final a in alarmSvc.alarms) {
    if (a.enabled) {
      try {
        await notificationService.scheduleAlarm(a);
      } catch (_) {}
    }
  }
  await _rescheduleRealityChecks();
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
  await _rescheduleAll();
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
  for (final a in alarmSvc.alarms) {
    if (a.enabled) {
      try {
        await notificationService.scheduleAlarm(a);
      } catch (_) {}
    }
  }
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
    (_, __) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete();
    },
    onError: (_, __) {
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
  runApp(const AdaOverlayApp());
}

/// Заранее декодированный логотип сплэша — первый кадр рисуется с ним
/// МГНОВЕННО, без «мигания» и подгрузки картинки в рантайме.
ui.Image? preDecodedLogo;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Декодируем логотип ДО первого кадра: на слабых телефонах Image.asset
  // не успевает прогрузиться к началу сплэша и картинка мигает.
  try {
    final data = await rootBundle.load('assets/keramika.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    preDecodedLogo = frame.image;
    codec.dispose();
  } catch (_) {
    // Если декод не удался — сплэш просто покажет Image.asset как раньше.
  }
  // Инициализируем SharedPreferences ОДИН раз ДО всего.
  await initPrefs();
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
  await migrateFromPrefs();
  await notificationService.init();
  notificationService.onNotificationTap = _handleNotificationTap;
  final launchDetails = await notificationService.getLaunchDetails();
  final hasPin = await PinService.hasPin();
  final theme = await SettingsService.loadThemeMode();
  final lang = await SettingsService.loadLanguageCode();
  final peachDark = await SettingsService.loadPeachDark();
  // Прогреваем живые флаги режимов до первого Home-кадра:
  // кнопка BERSERK и карточки не ждут открытия настроек.
  await SettingsService.loadPerfectionism();
  await SettingsService.loadBerserk();
  runApp(
    KeramikaApp(
      initialLocked: hasPin,
      initialTheme: theme,
      initialLanguageCode: lang,
      initialPeachDark: peachDark,
    ),
  );
  // Логотип прогреваем НЕ блокируя старт: сплэш анимируется 1.8с,
  // картинка успеет загрузиться к первому кадру. Так окно Android
  // (теперь фирменного цвета) не висит лишние секунды перед runApp.
  _precacheLogo();

  // Разрешения на уведомления и будильники пользователь включает сам
  // в настройках приложения (SettingsScreen). Здесь только перепланировка.
  Future.delayed(const Duration(milliseconds: 500), _rescheduleAllOnStart);

  // Автосохранение — загружаем данные ПЕРВЫМ ДЕЛОМ, потом стартуем таймер
  // только если пользователь включал autosave.
  await HabitService().load();
  await TaskService().load();
  await AlarmService().load();
  await RealityCheckService().load();
  await TimerService().load();

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

  // Флаг — уже обработали запуск от будильника, чтобы не открыть
  // WakeTaskScreen дважды (из getLaunchDetails и getAlarmPayload).
  bool _alarmHandled = false;

  if (launchDetails?.didNotificationLaunchApp == true) {
    _pendingAlarmPayload = launchDetails?.notificationResponse?.payload;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(_pendingAlarmPayload);
      _pendingAlarmPayload = null;
      _alarmHandled = true;
    });
  }

  // Также проверяем payload из intent (для fullScreenIntent).
  try {
    final intentPayload = await _alarmPayloadChannel.invokeMethod<String>(
      'getAlarmPayload',
    );
    if (!_alarmHandled && intentPayload != null && intentPayload.isNotEmpty) {
      _pendingAlarmPayload = intentPayload;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(_pendingAlarmPayload);
        _pendingAlarmPayload = null;
      });
    }
  } catch (_) {}

  // Слушаем новые payload'и когда приложение уже запущено (onNewIntent)
  // и сигнал о перезагрузке телефона (onBootCompleted).
  _alarmPayloadChannel.setMethodCallHandler((call) async {
    if (call.method == 'onNewAlarmPayload') {
      // Если WakeTaskScreen уже виден — игнорируем повторный payload
      // (пользователь тапнул по уведомлению, пока будильник уже звонит).
      if (_wakeScreenShowing) return;
      final payload = call.arguments as String?;
      if (payload != null && payload.isNotEmpty) {
        _handleNotificationTap(payload);
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

  const KeramikaApp({
    super.key,
    this.initialLocked = false,
    this.initialTheme = 'light',
    this.initialLanguageCode = 'system',
    this.initialPeachDark = false,
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
  Key _appKey = UniqueKey();
  int _refreshCounter = 0;
  // Плавный переход при смене темы и языка: мягкое затухание и возврат
  // (оптимально проверено — как было). При смене ЯЗЫКА цвет подложки не
  // меняется (тема та же), поэтому никаких белых/чёрных вспышек — просто
  // деликатное затемнение и проявление контента.
  bool _locked = false;
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
      default:
        return ThemeMode.system;
    }
  }

  String get themeKey => _themeKey;

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

  void _goHome() {
    aiLockScreenVisible.value = false;
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        slideUpRoute(const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _goSplash() {
    final nav = navigatorKey.currentState;
    if (nav != null) {
      // Плавный fade (не slide): после PIN сплэш не «прыгает» снизу —
      // аватарка появляется мягко своим fade+scale, без двойного движения
      // (переход экрана + анимация аватарки одновременно).
      nav.pushAndRemoveUntil(
        fadeRoute(SplashScreen(onDone: _goHome)),
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
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        slideUpRoute(LockScreen(onUnlock: () => unlock())),
        (route) => false,
      );
    }
  }

  Future<void> refreshApp() async {
    setState(() {
      _appKey = UniqueKey();
      _refreshCounter++;
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
    setState(() => _locked = false);
    _goSplash();
  }

  void initState() {
    super.initState();
    _themeKey = widget.initialTheme;
    _languageCode = widget.initialLanguageCode;
    _peachDark = widget.initialPeachDark;
    _locked = widget.initialLocked;
    aiLockScreenVisible.value = _locked;
    WidgetsBinding.instance.addObserver(this);
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
    if (state == AppLifecycleState.resumed) {
      // Приложение снова на переднем плане.
      // Системный UI (файл-пикер и т.п.) закрылся — флаг сбрасываем.
      systemUiActive = false;
      HabitService().normalizeIfDayChanged();
      rescheduleAllNotifications();
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
    final cacheKey = '${scheme.hashCode}|$isGrokStyle';
    final cached = isDark ? _darkThemeCache : _lightThemeCache;
    final cachedKey = isDark ? _darkThemeCacheKey : _lightThemeCacheKey;
    if (cached != null && cachedKey == cacheKey) return cached;

    final built = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Caveat — рукописный «анимешный» шрифт с полной кириллицей
      // (4 начертания в assets/fonts). Применяется ко ВСЕМУ тексту темы;
      // экраны, задающие styles через copyWith, наследуют fontFamily.
      fontFamily: 'Caveat',
      // Лёгкая цветокоррекция «приятнее глазу» без смены палитр: чуть
      // больше воздуха в тексте, мягче тени и скругления карточек,
      // деликатный размытый фон вместо сплошного — глаза меньше устают.
      // Базовый textTheme: слегка крупнее стандарта, чтобы компенсировать
      // малую x-высоту Caveat (глобальный TextScaler больше не используем —
      // он не доходил до части виджетов). Здесь размеры применяются
      // безусловно.
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .black
          .apply(
            fontFamily: 'Caveat',
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          )
          .copyWith(
            // Немного выше стандарта, но без прежнего перекоса: прежний
            // глобальный коэффициент 1.35 не долетал до части экранов,
            // а эти размеры применяются везде, включая привычки и задачи.
            titleMedium: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
            titleSmall: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 21,
              fontWeight: FontWeight.w500,
            ),
            bodyMedium: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            bodySmall: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
            labelSmall: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            labelMedium: const TextStyle(
              fontFamily: 'Caveat',
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: scheme.surfaceContainerLow,
        shadowColor: scheme.shadow.withValues(alpha: isDark ? 0.30 : 0.12),
        surfaceTintColor: scheme.primary.withValues(
          alpha: isDark ? 0.03 : 0.025,
        ),
        shape: isGrokStyle
            ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              )
            : const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
      ),
      // Цветокоррекция: единый мягкий стиль для всех диалогов и боттом-
      // шитов (светлее/воздушнее, скругление как у карточек) — без смены
      // цветовых тем.
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isGrokStyle ? 16 : 28),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        modalBackgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(isGrokStyle ? 16 : 28),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: isGrokStyle
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      // Тултипы (долгое зажатие кнопок — «Ада», «Будильники» и т.п.):
      // тематические, мягкие, с чётким текстом вместо серо-чёрной плашки.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.14),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(milliseconds: 2500),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      ),
      textSelectionTheme: const TextSelectionThemeData(),
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
      key: _appKey,
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
                return ColorScheme.fromSeed(
                  seedColor: Colors.purple.shade100,
                  brightness: Brightness.light,
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
                  seedColor: Colors.purple.shade300,
                  brightness: Brightness.dark,
                );
              })();

        return MaterialApp(
          title: 'Keramika',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
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
          // Плавная смена темы: цвета интерфейса (фон, карточки, тексты)
          // перетекают за 420 мс вместо резкого мгновенного переключения.
          themeAnimationDuration: const Duration(milliseconds: 320),
          themeAnimationCurve: Curves.easeOutCubic,
          home: _locked
              ? LockScreen(onUnlock: () => unlock())
              : SplashScreen(
                  key: ValueKey('splash_$_refreshCounter'),
                  onDone: _goHome,
                ),
          builder: (context, child) {
            // Глобальный множитель шрифта убран: TextScaler.linear(1.35)
            // НЕ применялся к виджетам, оборачивающим текст в собственный
            // MediaQuery (поэтому в привычках/задачах шрифт «не менялся»).
            // Базовые размеры теперь подняты в самой теме (_buildThemeData)
            // и точечно в проблемных местах — работает везде одинаково.
            // Системную навигационную панель красим в цвет фона приложения:
            // иначе внизу (под контентом) видна белая полоса, за которую
            // «залезает» экран при pull-to-refresh. Вызывается при каждой
            // перестройке темы — дёшево (один вызов в кадр).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final theme = Theme.of(context);
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
                      theme.brightness == Brightness.dark
                      ? Brightness.light
                      : Brightness.dark,
                  // Android 15+ (targetSdk 35+) накладывает СВОЮ контрастную
                  // белую подложку на навбар поверх нашего цвета — отключаем,
                  // иначе внизу всё равно видна белая полоса.
                  systemNavigationBarContrastEnforced: false,
                  statusBarColor: Colors.transparent,
                ),
              );
            });
            // Системный textScaler оставляем как есть — пользователь мог
            // включить крупный шрифт в системе; дополнительно не трогаем.
            return LocaleProvider(
                locale: resolved,
              // БЕЗ меняющегося key: при смене темы/языка не пересоздаём
              // Navigator и плавающее окошко (иначе открытый чат закрывался,
              // а пузырь терял состояние).
              // Тема перетекает штатной анимацией MaterialApp (AnimatedTheme),
              // язык — просто мгновенной плавной сменой текста. Никаких
              // своих затемнений, размытий и вспышек.
              child: KeyedSubtree(
                key: const ValueKey('app_root'),
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
                          : const SizedBox.shrink(key: ValueKey('no_splatter')),
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
            );
          },
        );
      },
    );
  }
}
