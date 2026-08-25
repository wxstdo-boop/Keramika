import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../utils/markdown_text.dart';
import '../services/ai_guide_service.dart';
import '../services/json_file.dart';
import '../services/prefs.dart';
import '../services/settings_service.dart';
import '../widgets/ada_avatars.dart';

/// Канал системного оверлея.
const MethodChannel _overlayChannel = MethodChannel('x-slayer/overlay');

/// Размеры окна оверлея (dp). Окно почти квадратное — «не вдлину»:
/// 320×360 (было 340×380, раньше 280×440 — вытянутое).
// Пузырь компактный (40): не перекрывает контент под ним.
// Чат-окно тоже чуть меньше — аккуратнее поверх чужого приложения.
const double _bubbleSize = 36;
const double _chatWidth = 292;
const double _chatHeight = 330;

/// Точка входа для главного приложения: движок оверлея переживает закрытие
/// окна, поэтому при каждом показе окна мы посылаем команду «сбросься и
/// покажись» — только так повторное открытие гарантированно видимо.
/// (lifecycle-события могут не долететь до вторичного движка.)
void resetOverlayFromHost() => _OverlayChatState.onHostReset();

/// Живая синхронизация аватарки из ГЛАВНОГО чата (отдельный движок).
void syncOverlayAvatarFromHost(int variant) =>
    _OverlayChatState.onAvatarSynced(variant);

/// Живая синхронизация модели из ГЛАВНОГО чата (отдельный движок).
void syncOverlayModelFromHost(String label) =>
    _OverlayChatState.onModelSynced(label);

class AdaOverlayApp extends StatefulWidget {
  const AdaOverlayApp({super.key});

  @override
  State<AdaOverlayApp> createState() => _AdaOverlayAppState();
}

class _AdaOverlayAppState extends State<AdaOverlayApp> {
  String _lang = 'en';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await initPrefs();
    final lang = await SettingsService.resolveLanguageCode();
    if (!mounted) return;
    setState(() {
      _lang = lang;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    // Окошко ВСЕГДА тёмное: фон чёрный с прямыми углами, поэтому даже при
    // светлой теме приложения контраст текста внутри не ломается.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Прозрачный фон под всей аппкой: именно canvasColor/backgroundColor
      // Material рисовал непрозрачным прямоугольником ЗА нашим скруглённым
      // шеллом — отсюда «квадратные углы» на фоне. Теперь за скруглением
      // виден настоящий экран.
      color: Colors.transparent,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: ThemeData.dark().colorScheme.copyWith(
          surface: Colors.transparent,
        ),
      ),
      home: LocaleProvider(locale: Locale(_lang), child: const _OverlayChat()),
    );
  }
}

class _OverlayChat extends StatefulWidget {
  const _OverlayChat();
  @override
  State<_OverlayChat> createState() => _OverlayChatState();
}

