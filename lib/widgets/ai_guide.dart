import 'dart:async';
import 'dart:convert';
import '../services/haptics.dart';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'press_scale.dart';
import 'glass_sheen.dart';
import 'section_pill.dart';
import 'stagger_in.dart';
import '../l10n/translations.dart';
import '../services/ai_guide_service.dart';
import '../services/json_file.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../services/prefs.dart';
import '../services/screen_reader_service.dart';
import '../services/settings_service.dart';
import '../overlay/overlay_bridge.dart';
import 'ada_avatars.dart';
import '../utils/snackbar.dart';
import '../utils/context_menu.dart';
import '../utils/markdown_text.dart';
import '../widgets/beautiful_selection.dart';
import '../widgets/smooth_tooltip.dart';
import '../widgets/model_label.dart';
import '../widgets/smooth_typing.dart';

export 'berserk_sheet.dart';
part 'ai_guide_bubbles.dart';
part 'ai_guide_floating.dart';

/// Режим «в окне»: мини-чат свернут в плавающее окошко поверх приложения.
/// Значение хранится в prefs ('ai_floating') — переживает перезапуск.
final ValueNotifier<bool> aiFloating = ValueNotifier<bool>(false);

/// Приватность: плавающее окошко скрывается, когда открыт экран блокировки
/// (PIN) — чтобы нельзя было открыть чат в обход блокировки.
final ValueNotifier<bool> aiLockScreenVisible = ValueNotifier<bool>(false);

/// Глобальный счётчик активных чатов — защита от множественного открытия
/// плавающего окошка (tap → chat → tap → chat → ...).
int _activeChats = 0;
// Анти-дребезг: пока лист открывается/закрывается — тапы по значку Ады
// игнорируются (иначе частые тапы давали мигание окна).
bool _chatBusy = false;
DateTime? _chatCloseAt;

/// Маленький кружок рядом с кнопкой «+». Появляется, когда в настройках
/// включён «Искусственный проводник». Открывает мини-чат Ады.
/// Аватарка Ады, ЖИВО реагирующая на смену значка ([adaAvatarVariant]).
/// В сообщениях, индикаторе печати и плавающей кнопке const-версия
/// «застывала» на старом значке — после смены старые и новые аватарки
/// выглядели как дубликаты. Здесь каждый значок плавно перетекает в новый.
class LiveAdaAvatar extends StatelessWidget {
  final double size;

  const LiveAdaAvatar({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: adaAvatarVariant,
      builder: (context, idx, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: AdaAvatar(
          variantIndex: idx,
          size: size,
          key: ValueKey('live_ada_${size}_$idx'),
        ),
      ),
    );
  }
}

class AiGuideFloatingButton extends StatefulWidget {
  const AiGuideFloatingButton({super.key});

  @override
  State<AiGuideFloatingButton> createState() => _AiGuideFloatingButtonState();
}

class _AiGuideFloatingButtonState extends State<AiGuideFloatingButton> {
  @override
  void initState() {
    super.initState();
    // Подтягиваем текущее значение в notifier (на случай, если settings
    // ещё не грузились) — и виджет сам подхватит его через слушатель.
    SettingsService.loadAiGuide();
  }

