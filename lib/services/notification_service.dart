import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../models/alarm.dart';
import '../models/wake_task.dart';
import '../utils/android_settings.dart' as android_settings;
import 'alarm_scheduler.dart';
import 'prefs.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _enabled = true;
  bool _fullscreen = true;
  bool _initialized = false;
  bool? _notificationsEnabledCached; // Кэш статуса уведомлений

  // Когда пользователь отметил проверку или удалил RC — отменяем уведомления на сегодня.
  bool _rcCancelledToday = false;
  String? _rcCancelDateKey;

  static const int _rcBaseId = 100000;
  static const int _maxRcSlots = 40;

  /// Стабильный id по порядку в списке расписания, чтобы отмена работала однозначно.
  int _stableRcId(int index) {
    return _rcBaseId + (index.clamp(0, _maxRcSlots - 1));
  }

  static const _enabledKey = 'notifications_enabled';
  static const _fullscreenKey = 'notifications_fullscreen';

  // Light, frosted-white notification background (instead of the default black).
  static const Color _lightBg = Color(0xFFFDF2F6);

  bool get enabled => _enabled;
  bool get fullscreen => _fullscreen;
  bool get isInitialized => _initialized;

  // defaultTargetPlatform не бросает на web, в отличие от dart:io Platform.
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void Function(String? payload)? onNotificationTap;

  // Используем существующий метод-канал из MainActivity.kt,
  // где зарегистрирован обработчик getTimeZone.
  static const _tzChannel = MethodChannel('com.wetidom.keramika/alarm_payload');

  Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    // Устанавливаем часовой пояс устройства через нативный Android API,
    // чтобы tz.local не оставался UTC. Иначе zonedSchedule будет
    // срабатывать в неправильное время (на разницу часового пояса).
    await _setupDeviceTimezone();
    _enabled = globalPrefs.getBool(_enabledKey) ?? true;
    _fullscreen = globalPrefs.getBool(_fullscreenKey) ?? true;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('ic_notification');
    final initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) =>
          onNotificationTap?.call(response.payload),
    );
    _createChannels();
    // After reinstall, SharedPreferences may survive via Android auto-backup
    // while OS notification permission is revoked. Sync stored state and
    // clear the alarm-asked timestamp so the alarm settings screen is
    // re-prompted on the next launch.
    if (_supported) {
      final osEnabled = await areNotificationsEnabled();
      if (_enabled && !osEnabled) {
        // Разрешение на уведомления пропало (типично после переустановки
        // APK: prefs живут через auto-backup, а OS-разрешение сброшено).
        // ВАЖНО: НЕ перезаписываем pref — это НАМЕРЕНИЕ пользователя
        // («уведомления включены»). _enabled=false только на эту сессию;
        // при старте _rescheduleAllOnStart увидит wantNotifs=true и
        // перезапросит разрешение ДО перепланировки будильников.
        _enabled = false;
        // Clear the alarm timestamp so the next explicit permission request
        // takes the user straight to the alarms & reminders flow.
        await globalPrefs.remove(_askedAtKey);
      }
    }
    _initialized = true;
  }

  /// Получает IANA-имя часового пояса устройства через нативный Android API
  /// и устанавливает его как tz.local для корректной работы zonedSchedule.
  Future<void> _setupDeviceTimezone() async {
    if (!_supported) return;
    try {
      final ianaName = await _tzChannel.invokeMethod<String>('getTimeZone');
      if (ianaName != null && ianaName.isNotEmpty) {
        try {
          tz.setLocalLocation(tz.getLocation(ianaName));
          return;
        } catch (_) {}
      }
    } catch (_) {}

    // Fallback: вычисляем Etc/GMT по смещению.
    // ВАЖНО: в IANA базе Etc/GMT имеет инвертированный знак!
    // Etc/GMT-3 = UTC+3 (Москва), Etc/GMT+5 = UTC-5 (Нью-Йорк).
    try {
      final offset = DateTime.now().timeZoneOffset;
      final totalMinutes = offset.inMinutes;
      final hours = totalMinutes.abs() ~/ 60;
      final sign = totalMinutes >= 0 ? '-' : '+'; // инвертировано!
      final tzId = 'Etc/GMT$sign$hours';
      tz.setLocalLocation(tz.getLocation(tzId));
    } catch (_) {}
  }

  /// Запрос разрешений по кнопке «Выдать» — ТОЛЬКО «Будильники и
  /// напоминания». Вызывается по явному действию пользователя
  /// («Выдать», промпты в экране будильников).
  ///
  /// Диалог разрешения на уведомления ЗДЕСЬ не показываем: на Android 14+
  /// системного диалога для точных будильников вообще нет (работает только
  /// экран специального доступа), а путать пользователя запросом уведы
  /// вместо будильников — не то, чего он ждёт. Разрешение на уведомления
  /// запрашивается отдельно — переключателем уведомлений.
  ///
  /// Цепочка intent'ов из utils/android_settings.dart: AOSP «Alarms &
  /// reminders» → MIUI-редактор разрешений → per-app экран уведомлений
  /// (там подраздел «Будильники и напоминания») → карточка приложения.
  static const _askedAtKey = 'permissions_alarm_asked_at';

  Future<void> requestPermissions() async {
    if (!_isAndroid) return;
    final opened = await android_settings.openExactAlarmSettings();
    if (opened) {
      await globalPrefs.setString(
        _askedAtKey,
        DateTime.now().toIso8601String(),
      );
    }
  }

  /// Мягкая проверка разрешений без выбрасывания в системные настройки:
  /// открывает экран батареи ТОЛЬКО если ограничения на батарею ещё
  /// действуют (battery optimization включён). Если ограничений нет —
  /// ничего не открываем: сохранение будильника не должно выдёргивать
  /// пользователя из приложения каждый раз.
  Future<void> requestPermissionsSoft() async {
    if (!_isAndroid) return;
    // Если батарея уже без ограничений — открывать нечего.
    final unrestricted = await AlarmScheduler.isIgnoringBatteryOptimizations();
    if (unrestricted) return;
    await android_settings.openAppSettingsAndroid();
  }

  /// Запрашивает системное разрешение уведомлений, если оно ещё не выдано.
  /// Нужен именно перед постановкой будильника: иначе AlarmManager может
  /// сработать, но Android silently отбросит само уведомление.
  Future<bool> ensureNotificationPermission() async {
    if (!_isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    var granted = await android?.areNotificationsEnabled() ?? true;
    if (!granted) {
      try {
        // Системный диалог разрешения открыт — PIN-размытие в «недавних»
        // не показываем, чтобы оно не «прыгало» при переходе.
        systemUiActive = true;
        await android?.requestNotificationsPermission();
        systemUiActive = false;
      } catch (_) {}
      _notificationsEnabledCached = null;
      granted = await android?.areNotificationsEnabled() ?? true;
    }
    _notificationsEnabledCached = granted;
    return granted;
  }

  /// Whether notifications are allowed at the OS level (Android 13+).
  /// Returns true when not supported / can't be determined.
  Future<bool> areNotificationsEnabled() async {
    if (_notificationsEnabledCached != null)
      return _notificationsEnabledCached!;
    if (!_supported) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final result = await android?.areNotificationsEnabled() ?? true;
    _notificationsEnabledCached = result;
    return result;
  }

  /// Reset the cached notification status to force a fresh check next time.
  void resetNotificationStatusCache() {
    _notificationsEnabledCached = null;
    notifyListeners(); // Чтобы UI обновился
  }

  Future<void> _zonedScheduleWithFallback(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduled,
    NotificationDetails details, {
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (e) {
      // Exact failed → fallback to inexact (still fires, just less precise)
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
        );
      } catch (e2) {
        // Both failed — rethrow so caller knows something is wrong
        throw Exception('Scheduling failed: $e, fallback: $e2');
      }
    }
  }

  Future<NotificationAppLaunchDetails?> getLaunchDetails() async {
    if (!_supported) return null;
    try {
      return await _plugin.getNotificationAppLaunchDetails();
    } catch (_) {
      return null;
    }
  }

  void _createChannels() {
    const channels = [
      AndroidNotificationChannel(
        'keramika_alarm',
        'Alarms',
        description: 'Alarm notifications',
        importance: Importance.max,
        playSound: false,
      ),
      AndroidNotificationChannel(
        'keramika_rc',
        'Reality Checks',
        description: 'Reality check reminders',
        importance: Importance.max,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'keramika_main',
        'Keramika',
        description: 'App notifications',
        importance: Importance.high,
      ),
    ];
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final c in channels) {
      android?.createNotificationChannel(c);
    }
  }

  Future<void> setEnabled(bool value, {bool requestPermission = true}) async {
    if (value && _isAndroid && requestPermission) {
      try {
        // When enabling, check and request notifications permission — handles the case where
        // SharedPreferences survived a reinstall but OS permission was revoked.
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        // Ждём обновления статуса — системный диалог асинхронный,
        // areNotificationsEnabled() может вернуть false сразу после
        // вызова, хотя пользователь уже дал разрешение.
        bool granted = await android?.areNotificationsEnabled() ?? true;
        if (!granted) {
          // User denied or not prompted yet — показываем системный диалог
          // запроса разрешения на уведомления (не просто настройки).
          try {
            await android?.requestNotificationsPermission();
          } catch (_) {}
          granted = await android?.areNotificationsEnabled() ?? true;
          _notificationsEnabledCached = null;
        }
        if (!granted) {
          // User denied — keep the toggle OFF and notify.
          _enabled = false;
          globalPrefs.setBool(_enabledKey, false);
          notifyListeners();
          return;
        }
        // Переключатель — ТОЛЬКО про уведомления. Разрешение на точные
        // будильники запрашивается отдельно, по явному действию
        // («Выдать», промпты в экране будильников), а не при каждом
        // включении уведомлений.
      } catch (_) {
        // Platform channel error — proceed with setting the pref anyway.
      }
    }
    _enabled = value;
    globalPrefs.setBool(_enabledKey, value);
    if (!value && _isAndroid) {
      cancelAll();
    }
    notifyListeners();
  }

  Future<void> setFullscreen(bool value) async {
    _fullscreen = value;
    globalPrefs.setBool(_fullscreenKey, value);
    notifyListeners();
    // Если включили fullscreen — открываем настройки отображения
    // поверх других приложений (SYSTEM_ALERT_WINDOW), которое нужно
    // для fullScreenIntent на Android 14+ — НО только если разрешение
    // ещё не выдано (иначе при каждом включении вылезает окно настроек).
    if (value && _isAndroid) {
      try {
        final canUse = await android_settings.canUseFullScreenIntent();
        if (!canUse) {
          await android_settings.openFullScreenNotifSettings();
        }
      } catch (_) {}
    }
  }

  /// Ежедневное напоминание (например, утренний отчёт Ады в 08:00).
  /// Повторяется каждый день в указанное время, пока не отменено.
  Future<void> scheduleDailyReminder(
    int id,
    int hour,
    int minute,
    String title,
    String body, {
    String? payload,
  }) async {
    if (!_supported || !_enabled) {
      debugPrint(
        '[ada-tracking] skip reminder $id supported=$_supported enabled=$_enabled',
      );
      return;
    }
    try {
      final now = DateTime.now();
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (scheduled.isBefore(tz.TZDateTime.from(now, tz.local))) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      debugPrint(
        '[ada-tracking] scheduling $id at $scheduled (tz.local=${tz.local})',
      );
      final details = const NotificationDetails(
        android: AndroidNotificationDetails(
          'ada_reminders',
          'Напоминания Ады',
          channelDescription: 'Утренний отчёт и вечерний разбор',
          // High + звук: раньше был defaultImportance — тихое уведомление
          // в шторке, которое легко не заметить. Теперь отчёт Ады
          // всплывает (heads-up) и играет звук.
          importance: Importance.high,
          priority: Priority.high,
          colorized: true,
          color: _lightBg,
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
        ),
      );
      await _zonedScheduleWithFallback(
        id,
        title,
        body,
        scheduled,
        details,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[ada-tracking] reminder $id error: $e');
    }
  }

  /// Отменяет ежедневное напоминание.
  Future<void> cancelReminder(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// Напоминание привычки «Вспомнить всё»: [weekday] 0 = каждый день,
  /// 1–7 = конкретный день недели (используется dayOfWeekAndTime, чтобы
  /// уведомление приходило только в выбранные дни).
  Future<void> scheduleHabitReminder(
    int id,
    int weekday,
    int hour,
    int minute,
    String title,
    String body, {
    String? payload,
  }) async {
    if (!_supported || !_enabled) {
      debugPrint(
        '[habit-reminder] skip $id supported=$_supported enabled=$_enabled',
      );
      return;
    }
    try {
      final now = DateTime.now();
      var scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (scheduled.isBefore(tz.TZDateTime.from(now, tz.local))) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      // Для конкретного дня недели подгоняем ближайшее наступление.
      final weekly = weekday >= 1 && weekday <= 7;
      if (weekly) {
        var diff = weekday - scheduled.weekday;
        if (diff < 0) diff += 7;
        if (diff > 0) scheduled = scheduled.add(Duration(days: diff));
      }
      debugPrint(
        '[habit-reminder] scheduling $id weekday=$weekday at $scheduled',
      );
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'habit_reminders',
          'Напоминания привычек',
          channelDescription: 'Напоминание «Вспомнить всё» о привычках',
          importance: Importance.high,
          priority: Priority.high,
          colorized: true,
          color: _lightBg,
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
        ),
      );
      await _zonedScheduleWithFallback(
        id,
        title,
        body,
        scheduled,
        details,
        matchDateTimeComponents: weekly
            ? DateTimeComponents.dayOfWeekAndTime
            : DateTimeComponents.time,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[habit-reminder] $id error: $e');
    }
  }

  Future<void> showInstant(int id, String title, String body) async {
    if (!_enabled || !_initialized || !_supported) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'keramika_main',
        'Keramika',
        channelDescription: 'App notifications',
        importance: Importance.high,
        priority: Priority.high,
        colorized: true,
        color: _lightBg,
        largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
      ),
    );
    await _plugin.show(id, title, body, details);
  }

  Future<bool> scheduleAlarm(Alarm alarm) async {
    if (!_enabled || !_initialized || !_supported) {
      return false;
    }
    if (!await ensureNotificationPermission()) {
      return false;
    }
    final now = DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.time.hour,
      alarm.time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    if (alarm.repeatDays.isNotEmpty) {
      final dayOfWeek = scheduled.weekday;
      if (!alarm.repeatDays.contains(dayOfWeek)) {
        for (int i = 1; i <= 7; i++) {
          final candidate = scheduled.add(Duration(days: i));
          if (alarm.repeatDays.contains(candidate.weekday)) {
            scheduled = candidate;
            break;
          }
        }
      }
    }
    final title = alarm.label.isNotEmpty ? alarm.label : 'Alarm';
    String body;
    if (alarm.taskType == WakeUpTask.math) {
      body = 'Задача: решить пример';
    } else if (alarm.taskType == WakeUpTask.pattern) {
      body = 'Задача: повторить паттерн';
    } else if (alarm.taskType == WakeUpTask.memory) {
      body = 'Задача: вспомни слово';
    } else {
      body =
          '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}';
    }
    final soundName = _rawSoundName(alarm);
    final customPath = alarm.soundName == 'Custom'
        ? alarm.customSoundPath
        : null;

    if (await AlarmScheduler.isAvailable()) {
      final ok = await AlarmScheduler.scheduleAlarmClock(
        id: alarm.id.hashCode,
        title: title,
        body: body,
        channelId: 'keramika_alarm',
        channelName: 'Alarms',
        soundName: soundName,
        vibrate: alarm.vibrate,
        fireTime: scheduled,
        hour: alarm.time.hour,
        minute: alarm.time.minute,
        repeatDays: alarm.repeatDays.join(','),
        payload: 'alarm:${alarm.id}',
        fullscreen: true,
        customSoundPath: customPath,
      );
      if (ok) return true;
    }

    final tzScheduled = tz.TZDateTime.from(scheduled, tz.local);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'keramika_alarm',
        'Alarms',
        channelDescription: 'Alarm notifications',
        importance: Importance.max,
        priority: Priority.max,
        // Если native AlarmManager недоступен (например, exact alarm
        // permission ещё не выдан), fallback должен всё равно быть слышимым.
        playSound: true,
        sound: RawResourceAndroidNotificationSound(_rawSoundName(alarm)),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: alarm.vibrate,
        category: AndroidNotificationCategory.alarm,
        colorized: true,
        color: _lightBg,
        fullScreenIntent: true,
        largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
      ),
    );
    try {
      await _zonedScheduleWithFallback(
        alarm.id.hashCode,
        title,
        body,
        tzScheduled,
        details,
        payload: 'alarm:${alarm.id}',
        matchDateTimeComponents:
            alarm.repeatDays.length == 7 || alarm.repeatDays.isEmpty
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _rawSoundName(Alarm alarm) {
    if (alarm.soundName == 'Custom' && alarm.customSoundPath != null)
      return 'alarm_default';
    switch (alarm.soundName) {
      case 'Gentle':
        return 'gentle';
      case 'Classic':
        return 'classic';
      case 'Digital':
        return 'digital';
      case 'Nature':
        return 'nature';
      default:
        return 'alarm_default';
    }
  }

  Future<void> cancelAlarm(String alarmId) async {
    if (!_supported) return;
    await AlarmScheduler.cancelAlarmClock(alarmId.hashCode);
    await _plugin.cancel(alarmId.hashCode);
  }

  Future<void> scheduleRealityChecks(
    List<TimeOfDay> schedule,
    List<String> questions, {
    required String title,
    bool cancelExisting = false,
  }) async {
    if (!_enabled || !_initialized || !_supported) return;

    // Сброс отмены при наступлении нового дня.
    final todayKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    if (_rcCancelDateKey != null && _rcCancelDateKey != todayKey) {
      _rcCancelledToday = false;
      _rcCancelDateKey = null;
    }

    // Если уведомления уже отменены пользователем или отмечены — не перепланировать.
    if (_rcCancelledToday) return;

    if (cancelExisting) await cancelAllRealityChecks();

    final now = DateTime.now();
    final useNative = await AlarmScheduler.isAvailable();

    // Если вопросов нет или они пустые — ничего не планируем.
    // Никаких fallback-вопросов, чтобы пользователь получал уведомления
    // только со своим текстом.
    if (questions.isEmpty || questions.every((q) => q.trim().isEmpty)) return;

    // Планируем каждый слот: будущий — на сегодня, уже прошедший — на
    // завтра (с ежедневным повтором). Иначе при «позднем» открытии
    // приложения сегодняшние слоты вообще не запланируются, и напоминания
    // не придут ни сегодня, ни завтра.
    final List<DateTime> toSchedule = [];
    for (final t in schedule) {
      final scheduled = DateTime(
        now.year,
        now.month,
        now.day,
        t.hour,
        t.minute,
      );
      toSchedule.add(
        scheduled.isAfter(now)
            ? scheduled
            : scheduled.add(const Duration(days: 1)),
      );
    }

    // Сначала отменяем ВСЕ возможные ID-слоты, чтобы не было дубликатов после изменений расписания.
    for (int i = _rcBaseId; i < _rcBaseId + _maxRcSlots; i++) {
      await AlarmScheduler.cancelAlarmClock(i);
      await _plugin.cancel(i);
    }

    for (int i = 0; i < toSchedule.length; i++) {
      final scheduled = toSchedule[i];
      final q = questions[i % questions.length];
      final id = _stableRcId(i);

      if (useNative) {
        try {
          final ok = await AlarmScheduler.scheduleAlarmClock(
            id: id,
            title: title,
            body: q,
            channelId: 'keramika_rc',
            channelName: 'Reality Checks',
            // Системный звук уведомлений телефона, а не встроенный
            // будильниковый — пользователь управляет им в настройках ОС.
            soundName: 'System',
            vibrate: true,
            fireTime: scheduled,
            hour: scheduled.hour,
            minute: scheduled.minute,
            repeatDays: '1,2,3,4,5,6,7',
            payload: 'rc',
            fullscreen: false,
          );
          if (!ok) throw Exception('native scheduling failed');
        } catch (e) {
          final tzScheduled = tz.TZDateTime.from(scheduled, tz.local);
          final details = NotificationDetails(
            android: AndroidNotificationDetails(
              'keramika_rc',
              'Reality Checks',
              channelDescription: 'Reality check reminders',
              importance: Importance.high,
              priority: Priority.high,
              colorized: true,
              color: _lightBg,
              enableVibration: true,
              largeIcon: const DrawableResourceAndroidBitmap(
                'ic_notification_large',
              ),
            ),
          );
          await _zonedScheduleWithFallback(
            id,
            'Reality Check',
            q,
            tzScheduled,
            details,
            payload: 'rc',
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      } else {
        final tzScheduled = tz.TZDateTime.from(scheduled, tz.local);
        final details = NotificationDetails(
          android: AndroidNotificationDetails(
            'keramika_rc',
            'Reality Checks',
            channelDescription: 'Reality check reminders',
            importance: Importance.high,
            priority: Priority.high,
            colorized: true,
            color: _lightBg,
            largeIcon: const DrawableResourceAndroidBitmap(
              'ic_notification_large',
            ),
          ),
        );
        await _zonedScheduleWithFallback(
          id,
          'Reality Check',
          q,
          tzScheduled,
          details,
          payload: 'rc',
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    }
  }

  Future<void> cancelAllRealityChecks() async {
    if (!_initialized || !_supported) return;
    for (int i = _rcBaseId; i < _rcBaseId + _maxRcSlots; i++) {
      await AlarmScheduler.cancelAlarmClock(i);
      await _plugin.cancel(i);
    }
    _rcCancelledToday = true;
    _rcCancelDateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  }

  Future<void> cancelAll() async {
    if (!_supported) return;
    await cancelAllRealityChecks();
    await _plugin.cancelAll();
  }

  /// Resets the per-day reality-check cancellation flag so notifications can
  /// be rescheduled after the user changes checks or before all checks have
  /// been marked as done today.
  void resetRcCancellation() {
    _rcCancelledToday = false;
    _rcCancelDateKey = null;
  }

  /// Opens the app's notification settings where user can enable notifications and exact alarms.
  Future<void> openAppSettings() async {
    if (!_supported) return;
    try {
      // Trying to open general app settings which contains notification settings
      await android_settings.openAppSettingsAndroid();
    } catch (e) {
      // Fallback: try exact alarm settings specifically
      try {
        await android_settings.openExactAlarmSettings();
      } catch (e2) {
        // Last resort: open app info page
        await android_settings.openAppSettingsAndroid();
      }
    }
  }
}
