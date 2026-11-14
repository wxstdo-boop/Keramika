import 'dart:async';
import '../services/haptics.dart';
import '../services/sounds.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../utils/android_settings.dart';
import '../services/pin_service.dart';
import '../services/reality_check_service.dart';
import '../widgets/canary_icon.dart';
import '../widgets/ada_icon.dart';
import '../widgets/settings_search_icon.dart';
import '../widgets/press_scale.dart';
import '../services/alarm_service.dart';
import '../services/app_version.dart';
import '../services/settings_service.dart';
import '../services/timer_service.dart';
import '../services/prefs.dart';
import '../services/json_file.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../services/nutrition_service.dart';
import '../services/new_year_event_service.dart';
import '../services/ai_guide_service.dart';
import '../l10n/translations.dart';
import '../l10n/locale_provider.dart';
import '../utils/context_menu.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/confetti_burst.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../widgets/update_pill.dart';
import 'lock_screen.dart';
import 'developer_corner_screen.dart';
import '../services/update_service.dart';
import 'forge_screen.dart';
import '../utils/page_transitions.dart';
import '../utils/motion_prefs.dart';
import '../utils/snackbar.dart';
import 'changelog_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/agysha_confirm_dialog.dart';

part 'settings_components.dart';
part 'settings_permissions.dart';
part 'settings_language_font.dart';
part 'settings_transfer.dart';
part 'settings_theme_carousel.dart';
part 'settings_dev_tools.dart';
part 'settings_links.dart';
part 'settings_section_top.dart';
part 'settings_section_look.dart';
part 'settings_section_access.dart';
part 'settings_section_behavior.dart';
part 'settings_section_ada.dart';
part 'settings_section_diagnostics.dart';

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
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
  bool _haptics = true;
  bool _sounds = false;
  bool _reduceMotion = false;
  bool _permissionWarningDismissed = false;
  bool _grantPressed = false; // Состояние зажатия кнопки «Выдать»
  bool? _notificationsEnabled; // Кэш статуса уведомлений
  // Карусель тем: листается по горизонтали, текущая тема по центру.
  PageController? _themePageCtrl;

  late AnimationController _perfController;
  late Animation<double> _perfScale;
  late Animation<double> _perfFade;

  /// Защита «Уголка разработчика» от многократных тапов: пока диалог/экран
  /// открываются, повторные тапы по плитке не наслаивают вторую откры-
  /// вающуюся настройку.
  bool _devOpening = false;
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
    // Право полноэкранных уведомлений выдаётся В СИСТЕМНЫХ настройках, и
    // пользователь возвращается сюда прямо оттуда: на resumed перечитываем
    // реальное состояние, чтобы переключатель не врал про будильник.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Изменение системного права видно только при возврате в приложение.
      notificationService.refreshFullScreenGrant();
    }
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
      _loadHaptics(),
      _loadSounds(),
      _loadReduceMotion(),
      _checkPermissionWarning(),
      _checkNotificationsEnabled(),
      _checkFullScreenGrant(),
      _loadAiGuide(),
      _loadAiTracking(),
      // Версию уточняем по установленному APK: на Android она отличается
      // от pubspec, если сборка собрана из другой ветки.
      AppVersion.refresh(),
    ]);
    if (mounted) setState(() {});
  }

  /// Реальное состояние права полноэкранных уведомлений из ОС: с Android 14
  /// оно выключено по умолчанию, и без него будильник не откроет экран
  /// задачи поверх блокировки.
  Future<void> _checkFullScreenGrant() async {
    await notificationService.refreshFullScreenGrant();
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
    WidgetsBinding.instance.removeObserver(this);
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
        if (!mounted) return;
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

  /// Красивая адаптивная плашка «Разрешения не выданы»: работает и на
  /// светлых, и на тёмных темах (вместо жёстко-красного errorContainer
  /// с белой кнопкой, который на тёмных темах выглядел плохо).

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

  Future<void> _loadHaptics() async {
    _haptics = await SettingsService.loadHaptics();
    Haptics.enabled = _haptics;
  }

  Future<void> _setHaptics(bool value) async {
    await SettingsService.saveHaptics(value);
    Haptics.enabled = value;
    if (mounted) setState(() => _haptics = value);
    // Отклик на само включение: когда включаем — даём короткий клик, чтобы
    // человек сразу услышал/почувствовал, что стало иначе.
    if (value) Haptics.select();
  }

  Future<void> _loadSounds() async {
    _sounds = await SettingsService.loadSounds();
    Sounds.enabled = _sounds;
  }

  Future<void> _setSounds(bool value) async {
    await SettingsService.saveSounds(value);
    Sounds.enabled = value;
    if (mounted) setState(() => _sounds = value);
    // Отклик на само включение: короткий клик подтверждает, что звук жив.
    if (value) Sounds.click();
  }

  Future<void> _loadReduceMotion() async {
    _reduceMotion = await SettingsService.loadReduceMotion();
    MotionPrefs.enabled.value = _reduceMotion;
  }

  Future<void> _setReduceMotion(bool value) async {
    await SettingsService.saveReduceMotion(value);
    MotionPrefs.enabled.value = value;
    if (mounted) setState(() => _reduceMotion = value);
  }

  /// Перерисовка из part-файлов: `setState` — protected член `State`, и в
  /// расширениях `_Settings*` напрямую недоступен.
  void _refresh(VoidCallback fn) => setState(fn);

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
            AgyshaApp.of(context).lock();
          },
        ),
      ),
    );
  }

  void _removePin() async {
    final confirm = await showAgyshaConfirm(
      context,
      title: Translations.removePinOf(context),
      body: Translations.t('areYouSure', context),
      icon: Icons.lock_outline_rounded,
      confirmLabel: Translations.deleteOf(context),
      destructive: true,
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

  @override
  Widget build(BuildContext context) {
    final appState = AgyshaApp.of(context);
    final theme = Theme.of(context);
    // Список собирается заранее, но рендерится ЛЕНИВО (ListView.builder):
    // экран настроек открывается без подлагивания — за кадром строятся
    // только видимые карточки, а не все сразу.
    final settingsItems = <Widget>[
      // Разделы живут в part-файлах settings_section_*.dart: список остаётся
      // плоским и ленивым, но без тысяч строк в одном uild.
      ..._settingsTopSection(context, appState, theme),
      ..._settingsLookSection(context, appState, theme),
      ..._settingsAccessSection(context, appState, theme),
      ..._settingsBehaviorSection(context, appState, theme),
      ..._settingsAdaSection(context, appState, theme),
      ..._settingsDiagnosticsSection(context, appState, theme),
    ];
    // «Чуть крупнее» ТОЛЬКО здесь: глобальная тема при обычном шрифте
    // намеренно уменьшает body/label-стили (плотные списки разделов),
    // но в настройках много мелких подписей — читаются тяжело.
    // Локально усиливаем TextScaler на 10%: базовый масштаб системы
    // (если пользователь увеличил шрифт в ОС) сохраняется, явные
    // fontSize карточек тоже масштабируются. Глобальная тема не трогается.
    final boostedTextScaler = TextScaler.linear(
      MediaQuery.textScalerOf(context).scale(1.0) * 1.1,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: boostedTextScaler),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            Translations.settingsOf(context),
            overflow: TextOverflow.ellipsis,
          ),
          // Задизайненный «Назад» (тултип), а не голый системный стрелочный —
          // как в остальных экранах.
          leading: const BackButtonTooltip(),
          // Красивая плавная лупа поиска по настройкам: пока только
          // анимируется при тапе, сам поиск подключим позже.
          actions: const [SettingsSearchIcon(), SizedBox(width: 4)],
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
      ),
    );
  }

  /// Кровавая карточка BERSERK — как «Борьба с перфекционизмом»:
  /// тот же ListTile с переключателем, без открытия по тапу (режим
  /// открывается ТОЛЬКО долгим зажатием «плюса» на главном экране).
  /// Фон — тёмно-красный градиент с едва заметными кровавыми пятнами,
  /// переключатель красный, иконка — топор.

}

/// Beautiful toggle for the Reality Checks section.
/// Lives at the very top of Settings -- immediately catches the user's eye.
/// Toggling this card adds or removes the 'РП' tab in Home together
/// with schedule and notifications.