  @override
  Widget build(BuildContext context) {
    // Живой слушатель: кружок появляется МГНОВЕННО при включении
    // проводника в настройках — без перезапуска приложения.
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.aiGuideEnabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        // Режим «в окне» включён — кружок у «+» скрыт, живёт окошко.
        // Возвращение кнопки после закрытия окошка — плавное (fade+scale
        // с пружинкой), а не мгновенное.
        return ValueListenableBuilder<bool>(
          valueListenable: aiFloating,
          builder: (context, floating, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: floating
                  ? const SizedBox.shrink(key: ValueKey('hidden'))
                  : KeyedSubtree(
                      key: const ValueKey('ada_fab'),
                      child: _buildFab(context),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildFab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Плавное «вдавливание» при зажатии — как у всех значков приложения.
    return PressScale(
      child: SmoothTooltip(
        message: Translations.t('aiGuide', context, 'AI guide'),
        preferredAbove: true,
        child: FloatingActionButton.small(
          heroTag: 'ai_guide_fab',
          onPressed: () => showAiGuideChat(context),
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: const LiveAdaAvatar(size: 20),
        ),
      ),
    );
  }
}

/// Тап по сердечке/значке Ай: случайный другой вариант. Вызывается из
/// шапки, пузырей и плавающего окошка; живёт в [adaAvatarVariant] и
/// синхронизируется с мини-окошком по каналу сообщений.
/// Поколение чата: растёт при очистке. Отправленные в фоне ответы Ады
/// сверяют своё поколение и НЕ вставляются, если чат успели очистить
/// (иначе после удаления истории «проскальзывал» старый ответ).
int adaChatGeneration = 0;

void cycleAdaAvatar() {
  // Смена ТОЛЬКО на вариант с другим значком И заметно другим оттенком:
  // иначе аватарки с похожими градиентами «дублируются» подряд.
  final cur = adaVariants[adaAvatarVariant.value];
  var best = -1;
  var bestScore = -1.0;
  for (var i = 0; i < 48; i++) {
    final idx = math.Random().nextInt(adaVariants.length);
    if (idx == adaAvatarVariant.value) continue;
    final v = adaVariants[idx];
    if (v.icon == cur.icon) continue;
    var dh = (v.hue - cur.hue).abs() % 360;
    if (dh > 180) dh = 360 - dh;
    // Максимальная «удалённость» по оттенку + лёгкий рандомный разброс,
    // чтобы цикл не шёл по одной и той же последовательности.
    final score = dh + math.Random().nextDouble() * 14;
    if (score > bestScore) {
      bestScore = score;
      best = idx;
    }
  }
  // Вырожденный случай — соседний индекс.
  if (best < 0) {
    best = (adaAvatarVariant.value + 1) % adaVariants.length;
  }
  setAdaAvatarVariant(best);
  Haptics.select();
  // Живая синхронизация с мини-окошком (отдельный движок): аватарка
  // меняется там при ближайшем опросе (~0.7с), через файл состояния.
  writeAdaSyncState(avatar: best);
}

/// Открывает мини-чат Ады снизу экрана.
Future<void> showAiGuideChat(BuildContext context) {
  // Быстрые повторные тапы по значку Ады не должны дёргать окно туда-сюда:
  // пока лист открывается/закрывается (или только что закрылся) — тап
  // игнорируется. Раньше частые тапы давали «окно не вылезает и мигает».
  if (_activeChats > 0 || _chatBusy) return Future<void>.value();
  // Ещё ни разу не закрывался — первый тап всегда проходит (Duration.zero
  // здесь НЕЛЬЗЯ: он < кулдауна и заблокировал бы самое первое открытие).
  final sinceClose = _chatCloseAt == null
      ? const Duration(seconds: 10)
      : DateTime.now().difference(_chatCloseAt!);
  // Короткий кулдаун после закрытия: тап сразу после закрытия снова
  // открывает чат (раньше 1.2 с «проглатывал» второй тап — «через раз»).
  // Защита от пачек тапов — сам isDismissible: false: чат не закрывается
  // от повторного тапа, так что мигать больше нечему.
  if (sinceClose < const Duration(milliseconds: 300)) {
    return Future<void>.value();
  }
  _activeChats++;
  _chatBusy = true;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Повторный тап по значку Ады (или рядом) НЕ закрывает чат: он закрывается
    // крестиком в шапке, свайпом вниз или системной кнопкой «назад».
    isDismissible: false,
    // Плавный выезд с МЯГКИМ стартом: easeInOutQuart — начинает медленно
    // и так же плавно останавливается. Раньше был easeOutQuart, который
    // стартует с максимальной скоростью — отсюда «дёрганое начало».
    // Закрытие — тот же мягкий профиль, без резких рывков.
    sheetAnimationStyle: AnimationStyle(
      curve: Curves.easeInOutQuart,
      duration: const Duration(milliseconds: 520),
      reverseCurve: Curves.easeInOutQuart,
      reverseDuration: const Duration(milliseconds: 400),
    ),
    // Отделяем тяжёлую ленту чата в отдельный composited layer: во время
    // выезда bottom sheet Android двигает готовый слой, а не перерисовывает
    // весь экран и все карточки под ним на каждом кадре.
    builder: (_) => const RepaintBoundary(child: _AiChatSheet()),
  ).whenComplete(() {
    _activeChats = 0;
    _chatBusy = false;
    _chatCloseAt = DateTime.now();
  });
}

/// Тонкая оболочка листа ИИ-чата: единственное, что реагирует на
/// клавиатуру (viewInsets меняется покадрово при её подъёме). Тяжёлое
/// содержимое — [_AiChatBody], которое подаётся как const-child и НЕ
/// пересобирается во время анимации клавиатуры. Раньше весь чат читал
/// MediaQuery и перестраивался на каждом кадре — «чуть тормозно».
class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet();

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  // Один и тот же native filter на протяжении жизни окна. Создание нового
  // ImageFilter в каждом IME-кадре инвалидировало backdrop layer без нужды.
  static final ImageFilter _backdropBlur = ImageFilter.blur(
    sigmaX: 8,
    sigmaY: 8,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Клавиатура: лёгкая оболочка ПОДНИМАЕТСЯ над ней, высота ужимается,
    // чтобы шапка не уходила за экран. Поле ввода всегда видно.
    // Без AnimatedPadding: на Android 11+ viewInsets приходит покадрово
    // вместе с анимацией клавиатуры — обычный Padding двигает лист ровно
    // с ней, без собственной задержки.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final available = MediaQuery.sizeOf(context).height - insets;
    final sheetHeight = available.clamp(260.0, available);
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: _backdropBlur,
            // Подложка приложения непрозрачная; src сохраняет тот же
            // результат размытия, избегая лишнего srcOver blending.
            blendMode: BlendMode.src,
            child: Container(
              height: sheetHeight,
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.72),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              // Тело чата не получает покадровые IME-инсеты: меняется только
              // внешний лёгкий Padding, а лента и её TextFields не пересобираются.
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: const _AiChatBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiChatBody extends StatefulWidget {
  const _AiChatBody();

  @override
  State<_AiChatBody> createState() => _AiChatBodyState();
}

class _AiChatBodyState extends State<_AiChatBody>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _historyKey = 'ai_chat_history';
  static const _pinsKey = 'ai_pinned_messages';
  static const int _maxPins = 10;

  final _inputCtrl = WideDashController();
  final _inputFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  final List<AiMessage> _messages = [];
  String? _historySnapshot;
  // Закреплённые сообщения Ады: живут отдельно от чата и НЕ стираются
  // вместе с ним — только ручным откреплением.
  final List<AiMessage> _pinned = [];
  String? _pinsSnapshot;
  // Сообщения, отмеченные сердечком (лайк). Живут отдельно от чата,
  // переживают очистку и перезапуск приложения.
  final Set<String> _liked = {};
  bool _busy = false;
  bool _error = false;
  String _errorMsg = '';
  bool _storageErrorShown = false;
  // Веб-поиск: значок перед быстрыми чипами плавно включает режим,
  // при котором Ада реально ищет в интернете (DuckDuckGo + Wikipedia).
  bool _webSearch = false;
  // Контекст экрана: Ада «видит» текст активного окна другого
  // приложения (мессенджер и т.п.) и может подсказать ответ собеседнику.
  // Работает только при выданном разрешении «Специальные возможности».
  bool _screenAware = false;
  // Плавная передача эстафеты «печатает…» → ответ: индикатор сначала
  // гаснет, и только потом ответ всплывает — без резкого щелчка.
  bool _typingFade = false;
  // Сколько сообщений было в чате на момент открытия. Анимация входа
  // пузыря — ТОЛЬКО у новых (добавленных ПОСЛЕ открытия): иначе при
  // открытии последние 3 сообщения истории «всплывали» прямо во время
  // выезда листа, и появление чата казалось дёрганым.
  int _openedCount = 0;
  String _lang = 'en';
  int _quotaLeft = 0;
  String _modelLabel = 'ada-0.0.3';
  // Плавная очистка чата: список гаснет, потом стирается.
  late final AnimationController _clearCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  // Троеточие тикает ТОЛЬКО пока Ада отвечает (repeat/stop в _send):
  // вечный repeat() гонял кадры даже когда индикатор не виден — на
  // слабых устройствах это постоянный расход CPU/батареи.
  late final AnimationController _dotsCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  // Плавное выделение поля ввода при фокусе: обводка мягко разгорается
  // (цвет primary) при тапе и гаснет обратно при снятии фокуса. Раньше
  // переключалась мгновенно — @@@@@@ просто «щёлкала».
  late final AnimationController _focusAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  // «Буквы появляются плавно» теперь делает SmoothTyping: каждая буква
  // проявляется и гаснет сама, поэтому общий fade-пульс поля убран —
  // он и был тем самым «миганием» всего текста на каждый символ.

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadPins();
    _loadLiked();
    // Открытый чат слушает доставку и перечитывает историю — отчёт
    // появляется в ленте в момент доставки, без переоткрытия.
    AiGuideService.adaReportTick.addListener(_onAdaReportTick);
    // При фокусе сохраняем текущую позицию чтения: прокрутка одновременно
    // с движением клавиатуры давала заметный скачок ленты.
    _inputFocus.addListener(_onInputFocus);
    // Модель могла смениться в мини-окошке (отдельный движок) — тик
    // приходит по мосту, перечитываем лейбл.
    AiGuideService.modelLabelTick.addListener(_onModelLabelTick);
    // Веб-поиск: запоминаем, был ли он включён — переживает перезапуск.
    try {
      _webSearch = globalPrefs.getBool('ai_web_search') ?? false;
    } catch (_) {}
    // Контекст экрана: помним выключатель (разрешение «Спец. возможности»
    // проверяем отдельно, при включении и при отправке).
    try {
      _screenAware = globalPrefs.getBool(ScreenReaderService.prefKey) ?? false;
    } catch (_) {}
    // Следим за возвратом из системных настроек: если пользователь выдал
    // разрешение «Спец. возможности» — значок включится сам; если отозвал
    // — сам выключится (не должен оставаться «включённым» без разрешения).
    WidgetsBinding.instance.addObserver(this);
  }

  Animation<double>? _chatRouteAnimation;
  bool _deferredInitStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _chatRouteAnimation)) return;
    _chatRouteAnimation?.removeStatusListener(_onChatRouteStatus);
    _chatRouteAnimation = animation;
    animation?.addStatusListener(_onChatRouteStatus);
    if (animation?.status == AnimationStatus.completed) {
      _startPostTransitionWork();
    }
  }

  void _onChatRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _startPostTransitionWork();
    } else if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  void _startPostTransitionWork() {
    if (_deferredInitStarted || !mounted) return;
    _deferredInitStarted = true;
    _ensureReports();
    unawaited(AiGuideService.maybeDeliverAdaNudge('system'));
    unawaited(AiGuideService.loadAdaStreak());
    _refreshScreenPerm();
    SettingsService.loadLanguageCode()
        .then((language) {
          if (!mounted) return;
          setState(() => _lang = language);
          _claimRewards();
        })
        .catchError((_) {});
    AiGuideService.hfRemainingToday()
        .then((remaining) {
          if (mounted) setState(() => _quotaLeft = remaining);
        })
        .catchError((_) {});
    AiGuideService.currentModelLabel()
        .then((label) {
          if (mounted && label.isNotEmpty) setState(() => _modelLabel = label);
        })
        .catchError((_) {});
    _startSyncPolling();
  }

  void _startSyncPolling() {
    if (_syncTimer != null) return;
    _syncTick();
    _syncTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _syncTick(),
    );
  }

  /// Сверяет выключатель с реальным системным разрешением: без разрешения
  /// «Спец. возможности» значок глаза НЕ остаётся включённым.
  Future<void> _refreshScreenPerm() async {
    ScreenReaderService.clearPermissionCache();
    final perm = await ScreenReaderService.hasPermission();
    if (!mounted) return;
    final saved = globalPrefs.getBool(ScreenReaderService.prefKey) ?? false;
    final visible = saved && perm;
    if (_screenAware != visible) {
      setState(() => _screenAware = visible);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из системных настроек «Спец. возможности» — обновляем
    // состояние значка по фактическому разрешению.
    if (state == AppLifecycleState.resumed) _refreshScreenPerm();
  }

  /// Догоняет пропущенный отчёт Ады (если время наступило) и подхватывает
  /// его в ленту. В фоне: история уже на экране, сообщение появится
  /// плавно, когда ИИ допишет.
  Future<void> _ensureReports() async {
    try {
      final delivered = await AiGuideService.maybeDeliverAdaReports('');
      if (delivered.isNotEmpty) await _loadHistory();
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  void _reportStorageFailure(Object error, StackTrace stackTrace) {
    debugPrint('Ada chat history operation failed: $error\n$stackTrace');
    if (!mounted || _storageErrorShown) return;
    _storageErrorShown = true;
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
      groupKey: 'ada-history-storage',
    );
  }

  void _onInputFocus() {
    // Плавная обводка поля ввода: разгорается при фокусе, гаснет при
    // снятии (тап по пузырю сообщения и т.п.).
    if (_inputFocus.hasFocus) {
      _focusAnim.forward();
    } else {
      _focusAnim.reverse();
    }
    // Keep the current reading position; jumping to the newest message on
    // focus competes with the keyboard's own movement.
  }

  void _onAdaReportTick() {
    _loadHistory();
  }

  void _onModelLabelTick() {
    _refreshModelLabel();
  }

  Timer? _syncTimer;
  int _lastSyncAvatar = -1;
  String _lastSyncModel = '';

  /// Опрос файла синхронизации: применяет смену аватарки/модели из
  /// мини-окошка (отдельный движок пишет в тот же файл).
  Future<void> _syncTick() async {
    try {
      final s = await readAdaSyncState();
      if (s.isEmpty) return;
      final av = s['avatar'];
      if (av is int && av >= 0 && av != _lastSyncAvatar) {
        _lastSyncAvatar = av;
        if (av != adaAvatarVariant.value) setAdaAvatarVariant(av);
      }
      final m = s['model'];
      if (m is String && m.isNotEmpty && m != _lastSyncModel) {
        _lastSyncModel = m;
        AiGuideService.recordModelUsed(m);
      }
    } catch (_) {}
  }

  void _refreshModelLabel() {
    AiGuideService.currentModelLabel()
        .then((m) {
          if (mounted && m.isNotEmpty && m != _modelLabel) {
            setState(() => _modelLabel = m);
          }
        })
        .catchError((_) {});
  }

  void _cycleAvatar() {
    // adaAvatarVariant сам уведомляет все аватарки. Не вызываем setState
    // всего чата: это лишний полный rebuild ленты на слабом телефоне.
    cycleAdaAvatar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AiGuideService.adaReportTick.removeListener(_onAdaReportTick);
    AiGuideService.modelLabelTick.removeListener(_onModelLabelTick);
    _chatRouteAnimation?.removeStatusListener(_onChatRouteStatus);
    _syncTimer?.cancel();
    _clearCtrl.dispose();
    _dotsCtrl.dispose();
    _focusAnim.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final raw = await JsonFile.read(_historyKey);
      _historySnapshot = raw;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            // Чат исчерпал 1000 сообщений — стираем и начинаем заново.
            if (loaded.length >= 1000) {
              _messages.clear();
            } else {
              _messages
                ..clear()
                ..addAll(loaded);
            }
            // Всё, что было загружено при открытии, НЕ анимирует вход —
            // только сообщения, добавленные после (см. animate ниже).
            _openedCount = _messages.length;
          });
          // История не менялась: не пересериализуем и не шифруем весь файл
          // при каждом открытии. Сохраняем только если применили лимит.
          if (loaded.length >= 1000) _saveHistory();
          // Открытие чата: мгновенно на последнее сообщение, без
          // «проезда» по всей истории.
          _scrollToBottom(animate: false);
        }
      }
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  Future<void> _saveHistory() async {
    try {
      final value = jsonEncode(_messages.map((m) => m.toJson()).toList());
      final resolved = await JsonFile.writeWithSnapshot(
        _historyKey,
        value,
        _historySnapshot,
      );
      if (resolved == value) _historySnapshot = resolved;
      _storageErrorShown = false;
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  Future<void> _loadPins() async {
    try {
      final raw = await JsonFile.read(_pinsKey);
      _pinsSnapshot = raw;
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _pinned
              ..clear()
              ..addAll(loaded.take(_maxPins));
          });
        }
      }
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  Future<void> _savePins() async {
    try {
      final value = jsonEncode(_pinned.map((m) => m.toJson()).toList());
      final resolved = await JsonFile.writeWithSnapshot(
        _pinsKey,
        value,
        _pinsSnapshot,
      );
      if (resolved == value) _pinsSnapshot = resolved;
      _storageErrorShown = false;
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  /// Ключ сообщения для лайков/закрепления — текст+автор (сообщения в чате
  /// неизменны, так что совпадений между разными сообщениями нет).
  String _msgKey(AiMessage m) => '${m.text.hashCode}_${m.isUser}';

  /// Лайки переживают перезапуск (хранятся отдельно key => ключ сообщения).
  void _loadLiked() {
    final raw = globalPrefs.getStringList('ai_liked_messages');
    if (raw != null) {
      _liked
        ..clear()
        ..addAll(raw);
    }
  }

  void _saveLiked() {
    globalPrefs.setStringList('ai_liked_messages', _liked.toList());
  }

  /// Сердечко на сообщении Ады: пустое ↔ залитое, плавно и навсегда.
  void _toggleLike(AiMessage m) {
    final k = _msgKey(m);
    setState(() {
      if (_liked.contains(k)) {
        _liked.remove(k);
      } else {
        _liked.add(k);
      }
    });
    _saveLiked();
    // Ада «запоминает» стиль/содержание лайкнутого ответа и подстраивается
    // под него в следующих сообщениях (паттерн живёт в системном промпте).
    if (!m.isUser) {
      AiGuideService.rememberLikedPattern(m.text);
    }
    Haptics.select();
  }

  bool _isPinned(AiMessage m) =>
      _pinned.any((p) => p.text == m.text && p.isUser == m.isUser);

  /// Копировать сообщение Ады — всегда доступно кнопкой на пузыре, даже если
  /// системный тулбар выделения не появился.
  Future<void> _copyMessage(AiMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t('copied', context, 'Скопировано'),
      icon: Icons.copy,
      iconColor: Colors.lightBlueAccent,
      groupKey: 'ada_copy',
    );
  }

  /// Зажать сообщение Ады — закрепить (плавно уезжает вверх, до 10 штук).
  /// Повторное зажатие открепляет.
  void _togglePin(AiMessage m) {
    if (m.isUser) return;
    var limitHit = false;
    setState(() {
      final idx = _pinned.indexWhere(
        (p) => p.text == m.text && p.isUser == m.isUser,
      );
      if (idx >= 0) {
        _pinned.removeAt(idx);
      } else if (_pinned.length < _maxPins) {
        _pinned.add(m);
      } else {
        limitHit = true;
      }
    });
    _savePins();
    if (limitHit) {
      // Лимит 10: ничего не стираем, просто мягко подсказываем.
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'pinLimit',
          context,
          'You can pin up to 10 messages',
        ),
        icon: Icons.push_pin_outlined,
        iconColor: Theme.of(context).colorScheme.primary,
        groupKey: 'ada_pin_limit',
      );
      Haptics.select();
    }
  }

  void _scrollToBottom({bool animate = true}) {
    // Лента с reverse:true — индекс 0 это низ чата, открытие сразу
    // показывает последнее сообщение БЕЗ итеративных прыжков (раньше
    // цикл сходимости из 14 jumpTo дёргал layout и «лагал» появление).
    // Новые сообщения появляются у низа автоматически; animate — плавный
    // возврат к низу, если пользователь листал историю вверх.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (animate) {
        if (pos.pixels > 4) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (pos.pixels > 0) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  String _friendlyAiError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return 'Ада не успела получить ответ. Попробуй ещё раз через мгновение.';
    }
    if (raw.contains('429') || raw.contains('rate')) {
      return 'Ада сейчас занята — я уже попробую другой бесплатный канал.';
    }
    if (raw.contains('все провайдеры') || raw.contains('unavailable')) {
      return 'Все бесплатные каналы сейчас недоступны. Проверь интернет — '
          'или вставь свой ключ Poolside в настройках, и нажми «обновить».';
    }
    return 'Связь с Адой прервалась. Нажми обновить — я попробую снова.';
  }

  /// Отправляет сообщение. [text] — если null, берём из поля ввода.
  /// Мелкий круглый значок веб-поиска: листается вместе с таблетками
  /// (вставлен первым элементом в горизонтальный список), включается и
  /// выключается плавно — заливается фирменным цветом, появляется
  /// свечение, иконка мягко меняется (fade + лёгкий scale БЕЗ перелёта).
  /// Фон свой (нейтральный), НЕ таблетный — значок всегда различим.
  Widget _buildWebSearchToggle(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    return SmoothTooltip(
      message: Translations.t(
        _webSearch ? 'aiWebSearchOn' : 'aiWebSearch',
        context,
        _webSearch ? 'Web search ON' : 'Web search',
      ),
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.light();
          setState(() {
            _webSearch = !_webSearch;
            try {
              globalPrefs.setBool('ai_web_search', _webSearch);
            } catch (_) {}
          });
        },
        child: ClipOval(
          // ClipOval: иконка при анимации НИКОГДА не вылезает за круг.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // «Стеклянный» круг под стать чату: выключен — полупрозрачная
              // поверхность (сквозь неё видно размытый фон листа) с тонкой
              // кромкой; включён — заливается фирменным градиентом.
              shape: BoxShape.circle,
              gradient: _webSearch
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary,
                        Color.lerp(cs.primary, cs.tertiary, 0.4)!,
                      ],
                    )
                  : null,
              color: _webSearch ? null : cs.surface.withValues(alpha: 0.55),
              border: Border.all(
                color: _webSearch
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.65),
                width: 1.3,
              ),
              boxShadow: _webSearch
                  ? [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              // Только fade, БЕЗ scale: иконка не увеличивается и не
              // «заезжает за границы» при переключении.
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Icon(
                _webSearch ? Icons.travel_explore : Icons.public,
                key: ValueKey('web_toggle_icon_$_webSearch'),
                size: 19,
                color: _webSearch ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Включает/выключает «контекст экрана». Значок включается ТОЛЬКО когда
  /// системное разрешение «Специальные возможности» реально выдано: без
  /// него значок не остаётся включённым (нельзя обещать «Ада видит экран»,
  /// если сервис не работает).
  Future<void> _toggleScreenAware(BuildContext context) async {
    Haptics.light();
    if (_screenAware) {
      // Выключение — мгновенное.
      setState(() => _screenAware = false);
      try {
        globalPrefs.setBool(ScreenReaderService.prefKey, false);
      } catch (_) {}
      return;
    }
    // Включение: сначала проверяем реальное разрешение.
    final hasPerm = await ScreenReaderService.hasPermission();
    if (!mounted || !context.mounted) return;
    if (hasPerm) {
      setState(() => _screenAware = true);
      try {
        await globalPrefs.setBool(ScreenReaderService.prefKey, true);
      } catch (_) {}
      return;
    }
    // Разрешения нет — объясняем и ведём в настройки. Значок при этом
    // НЕ включается: вернёшься с выданным разрешением — включится сам
    // (didChangeAppLifecycleState → _refreshScreenPerm).
    final cs = Theme.of(context).colorScheme;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.visibility_outlined, size: 44, color: cs.primary),
        title: const Text('Ада видит экран'),
        content: const Text(
          'Чтобы Ада могла подсказать ответ собеседнику (например, в '
          'мессенджере), разреши Keramika «Специальные возможности».\n\n'
          'Текст экрана не сохраняется и никуда не отправляется — он '
          'попадает в Аду только вместе с твоим сообщением.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Не сейчас'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await ScreenReaderService.openSystemSettings();
    }
  }

  /// Таблетка «контекст экрана»: Ада видит текст активного окна другого
  /// приложения (мессенджер, браузер) и может подсказать ответ собеседнику.
  /// Стиль — как у веб-поиска, но пилюля с «глазом» и живой точкой:
  /// включено — заливается фирменным цветом и пульсирует зелёной точкой
  /// (если разрешение доступно), выключено — нейтральное.
  Widget _buildScreenToggle(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    return SmoothTooltip(
      message: _screenAware
          ? 'Контекст экрана: включён — Ада видит текст на экране'
          : 'Контекст экрана: выключен — Ада не читает экран',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggleScreenAware(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            color: Colors.transparent,
            border: Border.all(
              color: _screenAware
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: _screenAware
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Icon(
                  _screenAware ? Icons.visibility : Icons.visibility_outlined,
                  key: ValueKey('screen_toggle_icon_$_screenAware'),
                  size: 19,
                  color: _screenAware ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              // «Живая» точка: зелёная, когда контекст экрана активен.
              if (_screenAware)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF4CD964),
                      border: Border.all(color: cs.surface, width: 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// [keepUserBubble] — true при повторной отправке с плашки «ИИ на курорте»:
  /// сообщение уже на экране, дубликат не добавляем.
  Future<void> _send({String? text, bool keepUserBubble = false}) async {
    final message = (text ?? _inputCtrl.text).trim();
    if (message.isEmpty || _busy) return;
    // Поколение на момент отправки: если чат очистят, пока Ада думает,
    // ответ не попадёт в пустой чат.
    final gen = adaChatGeneration;
    Haptics.light();
    _inputCtrl.clear();
    setState(() {
      // Лимит чата: 1000 сообщений, дальше — стереть и начать новый диалог.
      if (_messages.length >= 1000) _messages.clear();
      if (!keepUserBubble) {
        _messages.add(
          AiMessage(
            isUser: true,
            text: message,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
      // Горячий стрик: первое сообщение нового дня растит счётчик, и Ада
      // подкидывает в чат горячую фразу (не чаще раза в день).
      unawaited(AiGuideService.bumpAdaStreak());
      _busy = true;
      _error = false;
    });
    _dotsCtrl.repeat();
    _saveHistory();
    _scrollToBottom();
    try {
      final answer = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: _lang,
        useWebSearch: _webSearch,
        screenContext: _screenAware
            ? await ScreenReaderService.snapshot()
            : null,
      );
      // Чат успели очистить, пока Ада думала — ответ выбрасываем.
      if (!mounted || gen != adaChatGeneration) return;
      // Эстафета «печатает…» → ответ: индикатор плавно гаснет, и только
      // потом ответ всплывает (его собственная анимация входа).
      _dotsCtrl.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 210));
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        // Пустой ответ («три точки») никогда не показываем — вместо него
        // запасная фраза, чтобы не выглядело, будто Ада «промолчала».
        final finalText = answer.trim().isEmpty
            ? Translations.t(
                'aiEmptyAnswer',
                context,
                'Хм, я не смогла собрать ответ. Попробуй ещё раз!',
              )
            : answer;
        _messages.add(
          AiMessage(
            isUser: false,
            text: finalText,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        if (_messages.length > 1000) {
          _messages.removeRange(0, _messages.length - 1000);
        }
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      AiGuideService.hfRemainingToday().then((n) {
        if (mounted) setState(() => _quotaLeft = n);
      });
      _refreshModelLabel();
      // Синхронизируем «кто ответил» с мини-окошком (отдельный движок).
      final used = AiGuideService.lastUsedModel;
      if (used.isNotEmpty) {
        writeAdaSyncState(model: used);
      }
      _scrollToBottom();
    } catch (e) {
      if (!mounted || gen != adaChatGeneration) return;
      _dotsCtrl.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 210));
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _busy = false;
        _error = true;
        _errorMsg = _friendlyAiError(e);
        _typingFade = false;
      });
      _scrollToBottom();
      // Плашка «ИИ на курорте» остаётся видимой, пока пользователь не
      // нажмёт «обновить» или не отправит новое сообщение: иначе при
      // медленной/заблокированной сети создаётся впечатление, что Ада
      // «просто не ответила на сообщение».
      // (Скрывается в начале _send при новом сообщении: _error = false.)
    }
  }

  /// Кнопка «Повторить» на плашке: переотправляет ПОСЛЕДНЕЕ сообщение
  /// пользователя БЕЗ дубликата — пузырь остаётся на месте, плашка гаснет,
  /// идёт новая отправка того же текста.
  void _retryLast() {
    final lastUser = _messages.lastWhere(
      (m) => m.isUser,
      orElse: () => AiMessage(isUser: true, text: ''),
    );
    if (lastUser.text.isEmpty) return;
    setState(() => _error = false);
    _send(text: lastUser.text, keepUserBubble: true);
  }

  /// «Отменить последнее действие» — удаляет созданное Адой или
  /// восстанавливает удалённое. Результат появляется в чате как ответ Ады.
  Future<void> _undoLast() async {
    final result = await AiGuideService.undoLastAction();
    if (!mounted) return;
    setState(() {
      _messages.add(
        AiMessage(
          isUser: false,
          text: result,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
    _saveHistory();
    _scrollToBottom();
  }

  /// Плавная очистка всего чата: список гаснет (350мс), потом стирается.
  void _clearChat() {
    if (_messages.isEmpty && !_busy) return;
    if (_clearCtrl.isAnimating) return;
    // Старые «летящие» ответы больше не имеют права вернуться в пустой чат.
    adaChatGeneration++;
    _clearCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _busy = false;
        _error = false;
      });
      _dotsCtrl.stop();
      _saveHistory();
      _clearCtrl.reset();
    });
  }

  /// Свернуть чат в плавающее окошко / выключить окошко (обратное нажатие).
  ///
  /// На Android — СИСТЕМНЫЙ оверлей поверх ДРУГИХ приложений (живёт даже
  /// после выхода из приложения): сначала окно-чат, тап по «Ада, ничего
  /// не надо» сворачивает его в пузырь, который сам катается по экрану.
  /// На web — внутриприложенный пузырь (плагин оверлея не поддерживает web).
  Future<void> _toggleFloating() async {
    final next = !aiFloating.value;
    if (next) {
      if (!kIsWeb) {
        // Android: сразу показываем системный оверлей (с запросом
        // разрешения «поверх других приложений», если его ещё нет).
        final ctx = context;
        final dpr = View.of(ctx).devicePixelRatio;
        final size = MediaQuery.sizeOf(ctx);
        final shown = await ensureAdaOverlay(
          devicePixelRatio: dpr,
          screenWidth: size.width,
          screenHeight: size.height,
          // Верхний запретный пояс (статус-бар + шапка + таблетка
          // разделов): окно Ады лежит НАД приложением, и без него при
          // перетаскивании вверх окошко залезало на категории.
          topKeepout: adaTopKeepout(MediaQuery.paddingOf(ctx).top),
        );
        if (!shown) {
          // Разрешение не дали — показываем подсказку и остаёмся в чате.
          if (ctx.mounted) {
            showBeautifulSnackBar(
              ctx,
              message: Translations.t(
                'aiOverlayPermissionHint',
                ctx,
                'Allow Keramika to draw over other apps to enable the mini window',
              ),
              icon: Icons.warning_amber_rounded,
              iconColor: Theme.of(ctx).colorScheme.error,
              duration: const Duration(seconds: 3),
              groupKey: 'ada_window',
            );
          }
          return;
        }
      }
      aiFloating.value = true;
      globalPrefs.setBool('ai_floating', true);
      // Свернули — закрываем чат (на Android живёт системный оверлей,
      // на web — внутренний пузырь).
      if (!mounted) return;
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'aiWindowHint',
          context,
          'Collapsed to a mini window — tap it to return',
        ),
        icon: Icons.picture_in_picture_alt_outlined,
        iconColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
        groupKey: 'ada_window',
      );
      if (mounted && context.mounted) Navigator.pop(context);
    } else {
      // Выключили — окошко исчезает, чат остаётся открытым.
      aiFloating.value = false;
      globalPrefs.setBool('ai_floating', false);
      if (!kIsWeb) await closeAdaOverlay();
    }
  }

  /// Открепить сообщение (тап на крестик в панели закреплённых).
  void _unpin(AiMessage m) {
    setState(() {
      _pinned.removeWhere((p) => p.text == m.text && p.isUser == m.isUser);
    });
    _savePins();
  }

  /// Награды Ады (стрики, все задачи выполнены) появляются в чате первым
  /// сообщением при открытии. Каждая награда выдаётся только один раз.
  Future<void> _claimRewards() async {
    try {
      final rewards = await AiGuideService.collectRewards(_lang);
      if (!mounted || rewards.isEmpty) return;
      setState(() {
        for (final r in rewards) {
          _messages.add(
            AiMessage(
              isUser: false,
              text: r,
              ts: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
      });
      _saveHistory();
      _scrollToBottom();
    } catch (_) {
      // Награды — не критично: сбой не должен ронять чат.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Тело чата НЕ читает viewInsets: клавиатуру обслуживает лёгкая
    // оболочка _AiChatSheet. Здесь — только содержимое, которое
    // пересобирается по собственным setState, а не при каждом кадре
    // анимации клавиатуры. Лента дополнительно изолирована
    // (RepaintBoundary + removeViewInsets в _buildMessages).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ручка.
        Container(
          margin: const EdgeInsets.only(top: 10),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Шапка — Ада. Тап по имени/аватарке меняет её значок.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cycleAvatar,
                // Живой слушатель adaAvatarVariant: смена значка из ЛЮБОГО
                // места (тап по сердечку у сообщений, шапка, мини-чат)
                // мгновенно и плавно обновляет аватарку в шапке.
                child: ValueListenableBuilder<int>(
                  valueListenable: adaAvatarVariant,
                  builder: (context, idx, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: AdaAvatar(
                      variantIndex: idx,
                      key: ValueKey('ada_avatar_$idx'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _cycleAvatar,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Строка 1: «Ада, ничего не надо».
                      Text(
                        '${Translations.t('adaName', context, 'Ада')}, '
                        '${Translations.t('adaTagline', context, 'ничего не надо')}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // Строка 2: кто ответил и какая модель —
                      // Kilo, OVHcloud или AI Horde.
                      // Переключается плавно при смене провайдера.
                      // Стрик переехал в подсказку пустого чата (мельче
                      // и красивее) — в шапке осталась только модель.
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  sizeFactor: animation,
                                  alignment: AlignmentDirectional.topStart,
                                  child: child,
                                ),
                              ),
                          child: ModelLabel(
                            key: const ValueKey('model_label_stable'),
                            label: _modelLabel,
                            details: AiGuideService.providerTrace.value.join(
                              '\n',
                            ),
                            textStyle: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Кнопка очистки чата. Без серой подсветки при наведении.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearChat,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.delete_sweep_outlined,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              // Свернуть чат в плавающее окошко (режим «в окне»).
              ValueListenableBuilder<bool>(
                valueListenable: aiFloating,
                builder: (context, floating, _) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleFloating,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      floating
                          ? Icons.picture_in_picture_alt
                          : Icons.picture_in_picture_alt_outlined,
                      size: 22,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Закреплённые сообщения Ады — живут над чатом, не стираются
        // очисткой. Открепляются тапом на крестик.
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.35),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _pinned.isEmpty
                ? const SizedBox(
                    key: ValueKey('pins_none'),
                    width: double.infinity,
                  )
                : _PinnedBar(
                    key: const ValueKey('pins_bar'),
                    pinned: _pinned,
                    onUnpin: _unpin,
                  ),
          ),
        ),
        // Сообщения (гаснут при очистке).
        //
        // Лента изолирована от изменений MediaQuery (RepaintBoundary +
        // MediaQuery.removeViewInsets): при поднятии/опускании клавиатуры
        // viewInsets меняются покадрово, и БЕЗ изоляции тяжёлая лента
        // (сотни сообщений) пересобиралась на каждом кадре — отсюда
        // «дёрганое тормозное» поднятие клавиатуры в чате. Теперь
        // двигается только лёгкая оболочка (Padding + Container), а лента
        // остаётся готовой текстурой.
        Expanded(
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _clearCtrl,
                builder: (context, child) =>
                    Opacity(opacity: 1.0 - _clearCtrl.value, child: child),
                // Stack: лента ВСЕГДА на месте, подсказка поверх с
                // AnimatedOpacity. БЕЗ AnimatedSwitcher — при стирании чата
                // и при первом сообщении не мигает (не было двойного fade
                // «лента гаснет + подсказка вспыхивает»).
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListView.builder(
                      controller: _scrollCtrl,
                      // reverse:true — индекс 0 это НИЗ чата: открытие сразу
                      // показывает последние сообщения, никаких прыжков.
                      reverse: true,
                      // bottom: 112 — статичный запас под полем ввода:
                      // последнее сообщение не ложится вровень с полем.
                      // Паддинг не зависит от клавиатуры — лента не
                      // пересчитывается при её анимации.
                      padding: const EdgeInsets.only(
                        left: 14,
                        right: 14,
                        top: 12,
                        bottom: 116,
                      ),
                      itemCount: _messages.length + (_busy ? 1 : 0),
                      // Элементы уже обёрнуты в RepaintBoundary ниже;
                      // не добавляем вторую границу для каждого пузыря.
                      addRepaintBoundaries: false,
                      itemBuilder: (context, i) {
                        if (_busy && i == 0) {
                          // «Печатает…» — самый нижний элемент, прямо у поля.
                          // AnimatedOpacity: при ответе индикатор плавно гаснет,
                          // а не выпадает резко (см. _typingFade в _send).
                          return AnimatedOpacity(
                            opacity: _typingFade ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, child) => Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: 0.7 + 0.3 * t,
                                  child: child,
                                ),
                              ),
                              child: _TypingIndicator(animation: _dotsCtrl),
                            ),
                          );
                        }
                        // Индекс в исходном массиве (0 = последнее сообщение).
                        final mi = _busy
                            ? _messages.length - i
                            : _messages.length - 1 - i;
                        final m = _messages[mi];
                        // Сосед ВЫШЕ в ленте (следующий по истории).
                        final above = mi + 1 < _messages.length
                            ? _messages[mi + 1]
                            : null;
                        // Анимация входа — ТОЛЬКО у сообщений, добавленных
                        // ПОСЛЕ открытия чата (последние 3 из них). Сообщения
                        // истории при открытии НЕ анимируются: лист уже выезжает,
                        // и пузыри не «прыгают» поверх. Также не анимируются
                        // старые пузыри при скролле большого чата.
                        final isNew = mi >= _openedCount;
                        final animate = isNew && mi >= _messages.length - 3;
                        // Моё сообщение «прочитано», когда сразу за ним в
                        // истории идёт ответ Ады (она обработала сообщение).
                        // Время прочтения — метка ответа Ады.
                        final read =
                            m.isUser &&
                            mi + 1 < _messages.length &&
                            !_messages[mi + 1].isUser;
                        final readAt = read ? _messages[mi + 1].ts : null;
                        return RepaintBoundary(
                          key: ValueKey('msg_layer_$mi'),
                          child: _MessageBubble(
                            key: ValueKey('msg_$mi'),
                            message: m,
                            firstInGroup:
                                above == null || above.isUser != m.isUser,
                            animate: animate,
                            read: read,
                            readAt: readAt,
                            liked: _liked.contains(_msgKey(m)),
                            pinned: _isPinned(m),
                            onToggleLike: () => _toggleLike(m),
                            onCopy: () => _copyMessage(m),
                            // Зажать аватарку Ады — закрепить/открепить (до 10).
                            onLongPress: m.isUser ? null : () => _togglePin(m),
                            onTogglePin: m.isUser ? null : () => _togglePin(m),
                            onCycleAvatar: _cycleAvatar,
                          ),
                        );
                      },
                    ),
                    // Подсказка пустого чата: плавно появляется, когда
                    // сообщений нет, и гаснет при первом сообщении.
                    AnimatedOpacity(
                      opacity: _messages.isEmpty && !_busy ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !(_messages.isEmpty && !_busy),
                        child: const _EmptyChatPlaceholder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Плашка «ИИ на курорте» (с кодом ошибки для диагностики).
        _AnimatedErrorPlaque(
          visible: _error,
          errorMsg: _errorMsg,
          onRetry: _retryLast,
        ),
        // Быстрые действия: чип заполняет поле ввода шаблоном — дальше
        // локальный парсер выполнит команду мгновенно, без сети.
        _QuickChips(
          // Значки веб-поиска и контекста экрана — первые элементы
          // списка, листаются вместе с таблетками (не приклеены
          // столбом слева).
          leading: [
            _buildWebSearchToggle(context, theme),
            _buildScreenToggle(context, theme),
          ],
          onTap: (template) {
            _inputCtrl.text = template;
            _inputCtrl.selection = TextSelection.collapsed(
              offset: _inputCtrl.text.length,
            );
            _inputFocus.requestFocus();
          },
        ),
        // Подсказка про лимит Ады.
        if (_quotaLeft > 0 && _quotaLeft <= 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: Color(0xFFB06AB3),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: ClipRect(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final t = Curves.easeOutCubic.transform(
                          animation.value,
                        );
                        return FadeTransition(
                          opacity: animation,
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - t)),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        Translations.t(
                          'adaQuota',
                          context,
                          'Ada: N free left today',
                        ).replaceFirst('N', '$_quotaLeft'),
                        key: ValueKey('quota_$_quotaLeft'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // «Отменить последнее действие» — появляется/исчезает плавно
        // после того, как Ада что-то создала или удалила.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              alignment: AlignmentDirectional.topCenter,
              child: child,
            ),
          ),
          child: (AiGuideService.lastAction == null || _busy)
              ? const SizedBox.shrink(key: ValueKey('undo_none'))
              : Padding(
                  key: const ValueKey('undo_chip'),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.undo, size: 16),
                      label: Text(
                        '${Translations.t('aiUndo', context, 'Undo')}: '
                        '${AiGuideService.lastAction!.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _busy ? null : _undoLast,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(
                        color: cs.primary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
        ),
        // Поле ввода.
        SafeArea(
          top: false,
          child: RepaintBoundary(
            // Поле имеет постоянный размер при движении IME. Отдельный
            // слой позволяет сдвигать его вместе с листом без полной
            // перерисовки поля на каждом кадре клавиатуры.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                children: [
                  Expanded(
                  // Обводка поля плавно «разгорается» при фокусе и гаснет
                  // при снятии (короткая 220мс анимация, чтобы не тормозить
                  // клавиатуру, но и не «щёлкать» цветом).
                  child: AnimatedBuilder(
                    animation: _focusAnim,
                    builder: (context, child) {
                      final t = Curves.easeOutCubic.transform(_focusAnim.value);
                      return Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Color.lerp(
                              cs.outlineVariant.withValues(alpha: 0.4),
                              cs.primary.withValues(alpha: 0.7),
                              t,
                            )!,
                            width: 1.5 + t * 0.4,
                          ),
                        ),
                        child: child,
                      );
                    },
                    child: Stack(
                      children: [
                        // Каждую букву рисует SmoothTyping: она проявляется
                        // из пустоты и плавно гаснет при стирании. Само поле
                        // ниже — прозрачное, оно отвечает за каретку,
                        // выделение и клавиатуру.
                        SmoothTyping(
                          controller: _inputCtrl,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.4,
                            color: cs.onSurface,
                          ),
                          builder: (style) => TextField(
                            style: style,
                            magnifierConfiguration:
                                TextMagnifierConfiguration.disabled,
                            controller: _inputCtrl,
                            focusNode: _inputFocus,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 13000,
                            inputFormatters: [WideDashFormatter()],
                            // Отключаем автоподсказки/автокоррекцию
                            // клавиатуры: Gboard/MIUI добавляет свой
                            // автопробел после выбранного слова — отсюда
                            // «пробел в конце».
                            enableSuggestions: false,
                            autocorrect: false,
                            // Меню при зажатии: только Копировать/Вставить/
                            // Вырезать/Курсив — без «Поделиться»,
                            // «Спросить Copilot» и лишних пунктов.
                            contextMenuBuilder: minimalContextMenuBuilder,
                            // Не запускать дополнительный автоскролл
                            // EditableText при каждом кадре IME: лист уже
                            // сам двигается.
                            scrollPadding: EdgeInsets.zero,
                            cursorColor: cs.primary,
                            // Каретка мигает ПЛАВНО (fade-переход, а не
                            // резкое вкл/выкл) — «палка» не дёргается.
                            cursorOpacityAnimates: true,
                            decoration: InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        // Плавная подсказка «Спроси меня»: гаснет, когда
                        // начинаешь вводить, и мягко возвращается, когда
                        // поле пустое — вместо резкого щелчка.
                        IgnorePointer(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _inputCtrl,
                            builder: (context, v, _) => AnimatedOpacity(
                              opacity: v.text.isEmpty ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                child: Text(
                                  Translations.t(
                                    'aiGuideHint',
                                    context,
                                    'Ask me…',
                                  ),
                                  style: TextStyle(
                                    fontSize: 18,
                                    height: 1.4,
                                    color: cs.onSurfaceVariant.withValues(
                                      alpha: 0.8,
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
                ),
                const SizedBox(width: 8),
                _SendButton(busy: _busy, onTap: () => _send()),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Подсказка в пустом чате: ПО ЦЕНТРУ, две строки жирным, с переводом.
/// Под текстом — горячий стрик общения с Адой (мелкий огонёк с числом
/// дней подряд): не мусорит в шапке, живёт только в пустом чате.
