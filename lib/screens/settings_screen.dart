import 'dart:async';
import '../services/haptics.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../utils/android_settings.dart';
import '../services/pin_service.dart';
import '../services/reality_check_service.dart';
import '../services/alarm_service.dart';
import '../services/settings_service.dart';
import '../services/timer_service.dart';
import '../services/prefs.dart';
import '../services/json_file.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../services/nutrition_service.dart';
import '../services/ai_guide_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_circle_toggle.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_keyboard_body.dart';
import 'lock_screen.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import 'changelog_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

/// Чип, который реагирует на зажатие N секунд (по таймеру), а не
/// через системный LongPressGesture (тот срабатывает через ~0.5с).
/// Нужен для темы MUTILATED, где пасхалка «Вы элегантны?» показывается,
/// только если держать плашку 10 секунд.
class _LongPressChip extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final VoidCallback onLongPress;

  const _LongPressChip({
    required this.child,
    required this.duration,
    required this.onLongPress,
  });

  @override
  State<_LongPressChip> createState() => _LongPressChipState();
}

class _LongPressChipState extends State<_LongPressChip> {
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    _timer = Timer(widget.duration, () {
      widget.onLongPress();
      _timer = null;
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressDown: (_) => _start(),
      onLongPressUp: _stop,
      onLongPressCancel: _stop,
      onTap: _stop,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  bool _hasPin = false;
  bool _autoSave = false;
  bool _aiGuide = false;
  String _aiKey = '';
  final TextEditingController _aiKeyController = TextEditingController();
  bool _aiKeyVisible = false;
  bool _aiTracking = true;
  bool _autoExport = false;
  bool _experimental = false;
  bool _devMode = false;
  bool _perfectionism = false;
  bool _berserk = false;
  bool _taskNotes = false;
  // Плавное «продавливание» карточки BERSERK при зажатии — только визуал,
  // ничего не открывает (режим доступен долгим зажатием «плюса»).
  bool _berserkCardPressed = false;
  bool _permissionWarningDismissed = false;
  bool _grantPressed = false; // Состояние зажатия кнопки «Выдать»
  bool? _notificationsEnabled; // Кэш статуса уведомлений
  // Карусель тем: листается по горизонтали, текущая тема по центру.
  PageController? _themePageCtrl;

  late AnimationController _perfController;
  late Animation<double> _perfScale;
  late Animation<double> _perfFade;
  // Пульсация поля ключа при переключении глазка: текст плавно
  // проявляется/гаснет, а не дёргается мгновенно.
  late final AnimationController _keyPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    _perfController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _perfScale = CurvedAnimation(
      parent: _perfController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    _perfFade = CurvedAnimation(
      parent: _perfController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    // Все асинхронные загрузки — параллельно, но UI перестраивается ОДИН раз
    // в конце. Раньше каждая загрузка дёргала свой setState — вход в
    // настройки «подлагивал» серией мгновенных перестроек.
    _loadInitialState();
    // Слушаем изменения статуса уведомлений
    notificationService.addListener(_onNotificationChanged);
  }

  Future<void> _loadInitialState() async {
    await Future.wait<void>([
      _checkPin(),
      _loadAutoSave(),
      _loadAutoExport(),
      _loadExperimental(),
      _loadDevMode(),
      _loadPerfectionism(),
      _loadBerserk(),
      _loadTaskNotes(),
      _checkPermissionWarning(),
      _checkNotificationsEnabled(),
      _loadAiGuide(),
      _loadAiTracking(),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Сохраняем введённый AI-ключ, даже если пользователь не нажал
    // «готово» на клавиатуре.
    SettingsService.saveAiKey(_aiKey);
    _perfController.dispose();
    _keyPulse.dispose();
    _aiKeyController.dispose();
    _themePageCtrl?.dispose();
    notificationService.removeListener(_onNotificationChanged);
    super.dispose();
  }

  Future<void> _loadAiGuide() async {
    _aiGuide = await SettingsService.loadAiGuide();
    _aiKey = await SettingsService.loadAiKey();
    _aiKeyController.text = _aiKey;
  }

  Future<void> _loadAiTracking() async {
    _aiTracking = await SettingsService.loadAiTracking();
  }

  /// Включает/выключает Ада-трекинг: Ада сама пишет утренний отчёт (08:00)
  /// и вечерний разбор (21:00) прямо в ЧАТ — уведомления не нужны.
  Future<void> _toggleAiTracking(bool v) async {
    await SettingsService.saveAiTracking(v);
    setState(() => _aiTracking = v);
    debugPrint('[ada-tracking] toggle=$v');
    if (v) {
      try {
        final lang = await SettingsService.loadLanguageCode();
        // Если время утреннего/вечернего отчёта уже наступило — пишем
        // в чат сразу же, не дожидаясь следующего дня.
        final delivered = await AiGuideService.maybeDeliverAdaReports(lang);
        if (delivered.isEmpty) {
          showBeautifulSnackBar(
            context,
            message: Translations.t(
              'adaTrackingOn',
              context,
              'Ада теперь сама пишет в чат утром в 08:00 и вечером в 21:00',
            ),
            icon: Icons.auto_awesome,
            iconColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 3),
            groupKey: 'ada_tracking_on',
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _checkNotificationsEnabled() async {
    // Проверяем один раз и кэшируем. БЕЗ setState внутри: вызывается из
    // _loadInitialState (один общий setState в конце) — иначе вход в
    // настройки дёргается повторной перестройкой посреди перехода.
    if (_notificationsEnabled == null) {
      final enabled = await notificationService.areNotificationsEnabled();
      _notificationsEnabled = enabled;
    }
  }

  void _onNotificationChanged() {
    // При изменении состояния уведомлений — сбрасываем кэш, чтобы при следующей проверке было актуальное значение
    if (mounted) {
      _notificationsEnabled = null;
      _checkNotificationsEnabled().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _checkPermissionWarning() async {
    final dismissed =
        globalPrefs.getBool('permission_warning_dismissed') ?? false;
    _permissionWarningDismissed = dismissed;
  }

  void _dismissPermissionWarning() async {
    await globalPrefs.setBool('permission_warning_dismissed', true);
    if (mounted) setState(() => _permissionWarningDismissed = true);
  }

  /// Красивая адаптивная плашка «Разрешения не выданы»: работает и на
  /// светлых, и на тёмных темах (вместо жёстко-красного errorContainer
  /// с белой кнопкой, который на тёмных темах выглядел плохо).
  Widget _buildPermissionWarning(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // На светлых темах — мягкий розово-красный, на тёмных — глубокий
    // винный градиент с хорошим контрастом текста.
    final cardGradient = dark
        ? const [Color(0xFF4A0E1F), Color(0xFF7A1626)]
        : const [Color(0xFFFFE4EA), Color(0xFFFFD6DF)];
    final textColor = dark ? Colors.white : const Color(0xFF8C1D36);
    final subColor = dark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF8C1D36).withValues(alpha: 0.8);
    final iconBg = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.75);
    final btnGradient = dark
        ? const [Color(0xFFFF5C8A), Color(0xFFD81B60)]
        : const [Color(0xFFE91E63), Color(0xFFC2185B)];

    return Card(
      key: const ValueKey('warn_card'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : cs.error.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cardGradient,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
        child: Row(
          children: [
            // Иконка в кружке — не «жёстко красная», а на подложке.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(
                Icons.warning_amber_rounded,
                color: textColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Разрешения не выданы',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Будильники и уведомления не будут работать',
                    style: TextStyle(
                      color: subColor,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Объёмная кнопка «Выдать» — градиент, ripple, плавное нажатие.
            // Material + InkWell дают настоящую «волну» при тапе (белая
            // вспышка расходится от пальца), AnimatedScale — мягкое
            // «продавливание» кнопки, тень-свечение — глубину.
            TweenAnimationBuilder<double>(
              tween: Tween(end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: t, child: child),
              ),
              child: AnimatedScale(
                scale: _grantPressed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: btnGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFD81B60,
                          ).withValues(alpha: _grantPressed ? 0.42 : 0.5),
                          blurRadius: _grantPressed ? 12 : 14,
                          spreadRadius: 1,
                          offset: Offset(0, _grantPressed ? 4 : 5),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      splashColor: Colors.white.withValues(alpha: 0.35),
                      highlightColor: Colors.white.withValues(alpha: 0.12),
                      onTapDown: (_) => setState(() => _grantPressed = true),
                      onTapUp: (_) {
                        setState(() => _grantPressed = false);
                        _grantPermissions();
                      },
                      onTapCancel: () => setState(() => _grantPressed = false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Выдать',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                letterSpacing: 0.4,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _grantPermissions() async {
    // Сначала плавно скрываем карточку (fade 300ms), и только потом
    // запрашиваем разрешения — иначе системный экран уводит приложение
    // в фон и анимация исчезания не видна.
    _dismissPermissionWarning();
    // Сбрасываем кэш статуса, чтобы при следующем открытии настроек проверили заново
    notificationService.resetNotificationStatusCache();
    await Future.delayed(const Duration(milliseconds: 350));
    // Запрашиваем разрешения: системный диалог на уведомления +
    // разрешение на точные будильники.
    await notificationService.requestPermissions();
  }

  Future<void> _loadAutoSave() async {
    final v = await SettingsService.loadAutoSave();
    _autoSave = v;
  }

  Future<void> _loadAutoExport() async {
    final v = await SettingsService.loadAutoExport();
    _autoExport = v;
  }

  Future<void> _loadExperimental() async {
    final v = await SettingsService.loadExperimental();
    _experimental = v;
  }

  Future<void> _loadDevMode() async {
    final v = await SettingsService.loadDevMode();
    _devMode = v;
    // Сразу устанавливаем значение без создания лишних кадров анимации.
    _perfController.value = v ? 1.0 : 0.0;
  }

  Future<void> _loadPerfectionism() async {
    _perfectionism = await SettingsService.loadPerfectionism();
  }

  Future<void> _loadBerserk() async {
    _berserk = await SettingsService.loadBerserk();
  }

  Future<void> _loadTaskNotes() async {
    _taskNotes = await SettingsService.loadTaskNotes();
  }

  Future<void> _checkPin() async {
    final has = await PinService.hasPin();
    if (mounted && has != _hasPin) setState(() => _hasPin = has);
  }

  void _managePin() {
    Navigator.of(context).push(
      slideUpRoute(
        LockScreen(
          isSetting: true,
          onSet: () {
            Navigator.of(context).pop();
            _checkPin();
            KeramikaApp.of(context).lock();
          },
        ),
      ),
    );
  }

  void _removePin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.removePinOf(context)),
        content: Text(Translations.t('areYouSure', context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Translations.cancelOf(context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Translations.deleteOf(context)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // Плавно стираем ПИН: выключаем размытие в «недавних» через несколько
      // миллисекунд, чтобы переключатель задач сразу показывал реальный
      // контент (без замораживания размытого превью), затем сверяем флаг.
      await PinService.removePin();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      setSecureWindow(false);
      _checkPin();
    }
  }

  Future<void> _exportData() async {
    final exportTitle = Translations.t('export', context);
    final exportDoneText = Translations.t('exportDone', context);
    final out = await buildBackupPayload();
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(out));
    systemUiActive = true;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: exportTitle,
      fileName: 'keramika-backup.json',
      bytes: Uint8List.fromList(bytes),
    );
    systemUiActive = false;
    if (path != null && mounted) {
      showBeautifulSnackBar(context, message: exportDoneText);
    }
  }

  Future<void> _mergeJsonListById(String key, String importedRaw) async {
    try {
      final existingRaw = await JsonFile.read(key);
      final existing = _parseJsonList(existingRaw);
      final imported = _parseJsonList(importedRaw);
      final merged = <String, Map<String, dynamic>>{};
      final order = <String>[];
      for (final item in existing) {
        final id = item['id']?.toString();
        if (id != null) {
          merged[id] = item;
          if (!order.contains(id)) order.add(id);
        }
      }
      for (final item in imported) {
        final id = item['id']?.toString();
        if (id != null) {
          merged[id] = item;
          if (!order.contains(id)) order.add(id);
        }
      }
      await JsonFile.write(
        key,
        jsonEncode(order.map((id) => merged[id]).toList()),
      );
    } catch (_) {
      await JsonFile.write(key, importedRaw);
    }
  }

  List<Map<String, dynamic>> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> _mergeStringList(String key, String importedRaw) async {
    try {
      final existingRaw = await JsonFile.read(key);
      List<String> existing = <String>[];
      if (existingRaw != null && existingRaw.isNotEmpty) {
        final decoded = jsonDecode(existingRaw);
        if (decoded is List) {
          existing = decoded.whereType<String>().toList();
        }
      }
      final importedDecoded = jsonDecode(importedRaw);
      List<String> imported = <String>[];
      if (importedDecoded is List) {
        imported = importedDecoded.whereType<String>().toList();
      }
      final seen = <String>{};
      final merged = <String>[];
      for (final item in [...existing, ...imported]) {
        if (seen.add(item)) merged.add(item);
      }
      await JsonFile.write(key, jsonEncode(merged));
    } catch (_) {
      await JsonFile.write(key, importedRaw);
    }
  }

  Future<void> _mergeRealityCheckData(String importedRaw) async {
    try {
      Map<String, dynamic> existing = <String, dynamic>{};
      final existingRaw = await JsonFile.read('reality_check_data');
      if (existingRaw != null && existingRaw.isNotEmpty) {
        final decoded = jsonDecode(existingRaw);
        if (decoded is Map<String, dynamic>) {
          existing = decoded;
        }
      }
      final imported = jsonDecode(importedRaw) as Map<String, dynamic>;
      final merged = <String, dynamic>{...existing, ...imported};
      final existingChecksRaw = existing['checks']?.toString() ?? '';
      final importedChecksRaw = imported['checks']?.toString() ?? '';
      final existingChecks = _parseJsonList(existingChecksRaw);
      final importedChecks = _parseJsonList(importedChecksRaw);
      final mergedChecks = <String, Map<String, dynamic>>{};
      final order = <String>[];
      for (final item in [...existingChecks, ...importedChecks]) {
        final id = item['id']?.toString();
        if (id != null) {
          mergedChecks[id] = item;
          if (!order.contains(id)) order.add(id);
        }
      }
      merged['checks'] = jsonEncode(
        order.map((id) => mergedChecks[id]).toList(),
      );
      await JsonFile.write('reality_check_data', jsonEncode(merged));
    } catch (_) {
      await JsonFile.write('reality_check_data', importedRaw);
    }
  }

  Future<void> _importData() async {
    systemUiActive = true;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    systemUiActive = false;
    if (result == null || result.files.single.path == null || !mounted) return;
    if (!result.files.single.name.toLowerCase().endsWith('.json')) {
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t(
            'importWrongFile',
            context,
            'Please select a .json file',
          ),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
      return;
    }
    try {
      final content = await File(result.files.single.path!).readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final serviceKeys = <String>{
        'habits',
        'tasks',
        'task_categories',
        'alarms',
        'app_timers',
        'reality_check_data',
        'nutrition_meals',
        'ai_chat_history',
      };
      final listServiceKeys = <String>{
        'habits',
        'tasks',
        'alarms',
        'app_timers',
        'nutrition_meals',
      };
      final settingsKeys = <String>{
        'setting_theme',
        'setting_locale',
        'setting_peach_dark',
        'setting_experimental',
        'setting_auto_save',
        'setting_dev_mode',
        'setting_auto_export',
        'setting_ai_guide',
        'setting_ai_key',
      };
      for (final entry in decoded.entries) {
        if (entry.value == null) continue;
        final key = entry.key;
        final v = entry.value;
        if (serviceKeys.contains(key) && v is String) {
          if (listServiceKeys.contains(key)) {
            await _mergeJsonListById(key, v);
          } else if (key == 'task_categories') {
            await _mergeStringList(key, v);
          } else if (key == 'reality_check_data') {
            await _mergeRealityCheckData(v);
          } else {
            await JsonFile.write(key, v);
          }
        } else if (settingsKeys.contains(key)) {
          final settingsRaw = await JsonFile.read('app_settings');
          final settings = settingsRaw != null
              ? Map<String, dynamic>.from(jsonDecode(settingsRaw))
              : <String, dynamic>{};
          settings[key] = v;
          await JsonFile.write('app_settings', jsonEncode(settings));
        } else if (key == 'app_pin' && v is String) {
          await PinService.setPin(v);
        } else {
          if (v is String) {
            globalPrefs.setString(key, v);
          } else if (v is bool) {
            globalPrefs.setBool(key, v);
          } else if (v is int) {
            globalPrefs.setInt(key, v);
          } else if (v is double) {
            globalPrefs.setDouble(key, v);
          } else if (v is List) {
            globalPrefs.setStringList(key, v.cast<String>());
          }
        }
      }
      await HabitService().load();
      await TaskService().load();
      await AlarmService().load();
      await RealityCheckService().load();
      await TimerService().load();
      await NutritionService().load();
      await rescheduleAllNotifications();
      if (await SettingsService.loadAutoSave()) {
        stopAutoSave();
        startAutoSave();
      } else {
        stopAutoSave();
      }
      if (await SettingsService.loadAutoExport()) {
        stopAutoExport();
        startAutoExport();
      } else {
        stopAutoExport();
      }
      // refreshApp() пересоздаёт всё дерево (новый UniqueKey) и уходит на
      // сплэш — контекст настроек после этого мёртв, а OverlayEntry снекбара
      // был бы уничтожен вместе со старым деревом ДО появления. Поэтому
      // снекбар «Настройки импортированы» показываем через корневой
      // navigatorKey уже ПОСЛЕ пересоздания — он плавно выезжает и плавно
      // уходит на новом дереве.
      await KeramikaApp.of(context).refreshApp();
      final rootCtx = navigatorKey.currentContext;
      if (rootCtx != null && rootCtx.mounted) {
        // Небольшая пауза: новый Overlay успевает построиться после
        // пересоздания дерева, и снекбар появляется на нём плавно.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (rootCtx.mounted) {
          showBeautifulSnackBar(
            rootCtx,
            message: Translations.t('importDone', rootCtx),
          );
        }
      }
    } catch (_) {
      final ctx = navigatorKey.currentContext ?? context;
      if (ctx.mounted) {
        showBeautifulSnackBar(
          ctx,
          message: Translations.t('importError', ctx),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
    }
  }

  /// Красивая горизонтальная карусель тем: текущая тема по центру,
  /// соседние видны по краям (viewportFraction 0.55). Листается плавно,
  /// при остановке на новой странице тема переключается штатной
  /// анимацией MaterialApp — без вспышек и размытий.
  Widget _buildThemeCarousel(BuildContext context) {
    final appState = KeramikaApp.of(context);
    final entries = <_ThemeEntry>[
      // MUTILATED — САМАЯ ПЕРВАЯ тема, не переводится.
      const _ThemeEntry(
        'mutilated',
        'MUTILATED',
        Icons.bloodtype_outlined,
        specialMutilated: true,
      ),
      _ThemeEntry('light', Translations.lightOf(context), Icons.light_mode),
      _ThemeEntry('dark', Translations.darkOf(context), Icons.dark_mode),
      _ThemeEntry(
        'system',
        Translations.systemOf(context),
        Icons.brightness_auto,
      ),
      _ThemeEntry(
        'systemLight',
        Translations.t('themeSystemLight', context),
        Icons.palette_outlined,
      ),
      _ThemeEntry('rose', Translations.roseOf(context), Icons.favorite_outline),
      _ThemeEntry(
        'peach',
        Translations.peachOf(context),
        Icons.local_florist_outlined,
      ),
      const _ThemeEntry('grok', 'Grok', Icons.auto_awesome),
      const _ThemeEntry('darkGrok', 'Grok Dark', Icons.dark_mode),
    ];
    final currentIndex = entries.indexWhere((e) => e.key == appState.themeKey);
    _themePageCtrl ??= PageController(
      viewportFraction: 0.55,
      initialPage: currentIndex < 0 ? 0 : currentIndex,
    );
    return SizedBox(
      height: 124,
      child: PageView.builder(
        controller: _themePageCtrl,
        itemCount: entries.length,
        onPageChanged: (i) {
          final key = entries[i].key;
          if (key != appState.themeKey) appState.setThemeMode(key);
        },
        itemBuilder: (context, i) {
          final e = entries[i];
          return Center(
            child: _themePill(
              context,
              e.key,
              e.label,
              e.icon,
              specialMutilated: e.specialMutilated,
              // Тап по соседней теме прокручивает карусель к ней.
              extraOnSelected: () {
                final ctrl = _themePageCtrl;
                if (ctrl != null && ctrl.hasClients && ctrl.page != i) {
                  ctrl.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _themePill(
    BuildContext context,
    String key,
    String label,
    IconData icon, {
    bool specialMutilated = false,
    VoidCallback? extraOnSelected,
  }) {
    final appState = KeramikaApp.of(context);
    final isSelected = appState.themeKey == key;
    final theme = Theme.of(context);
    // Для MUTILATED — зажатие 10 секунд показывает плашную «Вы элегант?»
    // с переводами. Плавно появляется, держится 3 секунды, плавно уходит.
    final chip = ChoiceChip(
      // Крупные названия: в карусели у каждой темы много места, длинные
      // имена (MUTILATED, System Light) аккуратно масштабируются вниз,
      // короткие — полного размера.
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          // Жирнее (w700): названия читаются одинаково плотно и по-русски,
          // и по-английски (латиница в w600 выглядела тоньше кириллицы).
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      // Галочка выбранной темы появляется плавно: AnimatedSwitcher плавно
      // подменяет иконку на check (scale + fade), а не прыгает мгновенно.
      avatar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          isSelected ? Icons.check_circle : icon,
          key: ValueKey('pill_${key}_$isSelected'),
          size: 14,
        ),
      ),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (selected) {
        // Приятный «клик» при смене темы.
        Haptics.select();
        if (key == 'peach' && appState.themeKey == 'peach') {
          appState.togglePeachDark();
        } else {
          appState.setThemeMode(key);
        }
        extraOnSelected?.call();
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        // Тонкая аккуратная обводка: у выбранной — первичный цвет (1px),
        // у остальных — прозрачная. Никакого «утолщения» при переключении.
        side: BorderSide(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          width: 1,
        ),
      ),
    ); // Центрируем в ячейке сетки 3×3 — ровная и красивая сетка тем.
    if (!specialMutilated) return Center(child: chip);
    return Center(
      child: _LongPressChip(
        duration: const Duration(seconds: 10),
        onLongPress: () {
          // Плавный красивый snackbar с эмодзи — выезжает снизу с пружинкой,
          // держится 3 секунды и плавно уезжает.
          showBeautifulSnackBar(
            context,
            message:
                'Вы элегантны? 🥀 — Are you elegant? — Êtes-vous élégant·e ?',
            icon: Icons.diamond_outlined,
            iconColor: const Color(0xFFFFD166),
            duration: const Duration(seconds: 3),
          );
        },
        child: chip,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = KeramikaApp.of(context);
    final theme = Theme.of(context);
    // Список собирается заранее, но рендерится ЛЕНИВО (ListView.builder):
    // экран настроек открывается без подлагивания — за кадром строятся
    // только видимые карточки, а не все сразу.
    final settingsItems = <Widget>[
      // === Beautiful whole-section toggle for Reality Checks, top of Settings.
      // Adds or removes the 'РП' tab in Home, schedule, and notifications.
      const _RealityCheckToggleCard(),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Translations.themeOf(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              _buildThemeCarousel(context),
              // Значок Flutter ПОД каруселью тем, внутри той же карточки:
              // аккуратный фирменный акцент внизу секции.
              const SizedBox(height: 14),
              const Center(child: _FlutterBadge()),
            ],
          ),
        ),
      ),

      // Проверяем статус уведомлений — если false и предупреждение не скрыто, показываем карточку.
      // На web статус уведомлений не определить (всегда true), поэтому карточку
      // показываем тоже — иначе «Сбросить предупреждения» не даёт видимого результата.
      if (kIsWeb ||
          _notificationsEnabled == false ||
          _notificationsEnabled == null)
        // AnimatedSize + AnimatedSwitcher: карточка плавно исчезает
        // (fade + сворачивание высоты) при нажатии «Выдать».
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: _permissionWarningDismissed
                ? const SizedBox.shrink(key: ValueKey('warn_hidden'))
                : _buildPermissionWarning(context),
          ),
        ),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Translations.languageOf(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: appState.languageCode,
                isExpanded: true,
                borderRadius: BorderRadius.circular(12),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.language),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(Translations.followSystemOf(context)),
                  ),
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(Translations.englishOf(context)),
                  ),
                  DropdownMenuItem(
                    value: 'ru',
                    child: Text(Translations.russianOf(context)),
                  ),
                  DropdownMenuItem(
                    value: 'fr',
                    child: Text(Translations.frenchOf(context)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) appState.setLanguageCode(v);
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Translations.aboutOf(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              // «Keramika FOSS» — приписку FOSS выделяем розовым,
              // как она была на сплэше.
              Text.rich(
                TextSpan(
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                  children: [
                    const TextSpan(text: 'Keramika '),
                    const TextSpan(
                      text: 'FOSS',
                      style: TextStyle(
                        color: Color(0xFFF06292),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                // В «О приложении» — именно «1.3-release», как просил.
                'v$appVersion-release',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _openChangelog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          Translations.t('patchNotes', context),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _openGitHub(),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.code,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GitHub',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _openLink('https://gitlab.com/wxstdo/keramika'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GitLab',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Recommended',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Translations.t('aboutAuthorTitle', context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _CtaButton(
                label: Translations.t('visitellaName', context, 'Visitella'),
                icon: Icons.rocket_launch_outlined,
                // Оригинальный вид Visitella: тёмный градиент + чёрное свечение.
                gradient: const [
                  Color(0xFF4A4D54),
                  Color(0xFF232428),
                  Color(0xFF101013),
                ],
                glow: Colors.black,
                onTap: () => _openLink('https://mutilated.pages.dev/#top'),
              ),
              const SizedBox(height: 8),
              Text(
                Translations.t(
                  'visitellaDesc',
                  context,
                  'Projects, games, news',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.volunteer_activism_outlined,
                    color: Color(0xFFE91E63),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      Translations.t(
                        'supportAuthorTitle',
                        context,
                        'Support the author',
                      ),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                Translations.t(
                  'supportAuthorBody',
                  context,
                  'If this app helps you, you can thank the developer with a small donation.',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              // Кнопка «Поддержать»: открывает снизу окно с выбором способа
              // оплаты — CloudTips, Boosty (и др.). Внутри окна — крупные
              // градиентные кнопки, каждая открывает свою страницу.
              _CtaButton(
                label: Translations.t('support', context, 'Support'),
                icon: Icons.favorite,
                // Оригинальный вид: розовый градиент + розовое свечение.
                gradient: const [
                  Color(0xFFFF8FB3),
                  Color(0xFFFF4D7E),
                  Color(0xFFE91E63),
                ],
                glow: const Color(0xFFE91E63),
                onTap: _showSupportSheet,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Translations.pinLockOf(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Заголовок «Установить / Сменить ПИН» плавно
                        // меняется, а не дёргается при переключении.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SizeTransition(sizeFactor: anim),
                          ),
                          child: Text(
                            _hasPin
                                ? Translations.changePinOf(context)
                                : Translations.setPinOf(context),
                            key: ValueKey('pin_title_$_hasPin'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Translations.pinDescriptionOf(context),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Замок плавно переключается между lock/lock_open
                  // (fade + лёгкий поворот), а не дёргается мгновенно.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: RotationTransition(
                        turns: Tween<double>(
                          begin: -0.12,
                          end: 0,
                        ).animate(anim),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.85,
                            end: 1,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                    ),
                    child: IconButton(
                      key: ValueKey('pin_lock_$_hasPin'),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_hasPin ? Icons.lock : Icons.lock_open),
                      onPressed: _managePin,
                    ),
                  ),
                  // Кнопка «удалить ПИН» появляется/исчезает плавно, а место
                  // под неё зарезервировано всегда (48px) — ряд не «прыгает»
                  // влево-вправо при переключении.
                  SizedBox(
                    width: 48,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                      child: _hasPin
                          ? IconButton(
                              key: const ValueKey('pin_delete_btn'),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: _removePin,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('pin_delete_placeholder'),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      ListenableBuilder(
        listenable: notificationService,
        builder: (context, _) {
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translations.notificationsOf(context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Translations.notificationsDescOf(context)),
                    leading: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.85,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        notificationService.enabled
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        key: ValueKey(
                          'notif_icon_${notificationService.enabled}',
                        ),
                        color: notificationService.enabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () async {
                      final newVal = !notificationService.enabled;
                      await notificationService.setEnabled(newVal);
                      if (newVal) {
                        // Включили уведомления — реально перепланируем
                        // будильники и проверки реальности, иначе
                        // переключатель только ставил флаг.
                        await rescheduleAllNotifications();
                      }
                    },
                    trailing: VolumetricSwitch(
                      value: notificationService.enabled,
                      onChanged: (v) async {
                        await notificationService.setEnabled(v);
                        if (v) {
                          // Включили уведомления — реально перепланируем
                          // будильники и проверки реальности, иначе
                          // переключатель только ставил флаг.
                          await rescheduleAllNotifications();
                        }
                      },
                      activeColor: theme.colorScheme.primary,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Translations.fullscreenNotifDescOf(context)),
                    leading: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.85,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        notificationService.fullscreen
                            ? Icons.fullscreen
                            : Icons.fullscreen_exit,
                        key: ValueKey(
                          'fullscreen_icon_${notificationService.fullscreen}',
                        ),
                        color: notificationService.fullscreen
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () => notificationService.setFullscreen(
                      !notificationService.fullscreen,
                    ),
                    trailing: VolumetricSwitch(
                      value: notificationService.fullscreen,
                      onChanged: (v) => notificationService.setFullscreen(v),
                      activeColor: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Translations.batteryOptimizationOf(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.battery_saver, color: Colors.green),
                title: Text(Translations.batteryOptDescOf(context)),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () async {
                  final ctx = context;
                  final batteryText = Translations.batteryOpenedOf(ctx);
                  final cantOpenText = Translations.t('settingsCantOpen', ctx);
                  final opened = await openAppSettingsAndroid();
                  if (opened) {
                    showBeautifulSnackBar(ctx, message: batteryText);
                  } else {
                    showBeautifulSnackBar(
                      ctx,
                      message: cantOpenText,
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.power_settings_new,
                  color: Colors.orange,
                ),
                title: Text(Translations.t('autostart', context)),
                subtitle: Text(
                  Translations.t('autostartDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () async {
                  final ctx = context;
                  final text = Translations.t('settingsCantOpen', ctx);
                  final opened = await openAutostartSettings();
                  if (!opened && mounted) {
                    showBeautifulSnackBar(
                      ctx,
                      message: text,
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.notifications_active,
                  color: Colors.red,
                ),
                title: Text(Translations.t('fullScreenNotifTitle', context)),
                subtitle: Text(
                  Translations.t('fullScreenNotifBody', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () async {
                  final ctx = context;
                  final text = Translations.t('settingsCantOpen', ctx);
                  final opened = await openFullScreenNotifSettings();
                  if (!opened && mounted) {
                    showBeautifulSnackBar(
                      ctx,
                      message: text,
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(Translations.t('resetWarnings', context)),
            trailing: const Icon(Icons.restart_alt_outlined, size: 20),
            onTap: () async {
              await globalPrefs.setBool('welcome_dismissed', false);
              await globalPrefs.setBool('popup_warning_shown', false);
              await globalPrefs.setBool('permission_warning_dismissed', false);
              if (mounted) {
                showBeautifulSnackBar(
                  context,
                  message: Translations.t('warningsResetDone', context),
                );
              }
              if (mounted) {
                KeramikaApp.of(context).refreshApp();
              }
            },
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              // «Экспериментальное» — показ/скрытие секции таймеров на экране
              // будильников. Только видимость: таймеры при выключении НЕ
              // удаляются, они остаются в хранилище.
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: TweenAnimationBuilder<Color?>(
                  // Цвет значка секции таймера меняется ПЛАВНО при
                  // включении/выключении (300 мс), а не мигает резко.
                  tween: ColorTween(
                    end: _experimental
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) =>
                      Icon(Icons.science_outlined, color: color),
                ),
                title: Text(Translations.t('experimentalSettings', context)),
                subtitle: Text(
                  Translations.t('experimentalDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_experimental;
                  await SettingsService.saveExperimental(newVal);
                  setState(() => _experimental = newVal);
                },
                trailing: VolumetricSwitch(
                  value: _experimental,
                  onChanged: (v) async {
                    await SettingsService.saveExperimental(v);
                    setState(() => _experimental = v);
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.save_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('autoSave', context)),
                subtitle: Text(
                  Translations.t('autoSaveDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_autoSave;
                  await SettingsService.saveAutoSave(newVal);
                  setState(() => _autoSave = newVal);
                  if (newVal) {
                    startAutoSave();
                  } else {
                    stopAutoSave();
                  }
                },
                trailing: VolumetricSwitch(
                  value: _autoSave,
                  onChanged: (v) async {
                    await SettingsService.saveAutoSave(v);
                    setState(() => _autoSave = v);
                    if (v) {
                      startAutoSave();
                    } else {
                      stopAutoSave();
                    }
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('clearCache', context)),
                subtitle: Text(
                  Translations.t('clearCacheDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _clearCache,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      // === Искусственный проводник: мини-чат с ИИ у кнопки «+». ===
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFF8FB3), Color(0xFFE91E63)],
                      ),
                    ),
                    child: const Icon(
                      Icons.explore,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    Translations.t('aiGuide', context, 'AI guide'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  Translations.t('aiGuideToggle', context, 'Enable AI guide'),
                ),
                subtitle: Text(
                  Translations.t(
                    'aiGuideDesc',
                    context,
                    'A small circle appears next to the “+” button and opens a mini chat.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_aiGuide;
                  await SettingsService.saveAiGuide(newVal);
                  setState(() => _aiGuide = newVal);
                },
                trailing: VolumetricSwitch(
                  value: _aiGuide,
                  onChanged: (v) async {
                    await SettingsService.saveAiGuide(v);
                    setState(() => _aiGuide = v);
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
              // Поле ключа появляется/исчезает плавно (SizeTransition + fade).
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (child, animation) => SizeTransition(
                  sizeFactor: animation,
                  alignment: AlignmentDirectional.topStart,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _aiGuide
                    ? Padding(
                        key: const ValueKey('ai_key_fields'),
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            Text(
                              Translations.t(
                                'aiGuideKey',
                                context,
                                'Poolside key (optional)',
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Поле обёрнуто в FadeTransition: при переключении
                            // глазка текст плавно «переливается» (пульсация),
                            // не теряя фокус и не пересоздавая поле.
                            FadeTransition(
                              opacity: Tween<double>(begin: 0.35, end: 1.0)
                                  .animate(
                                    CurvedAnimation(
                                      parent: _keyPulse,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                              child: TextField(
                                magnifierConfiguration:
                                    TextMagnifierConfiguration.disabled,
                                controller: _aiKeyController,
                                contextMenuBuilder: minimalContextMenuBuilder,
                                obscureText: !_aiKeyVisible,
                                textInputAction: TextInputAction.done,
                                maxLength: 500,
                                maxLines: 1,
                                decoration: InputDecoration(
                                  isDense: true,
                                  counterText: '',
                                  hintText: Translations.t(
                                    'aiGuideKeyHint',
                                    context,
                                    'Paste your Laguna API key',
                                  ),
                                  suffixIcon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          ),
                                        ),
                                    child: IconButton(
                                      key: ValueKey(
                                        'ai_key_eye_$_aiKeyVisible',
                                      ),
                                      icon: Icon(
                                        _aiKeyVisible
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _aiKeyVisible = !_aiKeyVisible,
                                        );
                                        // Мягкий «перелив» текста ключа.
                                        _keyPulse.forward(from: 0);
                                      },
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onChanged: (v) => _aiKey = v,
                                onSubmitted: (v) =>
                                    SettingsService.saveAiKey(v),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Описание Ады: одна фраза про бесплатные модели.
                            Builder(
                              builder: (context) {
                                final note = Translations.t(
                                  'aiGuideKeyNote',
                                  context,
                                  'Ада использует встроенные бесплатные модели (100 сообщений на ADA, остальное — FreeLLMPool).',
                                );
                                return Text(
                                  note,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 20),
                            // Ада-трекинг: утренний отчёт + вечерний разбор.
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: const Icon(
                                Icons.wb_sunny_outlined,
                                color: Color(0xFFE89B3C),
                              ),
                              title: Text(
                                Translations.t(
                                  'adaTracking',
                                  context,
                                  'Ada tracking',
                                ),
                              ),
                              subtitle: Text(
                                Translations.t(
                                  'adaTrackingDesc',
                                  context,
                                  'Morning report “what is planned today” at 08:00 and evening review at 21:00 as notifications.',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              onTap: () => _toggleAiTracking(!_aiTracking),
                              trailing: VolumetricSwitch(
                                value: _aiTracking,
                                onChanged: _toggleAiTracking,
                                activeColor: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('ai_key_hidden')),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bug_report_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Translations.diagnosticsOf(context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _diagTile(
                context,
                icon: Icons.alarm_outlined,
                label: Translations.t('diagAlarmTest', context),
                onTap: () => _runAlarmDiag(),
              ),
              _diagTile(
                context,
                icon: Icons.psychology_outlined,
                label: Translations.t('diagRcTest', context),
                onTap: () => _runRcDiag(),
              ),
              _diagTile(
                context,
                icon: Icons.volume_up_outlined,
                label: Translations.t('diagSoundTest', context),
                onTap: () async {
                  final played = Translations.t('diagSoundPlayed', context);
                  final player = AudioPlayer();
                  try {
                    await player.play(AssetSource('sounds/default.wav'));
                    await Future.delayed(const Duration(milliseconds: 1500));
                    await player.stop();
                  } catch (_) {}
                  if (!mounted) return;
                  player.dispose();
                  showBeautifulSnackBar(context, message: played);
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizeTransition(
        sizeFactor: _perfScale,
        axis: Axis.vertical,
        child: FadeTransition(
          opacity: _perfFade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Card(
                  color: _devMode
                      ? theme.colorScheme.surfaceContainerLow
                      : Colors.transparent,
                  elevation: _devMode ? 4 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFFB39DDB),
                        size: 28,
                      ),
                      title: Text(
                        Translations.t('perfectionism', context),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFB39DDB),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        Translations.t('perfectionismHint', context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () async {
                        final newVal = !_perfectionism;
                        await SettingsService.savePerfectionism(newVal);
                        setState(() => _perfectionism = newVal);
                      },
                      trailing: SmoothCircleToggle(
                        value: _perfectionism,
                        onChanged: (v) async {
                          await SettingsService.savePerfectionism(v);
                          setState(() => _perfectionism = v);
                        },
                        activeColor: const Color(0xFFB39DDB),
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildTaskNotesCard(context, theme),
              const SizedBox(height: 8),
              _buildBerserkCard(context, theme),
            ],
          ),
        ),
      ),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.backup_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Translations.t('data', context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.schedule_outlined,
                  color: _autoExport
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                title: Text(Translations.t('autoExport', context)),
                subtitle: Text(
                  Translations.t('autoExportHourly', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_autoExport;
                  await SettingsService.saveAutoExport(newVal);
                  setState(() => _autoExport = newVal);
                  if (newVal) {
                    startAutoExport(runImmediately: true);
                  } else {
                    stopAutoExport();
                  }
                },
                trailing: VolumetricSwitch(
                  value: _autoExport,
                  onChanged: (v) async {
                    await SettingsService.saveAutoExport(v);
                    setState(() => _autoExport = v);
                    if (v) {
                      startAutoExport(runImmediately: true);
                    } else {
                      stopAutoExport();
                    }
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _exportData,
                      icon: const Icon(Icons.upload_outlined, size: 18),
                      label: Text(Translations.t('export', context)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _importData,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(Translations.t('import', context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                Translations.t('license', context),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _showDevModeDialog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Keramika',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          Translations.settingsOf(context),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent, // Make AppBar transparent
        elevation: 0, // Remove shadow
      ),
      resizeToAvoidBottomInset: false,
      body: SmoothKeyboardBody(
        child: ListView.builder(
          // Каскадное появление карточек: каждая мягко всплывает (fade + подъём)
          // через index * 40мс, а не вся страница разом. Ленивый билдер +
          // лёгкие Transform/Opacity — не грузит слабые устройства.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: settingsItems.length,
          itemBuilder: (context, index) => StaggerIn(
            index: index,
            step: const Duration(milliseconds: 40),
            child: settingsItems[index],
          ),
        ),
      ),
    );
  }

  /// Кровавая карточка BERSERK — как «Борьба с перфекционизмом»:
  /// тот же ListTile с переключателем, без открытия по тапу (режим
  /// открывается ТОЛЬКО долгим зажатием «плюса» на главном экране).
  /// Фон — тёмно-красный градиент с едва заметными кровавыми пятнами,
  /// переключатель красный, иконка — топор.
  Widget _buildBerserkCard(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final blood = Color.lerp(cs.primary, const Color(0xFFB51F32), 0.72)!;
    final themedDark = Color.lerp(
      cs.surfaceContainerLow,
      const Color(0xFF26070C),
      0.72,
    )!;
    return Listener(
      // Только визуальный отклик: при зажатии карточка очень плавно
      // «продавливается» (масштаб 0.97), при отпускании — так же плавно
      // возвращается. Ничего не открывает.
      onPointerDown: (_) => setState(() => _berserkCardPressed = true),
      onPointerUp: (_) => setState(() => _berserkCardPressed = false),
      onPointerCancel: (_) => setState(() => _berserkCardPressed = false),
      child: AnimatedScale(
        // Очень мягкое нажатие: 0.97 с долгой плавной кривой (280 мс)
        // в обе стороны — без рывков и резких «отщёлкиваний».
        scale: _berserkCardPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: Card(
          elevation: 0,
          // ПРОЗРАЧНЫЙ фон Card: иначе непрозрачный surfaceContainerLow
          // (из карт-темы) заливал карточку ПОВЕРХ полупрозрачного
          // градиента — Берсерк выглядел сплошным, а не полупрозрачным.
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          // БЕЗ fit: StackFit.expand — в ListView вертикаль unbounded,
          // expand-стек падал layout'ом и всё, что ниже «Борьбы с
          // перфекционизмом» (Берсерк, Данные/Экспорт), исчезало.
          child: Stack(
            children: [
              // Полупрозрачный кровавый градиент (alpha 0.42): сквозь него
              // просвечивает фон настроек. BackdropFilter убран — на слабом
              // GPU blur заливал карточку белым и «съедал» половину контента.
              DecoratedBox(
                decoration: BoxDecoration(
                  // Тот же радиус, что у Card: иначе прямоугольная рамка
                  // DecoratedBox вылезала за скруглённые углы карточки
                  // (на тёмной теме «резаные» края обводки).
                  borderRadius: BorderRadius.circular(20),
                  // Полупрозрачный градиент (alpha 0.42) + белый блик сверху —
                  // вид «матового стекла» без blur.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      themedDark.withValues(alpha: 0.42),
                      Color.lerp(
                        blood,
                        const Color(0xFF4A0A12),
                        0.55,
                      )!.withValues(alpha: 0.42),
                      Color.lerp(
                        blood,
                        const Color(0xFF8E1422),
                        0.25,
                      )!.withValues(alpha: 0.42),
                      blood.withValues(alpha: 0.42),
                    ],
                    stops: const [0.0, 0.45, 0.75, 1.0],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFF6A7A).withValues(alpha: 0.85),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFB51F32).withValues(alpha: 0.5),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: const Color(0xFFFF5265).withValues(alpha: 0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Кровавые пятна — статичный, дешёвый слой (без анимации).
                    Positioned.fill(
                      child: CustomPaint(painter: const _BloodStainsPainter()),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF8E1422), Color(0xFF3A0810)],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFFFF8290,
                              ).withValues(alpha: 0.9),
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFF5265,
                                ).withValues(alpha: 0.55),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Center(
                            // Топор — символ BERSERK.
                            child: Text('🪓', style: TextStyle(fontSize: 26)),
                          ),
                        ),
                        title: Text(
                          Translations.t('berserkCardTitle', context),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.55,
                            height: 1.2,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                              Shadow(
                                color: Color(0xFFFF5265),
                                blurRadius: 12,
                                offset: Offset(0, 0),
                              ),
                            ],
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            Translations.t('berserkCardSubtitle', context),
                            style: const TextStyle(
                              color: Color(0xFFFDEDEE),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                            ),
                          ),
                        ),
                        trailing: VolumetricSwitch(
                          value: _berserk,
                          onChanged: (value) async {
                            await SettingsService.saveBerserk(value);
                            if (mounted) setState(() => _berserk = value);
                          },
                          activeColor: const Color(0xFFFF5265),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Стеклянный блик сверху — ощущение полупрозрачности.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.38],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// «Вспомнил, что использую…» — тёплая карточка-воспоминание в разделе
  /// разработчика. Включает быстрое меню: долгое зажатие задачи (5 сек)
  /// открывает красивое окно заметки до 150 символов, заметка сохраняется.
  Widget _buildTaskNotesCard(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final lavender = Color.lerp(cs.primary, const Color(0xFF9C6ADE), 0.5)!;
    final peach = Color.lerp(cs.primary, const Color(0xFFFFB08A), 0.42)!;
    final base = Color.lerp(
      cs.surfaceContainerLow,
      const Color(0xFF2A2140),
      0.55,
    )!;
    return Card(
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base.withValues(alpha: 0.55),
                  Color.lerp(base, lavender, 0.38)!.withValues(alpha: 0.55),
                  Color.lerp(base, peach, 0.30)!.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              border: Border.all(
                color: Color.lerp(
                  lavender,
                  Colors.white,
                  0.45,
                )!.withValues(alpha: 0.6),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: lavender.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: peach.withValues(alpha: 0.16),
                  blurRadius: 40,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(peach, Colors.white, 0.12)!,
                        Color.lerp(lavender, const Color(0xFF4A3A7A), 0.35)!,
                      ],
                    ),
                    border: Border.all(
                      color: Color.lerp(
                        peach,
                        Colors.white,
                        0.6,
                      )!.withValues(alpha: 0.85),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: lavender.withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lightbulb_outline_rounded,
                      color: Color(0xFFFFF3E0),
                      size: 26,
                    ),
                  ),
                ),
                title: Text(
                  Translations.t('taskNotesTitle', context),
                  style: const TextStyle(
                    color: Color(0xFFFFF8EE),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    height: 1.25,
                    shadows: [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    Translations.t('taskNotesSubtitle', context),
                    style: const TextStyle(
                      color: Color(0xFFEDE4F5),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                trailing: SmoothCircleToggle(
                  value: _taskNotes,
                  onChanged: (value) async {
                    await SettingsService.saveTaskNotes(value);
                    if (mounted) setState(() => _taskNotes = value);
                  },
                  activeColor: lavender,
                  size: 32,
                ),
              ),
            ),
          ),
          // Тёплый блик сверху — ощущение полупрозрачного стекла.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.35],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDevModeDialog() {
    if (_devMode) {
      _perfController.reverse().then((_) {
        if (mounted) {
          setState(() => _devMode = false);
          SettingsService.saveDevMode(false);
        }
      });
      return;
    }
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(Translations.t('devMode', context)),
        content: TextField(
          magnifierConfiguration: TextMagnifierConfiguration.disabled,
          controller: ctrl,
          contextMenuBuilder: minimalContextMenuBuilder,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 50,
          buildCounter: smoothCharCounterBuilder,
          decoration: InputDecoration(
            hintText: '7720',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.cancelOf(context)),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text == '7720') {
                Navigator.pop(ctx);
                // Плавное появление раздела разработчика: ждём окончания
                // анимации закрытия диалога, иначе карточки выезжают под
                // ещё видимым фоном диалога и кажется, что «дёрнулось».
                Future.delayed(const Duration(milliseconds: 140), () {
                  if (!mounted) return;
                  setState(() => _devMode = true);
                  SettingsService.saveDevMode(true);
                  _perfController.forward();
                });
              } else {
                Navigator.pop(ctx);
              }
            },
            child: Text(Translations.okOf(context)),
          ),
        ],
      ),
    );
  }

  Widget _diagTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: const Icon(Icons.play_arrow_outlined, size: 20),
      dense: true,
      onTap: onTap,
    );
  }

  Future<void> _runDiag(int id, String title, String body) async {
    if (!notificationService.enabled) {
      final ctx = context;
      showBeautifulSnackBar(
        ctx,
        message: Translations.t('diagNotEnabled', ctx),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    try {
      final ec = Translations.t('diagEnableNotif', context);
      final cc = Translations.t('settingsCantOpen', context);
      final sc = Translations.t('diagSent', context);
      final permitted = await notificationService.areNotificationsEnabled();
      if (!permitted) {
        final opened = await openNotificationSettingsAndroid();
        if (!mounted) return;
        showBeautifulSnackBar(
          context,
          message: opened ? ec : cc,
          icon: Icons.error_outline,
          iconColor: Colors.red,
          duration: const Duration(seconds: 4),
        );
        return;
      }
      await notificationService.showInstant(id, title, body);
      if (!mounted) return;
      showBeautifulSnackBar(context, message: sc);
    } catch (e) {
      if (!mounted) return;
      showBeautifulSnackBar(
        context,
        message: '${Translations.t('diagError', context)}: $e',
        icon: Icons.error_outline,
        iconColor: Colors.red,
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _runRcDiag() async {
    final svc = RealityCheckService();
    final rcText = Translations.realityChecksOf(context);
    await svc.load();
    final question = svc.checks.isNotEmpty
        ? svc.checks.first.question
        : 'Is this a dream?';
    await _runDiag(99998, rcText, question);
  }

  Future<void> _runAlarmDiag() async {
    final svc = AlarmService();
    final alarmsText = Translations.alarmsOf(context);
    svc.load();
    final alarm = svc.alarms.isNotEmpty ? svc.alarms.first : null;
    final body = alarm != null
        ? (alarm.label.isNotEmpty
              ? alarm.label
              : '${alarm.time.hour.toString().padLeft(2, '0')}:${alarm.time.minute.toString().padLeft(2, '0')}')
        : 'Alarm test';
    await _runDiag(99999, alarmsText, body);
  }

  String get _supportAuthorUrl =>
      globalPrefs.getString('support_author_url') ??
      'https://pay.cloudtips.ru/p/da0c7421';

  String get _boostyUrl =>
      globalPrefs.getString('boosty_url') ?? 'https://boosty.to/larafut';

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Окно снизу с выбором способа поддержки: крупные градиентные кнопки
  /// CloudTips и Boosty, каждая открывает свою страницу оплаты. Оформление
  /// строится на цветах ТЕКУЩЕЙ темы — тёмные/светлые темы окно
  /// подхватывает само.
  void _showSupportSheet() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: false,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ручка-индикатор сверху.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    // Иконка-«сердце» в мягком градиентном кружке в цвете
                    // темы (primary вместо розового).
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.22),
                            accent.withValues(alpha: 0.10),
                          ],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(Icons.favorite, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Translations.t('support', context, 'Support'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                    // Крестик — закрыть окно.
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: cs.onSurfaceVariant,
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  Translations.t(
                    'supportAuthorBody',
                    context,
                    'If this app helps you, you can thank the developer with a small donation.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // Способы оплаты — большие кнопки-«таблетки» В ЦВЕТАХ ТЕМЫ
                // (primary и tertiary) с уникальными значками: облако для
                // CloudTips, ракета для Boosty.
                _SupportPill(
                  label: 'CloudTips',
                  icon: Icons.cloud_rounded,
                  gradient: [
                    Color.lerp(accent, Colors.white, 0.30)!,
                    accent,
                    Color.lerp(accent, Colors.black, 0.16)!,
                  ],
                  glow: accent,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openLink(_supportAuthorUrl);
                  },
                ),
                const SizedBox(height: 10),
                _SupportPill(
                  label: 'Boosty',
                  icon: Icons.rocket_launch_rounded,
                  gradient: [
                    Color.lerp(cs.tertiary, Colors.white, 0.30)!,
                    cs.tertiary,
                    Color.lerp(cs.tertiary, Colors.black, 0.16)!,
                  ],
                  glow: cs.tertiary,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openLink(_boostyUrl);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openChangelog() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangelogScreen()));
  }

  Future<void> _openGitHub() async {
    await _openLink('https://github.com/wxstdo-boop/Keramika');
  }

  Future<void> _clearCache() async {
    try {
      // Clear in-memory Flutter image cache.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync()) {
          try {
            if (entity is File) {
              entity.deleteSync();
            } else if (entity is Directory) {
              entity.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('clearCacheDone', context),
        );
      }
    } catch (_) {
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('diagError', context),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
    }
  }
}

/// Beautiful toggle for the Reality Checks section.
/// Lives at the very top of Settings -- immediately catches the user's eye.
/// Toggling this card adds or removes the 'РП' tab in Home together
/// with schedule and notifications.
class _RealityCheckToggleCard extends StatelessWidget {
  const _RealityCheckToggleCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rc = RealityCheckService();
    return ListenableBuilder(
      listenable: rc,
      builder: (context, _) {
        final on = rc.enabled;
        final title = Translations.t(
          'rcSettingsTitle',
          context,
          Translations.realityChecksOf(context),
        );
        final body = Translations.t(
          'rcSettingsBody',
          context,
          // Аббревиатура из перевода (RC/РП/CR), чтобы даже фолбэк не
          // показывал кириллицу в нерусских языках.
          'Adds or removes the section entirely: the '
              '${Translations.rcOf(context)} tab in Home, schedule and notifications.',
        );
        // Плавный переход цвета карточки и текста вместо мгновенного прыжка.
        final bgColor = on
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh;
        final fgColor = on
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface;
        final fgMuted = on
            ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.75)
            : theme.colorScheme.onSurfaceVariant;
        final badgeBg = on
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surface;
        final badgeFg = on
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;
        // AnimatedContainer: фон карточки плавно перетекает между
        // состояниями (раньше был простой Container — цвет переключался
        // мгновенно, хотя текст/бейдж анимировались — выглядело дёргано).
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // blurRadius 4: большие размытые тени на карточках стоят
              // дорого при каждом кадре скролла на средних GPU.
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: on ? 0.07 : 0.03),
                blurRadius: 4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _toggle(context, rc, !on),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Бейдж иконки — плавная смена цвета.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (c, a) => ScaleTransition(
                          scale: Tween<double>(begin: 0.7, end: 1.0).animate(a),
                          child: FadeTransition(opacity: a, child: c),
                        ),
                        child: Icon(
                          Icons.psychology_outlined,
                          key: ValueKey(on),
                          size: 26,
                          color: badgeFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            style: theme.textTheme.titleMedium!.copyWith(
                              fontWeight: FontWeight.w700,
                              color: fgColor,
                            ),
                            child: Text(title),
                          ),
                          const SizedBox(height: 4),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: fgMuted,
                            ),
                            child: Text(body),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    VolumetricSwitch(
                      value: on,
                      onChanged: (v) => _toggle(context, rc, v),
                      activeColor: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggle(BuildContext context, RealityCheckService rc, bool newValue) {
    rc.setEnabled(newValue);
    // When turning off: cancel any scheduled Rb notifications so they don't
    // surprise the user while the section is hidden. Turn-on is left for
    // the Rb screen initState to schedule next time it is shown.
    if (!newValue) {
      notificationService.cancelAllRealityChecks();
    }
    if (!context.mounted) return;
    // groupKey объединяет быстрые ON↔OFF-переключения в одну плашку — не даёт шторм.
    showBeautifulSnackBar(
      context,
      message: newValue
          ? Translations.t(
              'rcSettingsOn',
              context,
              'Раздел «Проверки реальности» включён',
            )
          : Translations.t(
              'rcSettingsOff',
              context,
              'Раздел «Проверки реальности» скрыт',
            ),
      icon: newValue
          ? Icons.check_circle_outline
          : Icons.visibility_off_outlined,
      iconColor: newValue ? Colors.green : Colors.orange,
      groupKey: 'rcSettingsToggle',
    );
  }
}

/// Кнопка-«трек» в стиле переключателей: чистый корпус с градиентной
/// заливкой, мягким цветным свечением и белой иконкой-капсулой. БЕЗ нижней
/// полосы-грани — объём только через тень и блик. Зажатие у всех таких
/// кнопок одинаковое: мягкое вдавливание по высоте + схлопывание тени.
/// Кнопка-«таблетка» способа оплаты в окне поддержки: градиентная широкая
/// строка с иконкой в кружке, названием и стрелкой. Используется внутри
/// bottom sheet (CloudTips / Boosty и др.).
class _SupportPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback onTap;

  const _SupportPill({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.onTap,
  });

  @override
  State<_SupportPill> createState() => _SupportPillState();
}

class _SupportPillState extends State<_SupportPill> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    // Контраст под текущую тему: на светлых темах градиент светлый →
    // тёмный текст, на тёмных → белый.
    final fg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xDE000000);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _setPressed(true);
        Haptics.medium();
      },
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        height: _pressed ? 58 : 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withValues(alpha: _pressed ? 0.2 : 0.35),
              blurRadius: _pressed ? 6 : 14,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.gradient,
          ),
          border: Border.all(
            color: fg.withValues(alpha: 0.40),
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg.withValues(alpha: 0.18),
                border: Border.all(
                  color: fg.withValues(alpha: 0.40),
                  width: 1,
                ),
              ),
              child: Icon(widget.icon, color: fg, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: fg.withValues(alpha: 0.7),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback? onTap;

  const _CtaButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glow,
    this.onTap,
  });

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xDE000000);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _setPressed(true);
        // Отдача при нажатии — как у остальных кнопок приложения.
        Haptics.medium();
      },
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: _pressed ? 56 : 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withValues(alpha: _pressed ? 0.22 : 0.38),
              blurRadius: _pressed ? 6 : 14,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.gradient,
          ),
          border: Border.all(
            color: fg.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Верхний блик — лёгкая выпуклость, как у шайбы переключателя.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    fg.withValues(alpha: 0.22),
                    fg.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fg.withValues(alpha: 0.20),
                    border: Border.all(
                      color: fg.withValues(alpha: 0.40),
                      width: 1,
                    ),
                  ),
                  child: Icon(widget.icon, color: fg, size: 17),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            // Стрелка справа — кнопка «открывает окно», намекает на это.
            Positioned(
              right: 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: fg.withValues(alpha: 0.7),
                  size: 26,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна запись карусели тем: ключ темы, название и иконка.
class _ThemeEntry {
  final String key;
  final String label;
  final IconData icon;
  final bool specialMutilated;

  const _ThemeEntry(
    this.key,
    this.label,
    this.icon, {
    this.specialMutilated = false,
  });
}

/// Едва заметные кровавые пятна для карточки BERSERK.
/// Статичный слой: рисуется один раз на размер карточки, без анимации.
class _BloodStainsPainter extends CustomPainter {
  const _BloodStainsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final blobs = <({Offset center, double radius})>[
      (
        center: Offset(size.width * 0.08, size.height * 0.16),
        radius: size.width * 0.30,
      ),
      (
        center: Offset(size.width * 0.94, size.height * 0.52),
        radius: size.width * 0.34,
      ),
      (
        center: Offset(size.width * 0.16, size.height * 0.88),
        radius: size.width * 0.26,
      ),
      (
        center: Offset(size.width * 0.80, size.height * 0.08),
        radius: size.width * 0.20,
      ),
      (
        center: Offset(size.width * 0.55, size.height * 0.60),
        radius: size.width * 0.24,
      ),
    ];
    for (final blob in blobs) {
      final rect = Rect.fromCircle(center: blob.center, radius: blob.radius);
      final paint = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x59B51F32), Color(0x22B51F32), Color(0x00B51F32)],
        ).createShader(rect);
      canvas.drawCircle(blob.center, blob.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BloodStainsPainter oldDelegate) => false;
}

/// Логотип Flutter: три фирменные «ступеньки» (светло-голубая, синяя,
/// тёмно-синяя) в мягком круглом бейдже с лёгкой «стеклянной» подложкой.
/// Стоит внизу карточки тем, внутри неё — как аккуратный фирменный акцент.
class _FlutterBadge extends StatelessWidget {
  const _FlutterBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = Color.lerp(cs.surfaceContainerHighest, cs.primary, 0.06)!;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, cs.surfaceContainerHighest],
        ),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: CustomPaint(
        size: const Size.square(16),
        painter: _FlutterLogoPainter(
          // Ступеньки в цвет текущей темы: светлый/средний/тёмный оттенки
          // primary вместо фирменных синих — значок подстраивается под
          // каждую тему.
          light: Color.lerp(cs.primary, Colors.white, 0.72)!,
          mid: Color.lerp(cs.primary, Colors.black, 0.05)!,
          dark: Color.lerp(cs.primary, Colors.black, 0.30)!,
        ),
      ),
    );
  }
}

class _FlutterLogoPainter extends CustomPainter {
  final Color light;
  final Color mid;
  final Color dark;

  const _FlutterLogoPainter({
    required this.light,
    required this.mid,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final lightPaint = Paint()..color = light;
    final midPaint = Paint()..color = mid;
    final darkPaint = Paint()..color = dark;

    final step = w / 3.0;
    // Верхняя ступенька: полная ширина, правый край скошен.
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w - step, h / 3)
        ..lineTo(0, h / 3)
        ..close(),
      lightPaint,
    );
    // Средняя ступенька: правая граница уходит дальше влево.
    canvas.drawPath(
      Path()
        ..moveTo(0, h / 3)
        ..lineTo(w - step, h / 3)
        ..lineTo(w - 2 * step, 2 * h / 3)
        ..lineTo(0, 2 * h / 3)
        ..close(),
      midPaint,
    );
    // Нижняя ступенька: самая узкая.
    canvas.drawPath(
      Path()
        ..moveTo(0, 2 * h / 3)
        ..lineTo(w - 2 * step, 2 * h / 3)
        ..lineTo(w - 3 * step, h)
        ..lineTo(0, h)
        ..close(),
      darkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FlutterLogoPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.mid != mid ||
      oldDelegate.dark != dark;
}