class _OverlayChatState extends State<_OverlayChat>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Живой экземпляр состояния (в движке оверлея он один и переживает
  /// закрытие окна). [onHostReset] вызывается из ГЛАВНОГО приложения по
  /// каналу сообщений — переоткрытие окна не зависит от lifecycle.
  static _OverlayChatState? _live;
  /// Первое появление (initState) НЕ должно повторять сброс: lifecycle
  /// «resumed» приходит на старте движка ДО первого кадра, и повторный
  /// сброс съедал плавный вход (fade успевал закончиться до показа).
  bool _initialized = false;

  /// Живая синхронизация из ГЛАВНОГО чата: аватарка сменилась там —
  /// меняем здесь МГНОВЕННО, без переоткрытия окна (отдельный движок,
  /// поэтому прямой вызов невозможен, только сообщение по мосту).
  static void onAvatarSynced(int variant) {
    final s = _live;
    if (s == null || !s.mounted) return;
    final v = variant.clamp(0, adaVariants.length - 1);
    if (v == s._avatarVariant) return;
    s.setState(() => s._avatarVariant = v);
    setAdaAvatarVariant(v);
  }

  /// Живая синхронизация модели из ГЛАВНОГО чата: какой провайдер ответил
  /// там — такой же лейбл показываем и в мини-окошке.
  static void onModelSynced(String label) {
    final s = _live;
    if (s == null || !s.mounted || label.isEmpty) return;
    if (s._modelLabel == label) return;
    s.setState(() => s._modelLabel = label);
  }

  /// Сброс из основного окна: окно пересоздано — привести к состоянию
  /// «только что открылся» и НАЧАТЬ появление заново. Важно: команда
  /// приходит ДО того, как новое окно реально появилось (движок живёт
  /// отдельно), поэтому мгновенный forward закончится ещё до открытия —
  /// окно выскочило бы без фейда. Ставим прозрачность в 0 и запускаем
  /// появление с задержкой, когда окно уже на экране.
  static void onHostReset() {
    final s = _live;
    if (s == null || !s.mounted) return;
    s._inputFocus.unfocus();
    s._stopDrift();
    s.setState(() {
      s._closing = false;
      s._inputFocused = false;
      s._collapsed = false;
    });
    // Приглушаем ДО нуля: даже если окно мгновенно появится, оно не
    // «вспыхнет» — fade стартует через момент.
    s._appearCtrl.value = 0;
    s._contentCtrl.value = 0;
    // НЕ ставим позицию в центр: синхронизацию делает _load() с нативным
    // getOverlayPosition (иначе окно «жило» в центре, хотя было вверху,
    // и первый сдвиг прыгал в центр — это и казалось «следом»).
    s._load();
    // Окно появляется через ~300-400 мс после команды (пересоздание
    // сервиса). Запускаем анимацию именно тогда.
    s._appearTimer?.cancel();
    s._appearTimer = Timer(const Duration(milliseconds: 350), () {
      if (!s.mounted) return;
      s._appearCtrl.forward(from: 0);
      s._contentCtrl.forward(from: 0);
      s._clampToScreen();
    });
  }

  static const _historyKey = 'ai_chat_history';

  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  final List<AiMessage> _messages = [];
  bool _busy = false;
  bool _typingFade = false;
  bool _collapsed = false; // Стартуем как ЧАТ.
  bool _closing = false;
  bool _resizing = false;
  bool _inputFocused = false;
  String _modelLabel = '';
  int _avatarVariant = 0;
  // Сколько сообщений было при открытии: только новые анимируют вход,
  // иначе при появлении окошка вся история «вспыхивала» поверх.
  int _openedCount = 0;

  late final AnimationController _appearCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final AnimationController _contentCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  Timer? _appearTimer;
  Timer? _syncTimer;

  // ── Позиция окна ──────────────────────────────────────────────────
  // Пузырь ЛЕТАЕТ САМ по экрану (пользователь просил вернуть).
  // Движение плавное: тики синхронизированы с vsync (Ticker), без
  // таймерных гонок; при касании дрейф мгновенно встаёт (не спорит
  // с пальцем) и плавно возобновляется после отпускания.
  Ticker? _driftTicker;
  double _vx = 0.8;
  double _vy = 0.6;
  Offset _pos = Offset.zero;

  // Сгладить первое поднятие клавиатуры: лента и без того изолирована
  // от viewInsets (MediaQuery.removeViewInsets), поэтому тяжёлого
  // пересборки нет; здесь же обеспечиваем мягкий старт — при появлении
  // фокуса делаем jumpTo(0) БЕЗ анимации (иначе «первое поднятие»
  // тормозило анимацией скролла вместе с выездом клавиатуры).
  @override
  void initState() {
    super.initState();
    _live = this;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _inputFocus.addListener(_onFocusChange);
    // Стартовый fade: onHostReset (command от main при первом open) или
    // lifecycle resumed. Страховка — свой таймер: если ни та, ни другая
    // команда не пришла, окно ВСЁ РАВНО плавно появится через ~300мс
    // (иначе навсегда висел «полупрозрачный след чата» при прозрачности 0).
    _appearCtrl.value = 0;
    _contentCtrl.value = 0;
    _appearTimer?.cancel();
    _appearTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _appearCtrl.forward(from: 0);
      _contentCtrl.forward(from: 0);
    });
    // Опрос файла синхронизации с ГЛАВНЫМ чатом: аватарка/модель меняются
    // в мини-окошке при ближайшем тике (~0.7с). Праксис надёжнее канала
    // сообщений между двумя движками (prefs кэшируется отдельно).
    _syncTick();
    _syncTimer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _syncTick(),
    );
  }

  Future<void> _syncTick() async {
    try {
      final s = await readAdaSyncState();
      if (s.isEmpty) return;
      final av = s['avatar'];
      if (av is int && av >= 0 && av != _avatarVariant) {
        final v = av.clamp(0, adaVariants.length - 1);
        if (mounted) setState(() => _avatarVariant = v);
        setAdaAvatarVariant(v);
      }
      final m = s['model'];
      if (m is String && m.isNotEmpty && m != _modelLabel) {
        if (mounted) setState(() => _modelLabel = m);
      }
    } catch (_) {}
  }

  // Оверлей рендерится в КЭШИРОВАННОМ движке: после закрытия окна Dart-
  // состояние чата остаётся живым, и второе открытие подхватывает
  // «хвосты» сессии (_closing=true и т.п.). При каждом перезапуске окна
  // (сервис зовёт appIsResumed → resumed) — сбрасываем всё и плавно
  // проигрываем появление заново.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Окно пересоздано/возвращено — то же самое, что и команда сброса
    // с главного экрана: приводим состояние и плавно показываемся.
    if (state == AppLifecycleState.resumed) {
      if (_initialized) {
        _initialized = false;
        return; // первый resumed при старте — не трогаем
      }
      onHostReset();
    }
  }

  // Сгладить первое поднятие клавиатуры: лента изолирована от viewInsets
  // (MediaQuery.removeViewInsets), поэтому пересборки нет. При фокусе
  // досматриваем вниз БЕЗ анимации (jumpTo) — но только если последнее
  // сообщение реально ушло из виду (иначе каждый фокус дёргал ленту).
  void _onFocusChange() {
    if (!mounted) return;
    final f = _inputFocus.hasFocus;
    if (f != _inputFocused) {
      _inputFocused = f;
      // Окно при фокусе не трогаем: фокусируемость включает onTap поля
      // (с ожиданием ответа натива), а при ПОТЕРЕ фокуса возвращаем окну
      // NOT_FOCUSABLE — жест «назад» снова работает в основном приложении,
      // и следующий тап по полю снова включает IME с первого раза.
      if (!f) _setFocusable(false);
      // Окно при фокусе НЕ поднимаем: оно живёт поверх клавиатуры, и
      // пользователь сам двигает его куда. Просто прокручиваем ленту
      // к последнему сообщению, чтобы оно не пряталось под полем.
      if (f && _scrollCtrl.hasClients) {
        final pos = _scrollCtrl.position;
        if (pos.maxScrollExtent > 0 &&
            pos.pixels < pos.maxScrollExtent - 16) {
          _scrollCtrl.jumpTo(pos.maxScrollExtent);
        }
      }
    }
  }

  /// Меняет флаг фокусируемости окна. Дождаться ответа натива ВАЖНО:
  /// requestFocus сразу после смены флага «съедался», и клавиатура
  /// появлялась только со второго тапа.
  Future<void> _setFocusable(bool focus) async {
    try {
      await _overlayChannel.invokeMethod<void>('updateFlag', {
        'flag': focus ? 'focusPointer' : 'defaultFlag',
      });
      // Натив обновляет LayoutParams асинхронно (updateViewLayout): даём
      // ему кадр-другой, иначе первый requestFocus может «съесть» флаг.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    } catch (_) {}
  }

  // ── Drag оверлея ──────────────────────────────────────────────────
  // Драг работает по всей зоне (пузырь и чат). Дельты копятся в _pos,
  // а на нативную сторону позиция уходит РОВНО РАЗ В КАДР (синхронно с
  // vsync через addPostFrameCallback) — телефон успевает отрисовать
  // каждое положение без гонки между таймером (16мс) и кадрами, которая
  // давала «дёрганье» (то двойная отправка, то пропуск).
  bool _dragging = false;
  bool _sendScheduled = false;
  bool _nativeMoveInFlight = false;
  Offset? _pendingNativePosition;

  void _scheduleSend() {
    if (_sendScheduled) return;
    _sendScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendScheduled = false;
      if (mounted) _sendPos();
    });
  }

  void _startDrag() {
    if (_dragging) return;
    _dragging = true;
    _stopDrift();
  }

  void _endDrag() {
    _dragging = false;
    if (mounted) {
      _sendPos();
      _persistPosition();
    }
    if (_collapsed) _startDrift();
  }

  void _onDrag(DragUpdateDetails d) {
    if (_closing) return; // закрытие — драг не двигает окно
    _pos = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
    _startDrag();
    // Координаты жеста приходят чаще, чем кадры. Сливаем их до ближайшего
    // кадра Flutter; native затем применяет одну последнюю позицию на vsync.
    // Прямой вызов на каждый onPanUpdate накапливал MethodChannel-запросы.
    _scheduleSend();
  }

  /// Шлёт текущую позицию на нативную сторону, удерживая окошко в границах
  /// экрана. Координаты передаются дробными (dp) — нативная сторона сама
  /// переводит их в пиксели, поэтому движение получается плавным, а не
  /// «ступеньками» по 1dp.
  void _sendPos() {
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    final w = _collapsed ? _bubbleSize : _chatWidth;
    final h = _collapsed ? _bubbleSize : _chatHeight;
    final x = _pos.dx.clamp(0.0, sw - w);
    // Нижняя граница не даёт окну лечь на навбар (белая полоса под
    // клавиатурой/внизу) — запас 36dp под системную навигацию.
    final y = _pos.dy.clamp(0.0, sh - h - 36);
    _pos = Offset(x, y);
    // Не складываем MethodChannel-вызовы в очередь: если native ещё
    // применяет предыдущую позицию, оставляем только самую свежую.
    _pendingNativePosition = _pos;
    _flushNativePosition();
  }

  void _flushNativePosition() async {
    if (_nativeMoveInFlight || _pendingNativePosition == null || !mounted) {
      return;
    }
    final position = _pendingNativePosition!;
    _pendingNativePosition = null;
    _nativeMoveInFlight = true;
    try {
      await _overlayChannel.invokeMethod<void>('updateOverlayPosition', {
        'x': position.dx,
        'y': position.dy,
      });
    } catch (_) {
      // Окно могло закрыться между кадрами — это не должно ломать чат.
    } finally {
      _nativeMoveInFlight = false;
      if (mounted && _pendingNativePosition != null) {
        _flushNativePosition();
      }
    }
  }

  void _persistPosition() {
    try {
      globalPrefs.setDouble('ada_overlay_x', _pos.dx);
      globalPrefs.setDouble('ada_overlay_y', _pos.dy);
    } catch (_) {}
  }

  Future<void> _load() async {
    _avatarVariant = savedAdaAvatarIndex();
    // Лейбл модели не перезатираем при каждом входе из пузыря (прыгал из
    // «ada-0.0.3» в «Kilo..» и обратно): берём только если ещё пуст,
    // дальше живёт через синхронизацию/ответы.
    if (_modelLabel.isEmpty) {
      _modelLabel = await AiGuideService.currentModelLabel();
    }
    // ВОССТАНАВЛИВАЕМ позицию из prefs: showOverlay всегда создаёт окно
    // по центру, а мы переставляем его туда, где оно было (иначе каждое
    // открытие «прыгало» в центр).
    final sx = globalPrefs.getDouble('ada_overlay_x');
    final sy = globalPrefs.getDouble('ada_overlay_y');
    if (sx != null && sy != null) {
      _pos = Offset(sx, sy);
      _sendPos();
    } else {
      // Первый запуск — синхронизируемся с реальным положением окошка
      // (нативные координаты), чтобы первый драг не «прыгал». 
      try {
        final p = await FlutterOverlayWindow.getOverlayPosition();
        if (mounted) {
          _pos = Offset(p.x, p.y);
        }
      } catch (_) {
        // Окошко ещё не готово — просто оставляем центр экрана.
      }
    }
    try {
      final raw = await JsonFile.read(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(loaded);
            // Сообщения истории при открытии НЕ анимируют вход.
            _openedCount = _messages.length;
          });
          _scrollToBottom(animate: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleSize() async {
    if (_closing || _resizing) return;
    _resizing = true;
    final wasCollapsed = _collapsed;
    final previousPosition = _pos;
    try {
      if (_collapsed) {
        // Пузырь → чат: гасим пузырь, мгновенно ставим размер чата (в момент
        // непрозрачности 0 — незаметно), выравниваем центр, проявляем.
        _stopDrift();
        await _contentCtrl.reverse();
        if (!mounted) return;
        setState(() => _collapsed = false);
        _resizeKeepCenter(_bubbleSize, _bubbleSize, _chatWidth, _chatHeight);
        final resized = await FlutterOverlayWindow.resizeOverlay(
              _chatWidth.round(),
              _chatHeight.round(),
              false,
            ) ??
            false;
        if (!resized) {
          _pos = previousPosition;
          if (mounted) {
            setState(() => _collapsed = wasCollapsed);
            _contentCtrl.forward(from: 0);
          }
          return;
        }
        _sendPos();
        _persistPosition();
        if (!mounted) return;
        // Ждём, пока новый размер попадёт в кадр, и только затем проявляем
        // чат. Иначе последний кадр fade рисовался уже с новым layout и давал
        // заметный толчок.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        _contentCtrl.forward(from: 0);
      } else {
        // Чат → пузырь: гасим чат, мгновенно уменьшаем окно в центр,
        // проявляем пузырь.
        await _contentCtrl.reverse();
        if (!mounted) return;
        setState(() => _collapsed = true);
        _resizeKeepCenter(_chatWidth, _chatHeight, _bubbleSize, _bubbleSize);
        final resized = await FlutterOverlayWindow.resizeOverlay(
              _bubbleSize.round(),
              _bubbleSize.round(),
              false,
            ) ??
            false;
        if (!resized) {
          _pos = previousPosition;
          if (mounted) {
            setState(() => _collapsed = wasCollapsed);
            _contentCtrl.forward(from: 0);
          }
          return;
        }
        _sendPos();
        _persistPosition();
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        _contentCtrl.forward(from: 0);
        _startDrift();
      }
    } catch (_) {
      // Сервис мог закрыться между тапом и resize. Не оставляем Dart-состояние
      // в промежуточном режиме и не даём исключению завершить overlay engine.
      _pos = previousPosition;
      if (mounted) {
        if (_collapsed != wasCollapsed) {
          setState(() => _collapsed = wasCollapsed);
        }
        _contentCtrl.forward(from: 0);
      }
    } finally {
      _resizing = false;
    }
  }

  /// Пересчитывает _pos так, чтобы ЦЕНТР окна не сдвинулся при смене
  /// размеров (нативный ресайз идёт от верхнего левого угла).
  void _resizeKeepCenter(
    double fromW,
    double fromH,
    double toW,
    double toH,
  ) {
    final cx = _pos.dx + fromW / 2;
    final cy = _pos.dy + fromH / 2;
    _pos = Offset(cx - toW / 2, cy - toH / 2);
  }

  void _startDrift() {
    _driftTicker?.stop();
    _driftTicker?.dispose();
    _driftTicker = null;
    _ensurePos();
    _vx = Random().nextBool() ? 0.2133 : -0.2133;
    _vy = Random().nextBool() ? 0.16 : -0.16;
    _driftTicker = createTicker((_) => _driftTick());
    _driftTicker!.start();
  }

  void _stopDrift() {
    _driftTicker?.stop();
    _driftTicker?.dispose();
    _driftTicker = null;
  }

  void _ensurePos() {
    if (_pos.dx != 0 || _pos.dy != 0) return;
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    _pos = Offset((sw - _bubbleSize) / 2, (sh - _bubbleSize) / 2);
  }

  void _driftTick() {
    if (!_collapsed || !mounted || _dragging) return;
    _ensurePos();
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    var x = _pos.dx + _vx;
    var y = _pos.dy + _vy;
    if (x <= 4 || x >= sw - _bubbleSize - 4) _vx = -_vx;
    if (y <= 4 || y >= sh - _bubbleSize - 4) _vy = -_vy;
    x = x.clamp(4.0, sw - _bubbleSize - 4);
    y = y.clamp(4.0, sh - _bubbleSize - 4);
    if ((x - _pos.dx).abs() < 0.01 && (y - _pos.dy).abs() < 0.01) return;
    _pos = Offset(x, y);
    _scheduleSend();
  }

  Future<void> _clampToScreen() async {
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    final x = _pos.dx.clamp(2.0, sw - _chatWidth - 2);
    final y = _pos.dy.clamp(2.0, sh - _chatHeight - 2 - 36);
    _pos = Offset(x, y);
    try {
      await _overlayChannel.invokeMethod<void>('updateOverlayPosition', {
        'x': x,
        'y': y,
      });
    } catch (_) {}
  }

  void _scrollToBottom({bool animate = true}) {
    // Новые сообщения — ПЛАВНЫЙ скролл к концу (список уже построен).
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        final pos = _scrollCtrl.position;
        if (pos.pixels < pos.maxScrollExtent - 4) {
          _scrollCtrl.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
        }
      });
      return;
    }
    // Открытие чата: ListView.builder строит лениво — первый maxScrollExtent
    // только оценка («середина»). Прыгаем к концу итеративно, пока оценка
    // не сойдётся к настоящему концу.
    Future<void> converge() async {
      for (var i = 0; i < 14; i++) {
        if (!_scrollCtrl.hasClients) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          continue;
        }
        final pos = _scrollCtrl.position;
        if (pos.pixels >= pos.maxScrollExtent - 2 && i > 2) break;
        pos.jumpTo(pos.maxScrollExtent);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => converge());
  }

  Future<void> _send() async {
    final message = _inputCtrl.text.trim();
    if (message.isEmpty || _busy) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add(AiMessage(isUser: true, text: message));
      _busy = true;
      _typingFade = false;
    });
    _saveHistory();
    _scrollToBottom();

    try {
      final lang = await SettingsService.resolveLanguageCode();
      final reply = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: lang,
        // Мини-окошеко уважает веб-поиск из основного чата: настройка
        // живёт в prefs ('ai_web_search') и переживает перезапуск.
        useWebSearch: globalPrefs.getBool('ai_web_search') ?? false,
      );
      if (!mounted) return;
      // Эстафета «печатает…» → ответ: точки плавно гаснут, потом ответ
      // всплывает — как в полном чате, без резкого щелчка.
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() {
        _messages.add(AiMessage(isUser: false, text: reply));
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      // Обновляем лейбл модели (какой провайдер реально ответил) и
      // сообщаем ГЛАВНОМУ чату (отдельный движок) — там тоже сменится.
      AiGuideService.currentModelLabel().then((m) {
        if (mounted && m != _modelLabel) setState(() => _modelLabel = m);
      });
      final used = AiGuideService.lastUsedModel;
      if (used.isNotEmpty) {
        writeAdaSyncState(model: used);
      }
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _typingFade = true;
      });
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiMessage(
            isUser: false,
            text: Translations.t(
              'aiResort',
              context,
              'ИИ на курорте, подожди немного',
            ),
          ),
        );
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      _scrollToBottom();
    }
  }

  Future<void> _saveHistory() async {
    try {
      var toSave = _messages;
      if (toSave.length > 1000) toSave = toSave.sublist(toSave.length - 1000);
      await JsonFile.write(
        _historyKey,
        jsonEncode(toSave.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Тап по аватарке мини-окошка — тот же живой цикл, что в главном чате:
  /// переключаем на УНИКАЛЬНЫЙ значок (другую иконку), сохраняем в prefs
  /// и сообщаем главному приложению (там все аватарки обновятся мгновенно).
  void _cycleAvatar() {
    final cur = adaVariants[_avatarVariant];
    var next = _avatarVariant;
    var guard = 0;
    while (guard < adaVariants.length * 3) {
      next = Random().nextInt(adaVariants.length);
      if (adaVariants[next].icon != cur.icon) break;
      guard++;
    }
    if (next == _avatarVariant) {
      next = (_avatarVariant + 1) % adaVariants.length;
    }
    setState(() => _avatarVariant = next);
    setAdaAvatarVariant(next);
    // Синхронизация с главным чатом: файл состояния подхватится опросом.
    writeAdaSyncState(avatar: next);
  }

  /// Аватар с плавной сменой: fade + лёгкий scale при переключении варианта.
  Widget _animatedAvatar(double size, int variant) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: AdaAvatar(
        key: ValueKey('av_$variant'),
        size: size,
        variantIndex: variant,
      ),
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _stopDrift();
    _persistPosition();
    // Замораживаем движение: отменяем отложенную отправку позиции
    // (иначе окно могло «уехать» в момент закрытия) и фиксируем её.
    _sendScheduled = false;
    _pendingNativePosition = null;
    _setFocusable(false);
    await _contentCtrl.reverse();
    if (!mounted) return;
    globalPrefs.setBool('ai_floating', false);
    // Пишем маркер чтобы main app знал что оверлей закрыт.
    // SharedPreferences кэширует в памяти отдельно для каждого engine.
    try {
      await JsonFile.write('overlay_closed', '1');
    } catch (_) {}
    await FlutterOverlayWindow.closeOverlay();
    // Снимаем «закрытость» и позицию: движок живёт дальше, окно может
    // быть открыто снова — состояние не должно оставаться мёртвым.
    _closing = false;
    _inputFocused = false;
  }

  @override
  void dispose() {
    if (_live == this) _live = null;
    WidgetsBinding.instance.removeObserver(this);
    _appearTimer?.cancel();
    _syncTimer?.cancel();
    _stopDrift();
    _appearCtrl.dispose();
    _contentCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.removeListener(_onFocusChange);
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // removeViewInsets: у системного окошка НЕТ места для клавиатуры,
    // окно поверх неё не сдвигается — а вот MediaQuery с viewInsets могла
    // заставлять чат пересчитываться при каждом подъёме/опускании IME
    // (отсюда «подтормаживания»). Изолируем инсеты полностью.
    return MediaQuery.removeViewInsets(
      context: context,
      removeLeft: true,
      removeTop: true,
      removeRight: true,
      removeBottom: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_appearCtrl, _contentCtrl]),
        builder: (context, _) {
          final appearT = Curves.easeOutCubic.transform(_appearCtrl.value);
          final contentT = _contentCtrl.value;
          return Opacity(
            // Появление гарантировано (авто-таймер в initState + команда
            // сброса от main + lifecycle), поэтому минимум НЕ нужен —
            // иначе висел «полупрозрачный след чата» вместо плавного фейда.
            opacity: (appearT * contentT).clamp(0.0, 1.0),
            child: _collapsed ? _buildBubble() : _buildChatShell(),
          );
        },
      ),
    );
  }

  Widget _buildBubble() {
    final sz = _bubbleSize - 2;
    final colors = adaVariants[_avatarVariant].colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleSize,
      onTapDown: (_) => _stopDrift(),
      onPanStart: (_) => _startDrag(),
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      onPanUpdate: _onDrag,
      child: Center(
        child: RepaintBoundary(
          child: ClipOval(
            child: Container(
              width: sz,
              height: sz,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.55),
                  width: 1.2,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(child: _animatedAvatar(sz * 0.66, _avatarVariant)),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.32),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.45],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatShell() {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // Чат двигается за шапку и фон (в ленте драг перехватывает
      // скролл, чтобы сообщения можно было листать).
      onPanStart: (_) => _startDrag(),
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      onPanUpdate: _onDrag,
      child: ClipRRect(
        // Гарантированно скруглённые углы: ClipRRect клипает и фон, и
        // детей — никакого «прямоугольника» за панелью (некоторые
        // устройства рисовали подложку окна квадратной).
        borderRadius: BorderRadius.circular(22),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A0C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
            // Тени НЕ кладём: оверлей рисуется на поверхности, обрезанной
            // ПРЯМОУГОЛЬНОЙ границей окна — размытая тень обрезалась
            // углами окна и выглядела как тёмный «квадратный фон».
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildHeader(cs),
              const Divider(height: 1),
              Expanded(
                child: _messages.isEmpty ? _buildEmpty(cs) : _buildMessages(cs),
              ),
              _buildInput(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return GestureDetector(
      onPanUpdate: _onDrag,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ручка-таб сверху по центру — как у главного чата.
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: cs.outlineVariant.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _cycleAvatar,
                  child: _animatedAvatar(28, _avatarVariant),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleSize,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ада',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        // Модель (ada-0.0.3 / Kilo · openrouter/free / LLM7 · fast)
                        // переключается плавно при смене провайдера.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(opacity: anim, child: child),
                          child: Text(
                            _modelLabel.isEmpty ? 'ada-0.0.3' : _modelLabel,
                            key: ValueKey(
                              _modelLabel.isEmpty ? 'ada-0.0.3' : _modelLabel,
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleSize,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.minimize_rounded,
                      color: cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      Icons.close_rounded,
                      color: cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 36,
              color: cs.primary,
            ),
            const SizedBox(height: 8),
            Text(
              Translations.t('aiOverlayEmpty', context, 'Chat with Ada'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(ColorScheme cs) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: _messages.length + (_busy ? 1 : 0),
      itemBuilder: (context, i) {
        if (_busy && i == _messages.length) {
          // «Печатает…»: гаснет плавно перед ответом (эстафета _typingFade).
          return AnimatedOpacity(
            opacity: _typingFade ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _TypingBubble(avatar: _avatarVariant),
          );
        }
        final m = _messages[i];
        // Плавное появление: fade + мягкий scale (как у пузырей главного
        // чата) — без сдвига, чтобы не двоилось движение при скролле.
        // Только у новых (добавленных ПОСЛЕ открытия) сообщений.
        final isNew = i >= _openedCount;
        final last3 = i >= _messages.length - 3;
        final animate = isNew && last3;
        return TweenAnimationBuilder<double>(
          key: ValueKey('mini_bubble_$i'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: animate ? 300 : 1),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          ),
          child: _MiniBubble(
            message: m,
            avatar: _avatarVariant,
            colorScheme: cs,
          ),
        );
      },
    );
  }

  Widget _buildInput(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        // Полностью непрозрачный фон: полупрозрачный давал «белую полосу»
        // под клавиатурой/внизу чата.
        color: cs.surfaceContainerLowest,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              magnifierConfiguration: TextMagnifierConfiguration.disabled,
              // Поле мини-окна не должно открывать выделение/тулбар:
              // long-press оставляем для обычного ввода, без полупрозрачного
              // selection overlay поверх оверлея.
              contextMenuBuilder: (_, __) => const SizedBox.shrink(),
              selectionControls: null,
              enableInteractiveSelection: false,
              controller: _inputCtrl,
              focusNode: _inputFocus,
              minLines: 1,
              maxLines: 3,
              scrollPadding: EdgeInsets.zero,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              onTap: () async {
                // Первый тап: окно становится фокусирующим, поле — фокусом.
                // Некоторые прошивки «съедают» первый requestFocus, пока
                // натив применяет флаг — пробуем до 6 раз, плюс прямой
                // показ IME, плюс страховка на следующий кадр.
                for (var i = 0; i < 6 && mounted; i++) {
                  await _setFocusable(true);
                  if (!mounted) return;
                  _inputFocus.requestFocus();
                  try {
                    await SystemChannels.textInput
                        .invokeMethod<void>('TextInput.show');
                  } catch (_) {}
                  if (!mounted) return;
                  if (_inputFocus.hasFocus) break;
                  await Future<void>.delayed(const Duration(milliseconds: 110));
                }
                if (mounted && !_inputFocus.hasFocus) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _inputFocus.requestFocus();
                      try {
                        SystemChannels.textInput
                            .invokeMethod<void>('TextInput.show');
                      } catch (_) {}
                    }
                  });
                }
              },
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                // Окошко ВСЕГДА тёмное (ThemeData.dark): буквы светлые,
                // а не чёрные — фон поля тёмный.
                color: cs.onSurface,
              ),
              cursorColor: cs.primary,
              decoration: InputDecoration(
                hintText: Translations.t(
                  'aiInputHint',
                  context,
                  'Message…',
                ),
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    width: 34,
                    height: 34,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    key: const ValueKey('send'),
                    onPressed: _send,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      minimumSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════

class _MiniBubble extends StatelessWidget {
  final AiMessage message;
  final int avatar;
  final ColorScheme colorScheme;
  const _MiniBubble({
    required this.message,
    required this.avatar,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final cs = colorScheme;
    final bubbleColor = isUser ? cs.primary : cs.surfaceContainerHigh;
    final textColor = isUser ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              // Плавная смена аватарки и в пузырях сообщений окошка.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: AdaAvatar(
                  key: ValueKey('mini_av_$avatar'),
                  size: 18,
                  variantIndex: avatar,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isUser ? 14 : 4),
                    topRight: Radius.circular(isUser ? 4 : 14),
                    bottomLeft: const Radius.circular(14),
                    bottomRight: const Radius.circular(14),
                  ),
                ),
                child: buildMarkdownText(
                  message.text,
                  TextStyle(fontSize: 12, color: textColor, height: 1.28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  final int avatar;
  const _TypingBubble({required this.avatar});
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ава меняется плавно (fade+scale), даже пока Ада печатает:
            // смена значка в любом месте мгновенно анимируется и здесь.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: anim, child: child),
              ),
              child: AdaAvatar(
                key: ValueKey('typing_av_${widget.avatar}'),
                size: 16,
                variantIndex: widget.avatar,
              ),
            ),
            const SizedBox(width: 5),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary,
                        ),
                        // Без вертикального прыжка: только альфа пульсирует
                        // (плавный «печатает…» на слабых устройствах —
                        // transform каждой точки каждый кадр дёргал UI).
                        color: cs.primary.withValues(alpha: 0.4 + 0.6 * (.5 - .5 * cos((t * 2 * pi) - i * 0.9))),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
