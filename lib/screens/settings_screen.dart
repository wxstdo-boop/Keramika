import 'dart:async';
import '../services/haptics.dart';
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
import '../services/settings_service.dart';
import '../services/timer_service.dart';
import '../services/prefs.dart';
import '../services/json_file.dart';
import '../utils/wide_dash_formatter.dart';
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
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import 'changelog_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

part 'settings_components.dart';

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
      _checkPermissionWarning(),
      _checkNotificationsEnabled(),
      _checkFullScreenGrant(),
      _loadAiGuide(),
      _loadAiTracking(),
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
  /// Название текущего языка для поля выбора.
  String _languageLabel(BuildContext context, String code) {
    switch (code) {
      case 'system':
        return Translations.followSystemOf(context);
      case 'en':
        return Translations.englishOf(context);
      case 'ru':
        return Translations.russianOf(context);
      case 'fr':
        return Translations.frenchOf(context);
      default:
        return Translations.followSystemOf(context);
    }
  }

  /// Меню выбора языка: компактный квадрат со скруглёнными углами, который
  /// появляется МЕЛКИМ и плавно растёт в полный рост (scale + fade),
  /// вместо стандартной анимации выпадашки.
  Future<void> _showLanguageMenu(
    BuildContext context,
    KeramikaAppState appState,
  ) async {
    // Язык выбирается БЕЗ закрытия окна: тап по пункту сразу переключает
    // язык и плавно обновляет фон/галочку, а само меню закрывается ТОЛЬКО
    // тапом вне квадрата (барьер). Раньше тап по пункту сразу «щёлкал»
    // окно закрытием и не давал попробовать другие языки подряд.
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, _) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final codes = ['system', 'en', 'ru', 'fr'];
        return StatefulBuilder(
          builder: (ctx, setState) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                // Урезано по бокам: квадрат, а не растянутая лента.
                width: 230,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final code in codes)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          appState.setLanguageCode(code);
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: code == appState.languageCode
                                ? cs.primary.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    color: code == appState.languageCode
                                        ? cs.primary
                                        : cs.onSurface,
                                    fontWeight: code == appState.languageCode
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  child: Text(_languageLabel(context, code)),
                                ),
                              ),
                              // Галочка плавно появляется/исчезает и
                              // «проскальзывает» при смене выбранного языка.
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                      scale: anim,
                                      child: FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                    ),
                                child: code == appState.languageCode
                                    ? Icon(
                                        Icons.check_rounded,
                                        key: const ValueKey('check'),
                                        size: 20,
                                        color: cs.primary,
                                      )
                                    : const SizedBox(
                                        key: ValueKey('no_check'),
                                        width: 20,
                                        height: 20,
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
          ),
        );
      },
      // Мелкий квадрат → плавный полный рост.
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.2, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  Future<void> _showFontMenu(
    BuildContext context,
    KeramikaAppState appState,
  ) async {
    // Шрифт выбирается ТАК ЖЕ, как язык: меню-квадрат с иконками и
    // плавной обводкой/галочкой, которое не закрывается при выборе —
    // только тапом вне квадрата.
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, _) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final fonts = [
          ('ordinary', Icons.font_download_outlined),
          ('caveat', Icons.draw_outlined),
        ];
        String fontLabel(String f) => f == 'caveat' ? 'Caveat' : 'Обычный';
        return StatefulBuilder(
          builder: (ctx, setState) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 230,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (f, icon) in fonts)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          appState.setFontFamily(f);
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: f == appState.fontFamily
                                ? cs.primary.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  icon,
                                  key: ValueKey(icon),
                                  size: 20,
                                  color: f == appState.fontFamily
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    color: f == appState.fontFamily
                                        ? cs.primary
                                        : cs.onSurface,
                                    fontWeight: f == appState.fontFamily
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  child: Text(
                                    fontLabel(f),
                                    style: f == 'caveat'
                                        ? const TextStyle(
                                            fontFamily: 'Caveat',
                                            fontSize: 24,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                      scale: anim,
                                      child: FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                    ),
                                child: f == appState.fontFamily
                                    ? Icon(
                                        Icons.check_rounded,
                                        key: const ValueKey('check'),
                                        size: 20,
                                        color: cs.primary,
                                      )
                                    : const SizedBox(
                                        key: ValueKey('no_check'),
                                        width: 20,
                                        height: 20,
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
          ),
        );
      },
      // Мелкий квадрат → плавный полный рост.
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.2, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

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
    // file_picker 13: статический `saveFile` возвращает `Uri?`, а не путь
    // строкой — нам нужен только факт успешного сохранения.
    final savedUri = await FilePicker.saveFile(
      dialogTitle: exportTitle,
      fileName: 'keramika-backup.json',
      bytes: Uint8List.fromList(bytes),
    );
    systemUiActive = false;
    if (savedUri != null && mounted) {
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
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    systemUiActive = false;
    if (picked?.path == null || !mounted) return;
    if (!picked!.name.toLowerCase().endsWith('.json')) {
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
      final content = await File(picked.path!).readAsString();
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
        'ai_pinned_messages',
        'ada_sync_state',
        'completion_log',
        'ny_event_2027',
      };
      final listServiceKeys = <String>{
        'habits',
        'tasks',
        'alarms',
        'app_timers',
        'nutrition_meals',
      };
      final settingsKeys = <String>{
        'app_settings',
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
      for (final entry in decoded.entries) {
        if (entry.value == null) continue;
        final key = entry.key;
        final v = entry.value;
        if (key == 'app_settings' && v is Map) {
          final settingsRaw = await JsonFile.read('app_settings');
          final settings = settingsRaw != null
              ? Map<String, dynamic>.from(jsonDecode(settingsRaw))
              : <String, dynamic>{};
          settings.addAll(Map<String, dynamic>.from(v));
          await JsonFile.write('app_settings', jsonEncode(settings));
        } else if (serviceKeys.contains(key) && v is String) {
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
          if (key == 'developer_prompt') {
            if (v is! String) {
              throw const FormatException(
                'The developer prompt in this backup is invalid',
              );
            }
            await SettingsService.saveDeveloperPrompt(v);
            continue;
          }
          final settingsRaw = await JsonFile.read('app_settings');
          final settings = settingsRaw != null
              ? Map<String, dynamic>.from(jsonDecode(settingsRaw))
              : <String, dynamic>{};
          settings[key] = v;
          await JsonFile.write('app_settings', jsonEncode(settings));
        } else if (key == 'app_pin' && v is String) {
          await PinService.importBackupValue(v);
        } else {
          if (v is String) {
            await globalPrefs.setString(key, v);
          } else if (v is bool) {
            await globalPrefs.setBool(key, v);
          } else if (v is int) {
            await globalPrefs.setInt(key, v);
          } else if (v is double) {
            await globalPrefs.setDouble(key, v);
          } else if (v is List) {
            await globalPrefs.setStringList(key, v.cast<String>());
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
      if (!mounted) return;
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
      // «Метель» — подарок 12-го дня ивента: в карусели появляется только
      // после его получения и пропадает вместе со сбросом события.
      if (NewYearEventService().prizeGranted)
        _ThemeEntry('metel', Translations.t('metel', context), Icons.snowing),
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
    // Для MUTILATED — зажатие 10 секунд показывает плашную «Вы элегант?»
    // с переводами. Плавно появляется, держится 3 секунды, плавно уходит.
    // ТОНКАЯ обводка (1px) с НАСТОЯЩЕЙ анимацией: begin всегда 0,
    // end = 1 для выбранного / 0 для остальных. TweenAnimationBuilder
    // сам анимирует переход (текущее значение → end) при каждом
    // rebuild, поэтому при выборе линия плавно «проявляется» (0→1),
    // при снятии — плавно «гаснет» (1→0). ВАЖНО: begin фиксирован —
    // одинаковые begin/end давали мгновенный скачок.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isSelected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      builder: (context2, alphaBorder, _) {
        final themeLocal = Theme.of(context2);
        final chip = ChoiceChip(
          // Крупные названия: в карусели у каждой темы много места, длинные
          // имена (MUTILATED, System Light) масштабируются вниз.
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          // Галочка выбранной темы появляется плавно.
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
            Haptics.select();
            if (key == 'peach' && appState.themeKey == 'peach') {
              appState.togglePeachDark();
            } else {
              appState.setThemeMode(key);
            }
            extraOnSelected?.call();
          },
          // Обводка тонкая (1px) и АНИМИРУЕТСЯ по alpha каждый кадр.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: themeLocal.colorScheme.primary.withValues(
                alpha: alphaBorder,
              ),
              width: 1,
            ),
          ),
        );
        if (!specialMutilated) return Center(child: chip);
        return Center(
          child: _LongPressChip(
            duration: const Duration(seconds: 10),
            onLongPress: () {
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
      },
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

      const SizedBox(height: 8),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.text_fields_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Шрифт',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Шрифт выбирается так же, как язык: тап по плитке открывает
              // меню-квадрат с иконками, плавной обводкой и галочкой —
              // окно не закрывается при выборе, только тапом вне квадрата.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showFontMenu(context, appState),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          appState.fontFamily == 'caveat'
                              ? Icons.draw_outlined
                              : Icons.font_download_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            appState.fontFamily == 'caveat'
                                ? 'Caveat'
                                : 'Обычный',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
              // Своё «выпадающее» меню вместо DropdownButton: появляется
              // мелким квадратом и плавно растёт в полный рост (scale +
              // fade), по бокам урезано — компактный квадрат со скруглёнными
              // углами, как просил.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showLanguageMenu(context, appState),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.language,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _languageLabel(context, appState.languageCode),
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
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
              // Номер версии — пасхалка: держим палец → конфетти в цветах
              // темы + тост. GestureDetector без ripple, чтобы не портить
              // «информационный» вид строки.
              // Версия (долгое нажатие — пасхалка) и рядом полупрозрачная
              // таблетка «Проверить обновления».
              Row(
                children: [
                  GestureDetector(
                    onLongPress: _onVersionLongPress,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        // В «О приложении» — именно «1.3-release», как просил.
                        'v$appVersion-release',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
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
                      const SizedBox(width: 8),
                      const UpdatePill(),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.28,
                            ),
                          ),
                        ),
                        child: Text(
                          'Recommended',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => _openLink(
                  'https://gitflic.ru/project/wetcorporation/keramika',
                ),
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
                          'GitFlic',
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
                // «Кровавый» вид: топ-стоп тёплого ализарина, середина —
                // насыщенный багровый, низ — почти вишнёвый, как Запекшаяся
                // кровь. Свечение в тон середины: кнопка горит изнутри,
                // а не светится розовым обертоном.
                gradient: const [
                  Color(0xFFFF5A66),
                  Color(0xFFD90D28),
                  Color(0xFF7E0B1B),
                ],
                glow: const Color(0xFFC8102E),
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
          final fsOn = notificationService.fullscreen;
          // Намерение пользователя и РЕАЛЬНОЕ системное право — разные вещи.
          final fsBlocked = fsOn && !notificationService.fullScreenGranted;
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
                  PressScale(
                    child: ListTile(
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
                  ),
                  PressScale(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(Translations.fullscreenNotifDescOf(context)),
                      // Переключатель выше — это НАМЕРЕНИЕ пользователя.
                      // Право же выдаёт система (app-op USE_FULL_SCREEN_INTENT),
                      // и с Android 14 оно по умолчанию ЗАПРЕЩЕНО: без него
                      // будильник приходит только шапкой уведомления, экран
                      // задачи поверх блокировки не появляется. Показываем это
                      // честно и ведём ровно на тот экран, где тумблер живёт.
                      subtitle: fsBlocked
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                Translations.t(
                                  'fullScreenGrantMissing',
                                  context,
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            )
                          : null,
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
                          fsOn && !fsBlocked
                              ? Icons.fullscreen
                              : Icons.fullscreen_exit,
                          key: ValueKey('fullscreen_icon_${fsOn}_$fsBlocked'),
                          color: fsBlocked
                              ? theme.colorScheme.error
                              : fsOn
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () async {
                        if (fsBlocked) {
                          // Право не выдано → тап по строке ведёт на его выдачу.
                          await openFullScreenNotifSettings();
                          return;
                        }
                        await notificationService.setFullscreen(!fsOn);
                      },
                      trailing: VolumetricSwitch(
                        value: fsOn,
                        onChanged: (v) => notificationService.setFullscreen(v),
                        activeColor: theme.colorScheme.primary,
                      ),
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
              PressScale(
                child: ListTile(
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
                    final cantOpenText = Translations.t(
                      'settingsCantOpen',
                      ctx,
                    );
                    final opened = await openAppSettingsAndroid();
                    if (!ctx.mounted) return;
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
              ),
              const Divider(height: 1),
              PressScale(
                child: ListTile(
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
                    if (!opened && ctx.mounted) {
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
              ),
              const Divider(height: 1),
              PressScale(
                child: ListTile(
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
                    if (!opened && ctx.mounted) {
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
          child: PressScale(
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
                await globalPrefs.setBool(
                  'permission_warning_dismissed',
                  false,
                );
                if (context.mounted) {
                  showBeautifulSnackBar(
                    context,
                    message: Translations.t('warningsResetDone', context),
                  );
                }
                if (context.mounted) {
                  KeramikaApp.of(context).refreshApp();
                }
              },
            ),
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
              PressScale(
                child: ListTile(
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
              ),
              const Divider(height: 1),
              PressScale(
                child: ListTile(
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
              ),
              const Divider(height: 1),
              PressScale(
                child: ListTile(
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
                  // Значок Ады: своя «искры-светлячок» вместо общей
                  // иконки-компаса — плавная анимация при тапе, как у
                  // канарейки в уголке разработчика, только другой персонаж.
                  const AdaIcon(size: 34),
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
              PressScale(
                child: ListTile(
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
                              'Poolside / Agnes AI / Zen — API key',
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
                              child: SmoothTyping(
                                controller: _aiKeyController,
                                // Ключ, скрытый «звёздочками», рисует само поле:
                                // по точкам анимация бессмысленна.
                                enabled: _aiKeyVisible,
                                builder: (style) => TextField(
                                  style: style,
                                  cursorOpacityAnimates: true,
                                  magnifierConfiguration:
                                      TextMagnifierConfiguration.disabled,
                                  controller: _aiKeyController,
                                  contextMenuBuilder: minimalContextMenuBuilder,
                                  obscureText: !_aiKeyVisible,
                                  textInputAction: TextInputAction.done,
                                  maxLength: 500,
                                  inputFormatters: [WideDashFormatter()],
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  maxLines: 1,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    counterText: '',
                                    hintText:
                                        'Вставь ключ Poolside, Agnes AI или Zen',
                                    suffixIcon: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
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
                                            () =>
                                                _aiKeyVisible = !_aiKeyVisible,
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
                            PressScale(
                              child: ListTile(
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
                  if (!context.mounted) return;
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
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            // Канарейка вместо «телефонной» иконки developer-mode: стоит
            // статично, при тапе плавно машет крылом; повторные тапы,
            // пока анимация жива, игнорируются внутри самой канарейки.
            leading: const CanaryIcon(size: 40),
            title: Text(_developerCornerTitle(context)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: _devOpening ? null : _showDevToolsScreen,
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
              PressScale(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Значок плавно меняется при включении/выключении:
                  // контурные часы → залитые + галочка, с fade и «попом».
                  // Значок автоэкспорта плавно меняется при включении/выключении:
                  // чистый кроссфейд (без «попа»-масштаба, который дёргал) между
                  // двумя РАЗНЫМИ значками — ещё и цвет мягко анимируется, чтобы
                  // переход был ощутимо плавным, а не щелчком.
                  leading: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeInOutCubic,
                    switchOutCurve: Curves.easeInOutCubic,
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Icon(
                      _autoExport
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_sync_outlined,
                      key: ValueKey('autoexport_$_autoExport'),
                      color: theme.colorScheme.primary.withValues(
                        alpha: _autoExport ? 1.0 : 0.45,
                      ),
                    ),
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
  void _showDevModeDialog() {
    if (_devMode) {
      _showDevToolsScreen();
      return;
    }
    var openToolsAfterClose = false;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: Translations.t('devMode', context),
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 460),
      pageBuilder: (ctx, _, _) => MediaQuery.removeViewInsets(
        context: ctx,
        removeBottom: true,
        child: SafeArea(
          child: Center(
            child: DeveloperModePasswordDialog(
              title: Translations.t('devMode', ctx),
              prompt: Translations.t(
                'devModePrompt',
                ctx,
                'Enter the access code to continue',
              ),
              invalidCode: Translations.t(
                'devModeInvalidCode',
                ctx,
                'That code did not match. Try again.',
              ),
              cancelLabel: Translations.cancelOf(ctx),
              unlockLabel: Translations.t('devModeUnlock', ctx, 'Unlock'),
              onCancel: () => Navigator.of(ctx).pop(),
              onUnlock: () async {
                await SettingsService.saveDevMode(true);
                if (!mounted || !ctx.mounted) return;
                setState(() => _devMode = true);
                _perfController.forward();
                openToolsAfterClose = true;
                Navigator.of(ctx).pop();
              },
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    ).then((_) {
      if (openToolsAfterClose && mounted) _showDevToolsScreen();
    });
  }

  Future<void> _showDevToolsScreen() async {
    if (_devOpening) return;
    _devOpening = true;
    try {
      await _openDevToolsScreen();
    } finally {
      _devOpening = false;
    }
  }

  Future<void> _openDevToolsScreen() async {
    late final String developerPrompt;
    try {
      developerPrompt = await SettingsService.loadDeveloperPrompt();
    } catch (error) {
      if (mounted) showBeautifulSnackBar(context, message: error.toString());
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (routeContext, animation, secondaryAnimation) {
          // ЛОКАЛЬНОЕ состояние переключателей уголка: ValueNotifier'ы
          // живут внутри роута, и стрелка рисует значение мгновенно.
          // Раньше переключатель зависел от setState ВНЕШНЕГО экрана
          // настроек — тот мог не отработать (скрытый под роутом/
          // устаревший), и тап «уходил в пустоту»: после открытия уголка
          // настройка переставала работать. Теперь UI-источник один —
          // локальный, а наружное состояние и сервис обновляются следом.
          final perfectionismFlag = ValueNotifier<bool>(_perfectionism);
          final taskNotesFlag = ValueNotifier<bool>(_taskNotes);
          final berserkFlag = ValueNotifier<bool>(_berserk);
          final cs = Theme.of(routeContext).colorScheme;

          void syncOuterScreen() {
            if (!mounted) return;
            // БЕЗ setState: экран настроек лежит ПОД роутом уголка и не
            // виден, а его перестройка — это тысячи виджетов на каждый
            // тап переключателя. Раньше именно она и давала «дичайшие
            // подтормаживания» уголка. Поля просто запоминаем — они
            // прочитаются при следующем открытии уголка.
            _perfectionism = perfectionismFlag.value;
            _taskNotes = taskNotesFlag.value;
            _berserk = berserkFlag.value;
          }

          Future<void> savePerfectionism(bool value) async {
            perfectionismFlag.value = value; // мгновенный отклик
            syncOuterScreen();
            try {
              await SettingsService.savePerfectionism(value);
            } catch (e) {
              perfectionismFlag.value = !value; // откат при отказе сервиса
              syncOuterScreen();
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          Future<void> saveTaskNotes(bool value) async {
            taskNotesFlag.value = value;
            syncOuterScreen();
            try {
              await SettingsService.saveTaskNotes(value);
            } catch (e) {
              taskNotesFlag.value = !value;
              syncOuterScreen();
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          Future<void> saveBerserk(bool value) async {
            berserkFlag.value = value;
            syncOuterScreen();
            try {
              await SettingsService.saveBerserk(value);
            } catch (e) {
              berserkFlag.value = !value;
              syncOuterScreen();
              if (routeContext.mounted) {
                showBeautifulSnackBar(routeContext, message: e.toString());
              }
            }
          }

          return DeveloperCornerScreen(
            title: _developerCornerTitle(routeContext),
            controlsLabel: _developerControlsLabel(routeContext),
            subtitle: Translations.t(
              'devToolsSubtitle',
              routeContext,
              'Hidden controls for tuning the Keramika experience.',
            ),
            disableLabel: Translations.t(
              'devModeDisable',
              routeContext,
              'Turn off developer mode',
            ),
            developerPrompt: developerPrompt,
            onSaveDeveloperPrompt: SettingsService.saveDeveloperPrompt,
            accent: cs.primary,
            onDisable: () async {
              await SettingsService.saveDevMode(false);
              if (!mounted || !routeContext.mounted) return;
              setState(() => _devMode = false);
              _perfController.reverse();
              Navigator.of(routeContext).pop();
            },
            children: [
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFB39DDB),
                ),
                title: Text(Translations.t('perfectionism', routeContext)),
                subtitle: Text(
                  Translations.t('perfectionismHint', routeContext),
                ),
                // Горжусь мгновенной стрелкой: тап перевернёт
                // ЛОКАЛЬНЫЙ флаг, а внешний экран догонит следом.
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: perfectionismFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    // Свой слой перерисовки: 720-мс анимация большого
                    // пальца не перерастеризует плитку целиком (кольцо +
                    // змейка + тени) каждый кадр — отсюда были тормоза.
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: savePerfectionism,
                      activeColor: const Color(0xFFB39DDB),
                      // Крупнее и объёмнее — уголок разработчика.
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => savePerfectionism(!perfectionismFlag.value),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFFD3A7FF),
                ),
                title: Text(Translations.t('taskNotesTitle', routeContext)),
                subtitle: Text(
                  Translations.t('taskNotesSubtitle', routeContext),
                ),
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: taskNotesFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: saveTaskNotes,
                      activeColor: const Color(0xFFD3A7FF),
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => saveTaskNotes(!taskNotesFlag.value),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFF5265),
                ),
                title: Text(Translations.t('berserkCardTitle', routeContext)),
                subtitle: Text(
                  Translations.t('berserkCardSubtitle', routeContext),
                ),
                trailing: ValueListenableBuilder<bool>(
                  valueListenable: berserkFlag,
                  builder: (context, value, _) => RepaintBoundary(
                    child: VolumetricSwitch(
                      value: value,
                      onChanged: saveBerserk,
                      activeColor: const Color(0xFFFF5265),
                      scale: 1.28,
                    ),
                  ),
                ),
                onTap: () => saveBerserk(!berserkFlag.value),
              ),
            ],
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Въезд — easeOutCubic, выезд (жест «назад»/свайп вправо) —
          // easeInOutCubic: экран не «падает» мгновенно в начале отдачи
          // (easeInCubic стартовал на нуле скорости и потом рванул), а
          // уходит с той же скоростью, с которой читался въезд. Обратный
          // переезд тоже подольше (420 мс).
          final entrance = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(entrance),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.16, 0),
                end: Offset.zero,
              ).animate(entrance),
              child: ScaleTransition(
                alignment: Alignment.centerRight,
                scale: Tween<double>(begin: 0.94, end: 1).animate(entrance),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  String _developerCornerTitle(BuildContext context) {
    return switch (LocaleProvider.of(context).languageCode) {
      'ru' => 'Уголок разработчика',
      'fr' => 'Coin développeur',
      _ => 'Developer corner',
    };
  }

  String _developerControlsLabel(BuildContext context) {
    return switch (LocaleProvider.of(context).languageCode) {
      'ru' => 'ЭКСПЕРИМЕНТАЛЬНЫЕ НАСТРОЙКИ',
      'fr' => 'OPTIONS EXPÉRIMENTALES',
      _ => 'EXPERIMENTAL CONTROLS',
    };
  }

  Widget _diagTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return PressScale(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(label, style: theme.textTheme.bodyMedium),
        trailing: const Icon(Icons.play_arrow_outlined, size: 20),
        dense: true,
        onTap: onTap,
      ),
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
                // с уникальными значками: красная сумка у Ozon — плашка SOON
                // сохранена, но зажимается ТАКЖЕ плавно, как Boosty (340 мс).
                _SupportPill(
                  label: 'Ozon',
                  icon: Icons.shopping_bag_rounded,
                  badge: 'SOON',
                  subtitle: Translations.t('supportOzonSubtitle', context),
                  gradient: const [
                    Color(0xFFFF5A6E),
                    Color(0xFFE8263C),
                    Color(0xFFB3152E),
                  ],
                  glow: const Color(0xFFE8263C),
                  onTap: () {
                    showBeautifulSnackBar(
                      context,
                      message: Translations.t(
                        'supportSoonToast',
                        context,
                        'Ozon is coming soon. Stay tuned!',
                      ),
                      icon: Icons.hourglass_top_rounded,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SupportPill(
                  label: 'Boosty',
                  icon: Icons.rocket_launch_rounded,
                  subtitle: Translations.t('supportBoostySubtitle', context),
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

  /// Пасхалка по долгому нажатию на номер версии: тяжёлый тактильный
  /// отклик, залп конфетти в цветах текущей темы и тост.
  void _onVersionLongPress() {
    Haptics.heavy();
    showConfettiBurst(context);
    showBeautifulSnackBar(
      context,
      message: 'Ты нашёл пасхалку. Keramika — свободное приложение.',
      icon: Icons.celebration_outlined,
      duration: const Duration(milliseconds: 2600),
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
