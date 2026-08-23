import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../utils/markdown_text.dart';
import '../services/ai_guide_service.dart';
import '../services/json_file.dart';
import '../services/prefs.dart';
import '../services/settings_service.dart';
import '../utils/context_menu.dart';

/// Канал системного оверлея.
const MethodChannel _overlayChannel = MethodChannel('x-slayer/overlay');

/// Оригинальные градиенты аватарки Ады (те же что в основном чате).
const _overlayGradients = <List<Color>>[
  [Color(0xFFFF9EC6), Color(0xFFB06AB3), Color(0xFF7C4DFF)],
  [Color(0xFFFFB199), Color(0xFFFF6B9D), Color(0xFFE63946)],
  [Color(0xFF9BE8FF), Color(0xFF7C4DFF), Color(0xFF2E3192)],
  [Color(0xFF8BF0C8), Color(0xFF2BB3A0), Color(0xFF0F6E6E)],
  [Color(0xFFFFD166), Color(0xFFFF8C42), Color(0xFFD62828)],
  [Color(0xFFC9B8FF), Color(0xFF8E7CFF), Color(0xFF4A3F9E)],
];

const _overlayIcons = <IconData>[
  Icons.favorite,
  Icons.local_florist,
  Icons.auto_awesome,
  Icons.wb_sunny,
  Icons.star,
  Icons.psychology,
];

/// Размеры окна оверлея (dp). Окно почти квадратное — «не вдлину»:
/// 340×380 (было 280×440 — вытянутое).
// Пузырь уменьшен ВДВОЕ (64→32): компактнее, не перекрывает контент.
// Чат-окно то же (340×380).
const double _bubbleSize = 32;
const double _chatWidth = 340;
const double _chatHeight = 380;

/// Точка входа для главного приложения: движок оверлея переживает закрытие
/// окна, поэтому при каждом показе окна мы посылаем команду «сбросься и
/// покажись» — только так повторное открытие гарантированно видимо.
/// (lifecycle-события могут не долететь до вторичного движка.)
void resetOverlayFromHost() => _OverlayChatState.onHostReset();

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

  /// Сброс из основного окна: окно пересоздано — привести чат в состояние
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
    s._posInit = false;
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

  // ── Дрейф пузыря ──────────────────────────────────────────────────
  Timer? _driftTimer;
  double _vx = 0.8;
  double _vy = 0.6;
  Offset _pos = Offset.zero;
  bool _posInit = false;
  bool _driftMoving = false;

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
      _setFocusable(f);
      // Окно при фокусе НЕ поднимаем: оно живёт поверх клавиатуры, и
      // пользователь сам двигает его куда надо. Просто прокручиваем ленту
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
    } catch (_) {}
  }

  // ── Drag оверлея ──────────────────────────────────────────────────
  // Драг работает ПО ВСЕЙ площади (пузырь и чат). Дельты копятся в _pos,
  // а на нативную сторону позиция уходит ОДИН раз за ~16мс (частота
  // кадров): пачка вызовов MethodChannel при быстром жесте перегружает
  // UI-поток и движение начинает «дёргаться». Раз в кадр — телефон успевает
  // отрисовать каждое новое положение окна.
  bool _dragging = false;
  Timer? _dragTimer;

  void _startDrag() {
    if (_dragging) return;
    _dragging = true;
    _stopDrift();
    _dragTimer?.cancel();
    _dragTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_dragging) return;
      _sendPos();
    });
  }

  void _endDrag() {
    _dragging = false;
    _dragTimer?.cancel();
    _dragTimer = null;
    if (mounted) _sendPos();
    if (_collapsed) _startDrift();
  }

  void _onDrag(DragUpdateDetails d) {
    _pos = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
    _startDrag();
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
    final y = _pos.dy.clamp(0.0, sh - h);
    _pos = Offset(x, y);
    _overlayChannel.invokeMethod<void>('updateOverlayPosition', {
      'x': _pos.dx,
      'y': _pos.dy,
    });
    // Сохраняем позицию: при переоткрытии окно должно встать ТУДА, где
    // его оставили (showOverlay по умолчанию открывает в ЦЕНТРЕ, и без
    // сохранения позиция «не запоминалась»).
    try {
      globalPrefs.setDouble('ada_overlay_x', _pos.dx);
      globalPrefs.setDouble('ada_overlay_y', _pos.dy);
    } catch (_) {}
  }

  Future<void> _load() async {
    _avatarVariant = (globalPrefs.getInt('ada_avatar_variant') ?? 0).clamp(
      0,
      _overlayGradients.length - 1,
    );
    _modelLabel = await AiGuideService.currentModelLabel();
    // ВОССТАНАВЛИВАЕМ позицию из prefs: showOverlay всегда создаёт окно
    // по центру, а мы переставляем его туда, где оно было (иначе каждое
    // открытие «прыгало» в центр).
    final sx = globalPrefs.getDouble('ada_overlay_x');
    final sy = globalPrefs.getDouble('ada_overlay_y');
    if (sx != null && sy != null) {
      _pos = Offset(sx, sy);
      _posInit = true;
      _sendPos();
    } else {
      // Первый запуск — синхронизируемся с реальным положением окошка
      // (нативные координаты), чтобы первый драг не «прыгал». 
      try {
        final p = await FlutterOverlayWindow.getOverlayPosition();
        if (mounted) {
          _pos = Offset(p.x, p.y);
          _posInit = true;
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
    if (_closing) return;
    if (_collapsed) {
      // Пузырь → чат: гасим пузырь, мгновенно ставим размер чата (в момент
      // непрозрачности 0 — незаметно), выравниваем центр, проявляем.
      _stopDrift();
      await _contentCtrl.reverse();
      if (!mounted) return;
      setState(() => _collapsed = false);
      _resizeKeepCenter(_bubbleSize, _bubbleSize, _chatWidth, _chatHeight);
      await FlutterOverlayWindow.resizeOverlay(
        _chatWidth.round(),
        _chatHeight.round(),
        false,
      );
      _sendPos();
      _clampToScreen();
      if (!mounted) return;
      _contentCtrl.forward(from: 0);
      _load();
    } else {
      // Чат → пузырь: гасим чат, мгновенно уменьшаем окно в центр,
      // проявляем пузырь.
      await _contentCtrl.reverse();
      if (!mounted) return;
      setState(() => _collapsed = true);
      _resizeKeepCenter(_chatWidth, _chatHeight, _bubbleSize, _bubbleSize);
      await FlutterOverlayWindow.resizeOverlay(
        _bubbleSize.round(),
        _bubbleSize.round(),
        false,
      );
      _sendPos();
      if (!mounted) return;
      _contentCtrl.forward(from: 0);
      _startDrift();
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
    _driftTimer?.cancel();
    _ensurePos();
    // Скорость та же, что была (0.8/0.6 dp за 60мс), но тикаем каждые
    // 16мс — пузырь плывёт плавно, а не «перескакивает» ~16 раз в секунду.
    _vx = Random().nextBool() ? 0.2133 : -0.2133;
    _vy = Random().nextBool() ? 0.16 : -0.16;
    _driftTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _driftTick(),
    );
  }

  void _stopDrift() {
    _driftTimer?.cancel();
    _driftTimer = null;
    // Снимаем флаг «тик в полёте» — иначе после остановки/перезапуска
    // дрейф навсегда застревает (guard в _driftTick).
    _driftMoving = false;
  }

  void _ensurePos() {
    if (_posInit) return;
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    _pos = Offset((sw - _bubbleSize) / 2, (sh - _bubbleSize) / 2);
    _posInit = true;
  }

  void _driftTick() {
    if (!_collapsed || !mounted || _driftMoving) return;
    _ensurePos();
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    var x = _pos.dx + _vx;
    var y = _pos.dy + _vy;
    if (x <= 4 || x >= sw - _bubbleSize - 4) _vx = -_vx;
    if (y <= 4 || y >= sh - _bubbleSize - 4) _vy = -_vy;
    x = x.clamp(4.0, sw - _bubbleSize - 4);
    y = y.clamp(4.0, sh - _bubbleSize - 4);
    // Сдвиг меньше ~0.01dp за тик — не отправляем (лишние вызовы
    // нативной стороны только добавляют задержку и «дёрганье»).
    if ((x - _pos.dx).abs() < 0.01 && (y - _pos.dy).abs() < 0.01) return;
    _pos = Offset(x, y);
    _driftMoving = true;
    _overlayChannel
        .invokeMethod<void>('updateOverlayPosition', {
          'x': _pos.dx,
          'y': _pos.dy,
        })
        .then((_) => _driftMoving = false)
        .catchError((_) => _driftMoving = false);
  }

  Future<void> _clampToScreen() async {
    final sw = globalPrefs.getDouble('ada_overlay_sw') ?? 400;
    final sh = globalPrefs.getDouble('ada_overlay_sh') ?? 850;
    final x = _pos.dx.clamp(2.0, sw - _chatWidth - 2);
    final y = _pos.dy.clamp(2.0, sh - _chatHeight - 2);
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
      // Обновляем лейбл модели (какой провайдер реально ответил).
      AiGuideService.currentModelLabel().then((m) {
        if (mounted && m != _modelLabel) setState(() => _modelLabel = m);
      });
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

  void _cycleAvatar() {
    var next = _avatarVariant;
    var guard = 0;
    while (next == _avatarVariant && guard < _overlayGradients.length) {
      next = Random().nextInt(_overlayGradients.length);
      guard++;
    }
    setState(() => _avatarVariant = next);
    globalPrefs.setInt('ada_avatar_variant', next);
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
      child: _OverlayAvatar(
        key: ValueKey('av_$variant'),
        size: size,
        variant: variant,
      ),
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _stopDrift();
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
    _posInit = false;
    _inputFocused = false;
  }

  @override
  void dispose() {
    if (_live == this) _live = null;
    WidgetsBinding.instance.removeObserver(this);
    _appearTimer?.cancel();
    _dragTimer?.cancel();
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
    final sz = _bubbleSize - 8;
    final colors = _overlayGradients[_avatarVariant];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleSize,
      // Драг за ВЕСЬ пузырь. Дрейф останавливаем СРАЗУ при касании
      // (onTapDown), иначе он продолжает толкать пузырь под пальцем —
      // перетаскивание выглядело «дёрганым». После отпускания дрейф
      // возобновляется.
      onTapDown: (_) => _stopDrift(),
      onPanStart: (_) => _startDrag(),
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _endDrag,
      onPanUpdate: _onDrag,
      child: Center(
        child: Container(
          width: sz,
          height: sz,
          decoration: BoxDecoration(
            // Круглый градиентный пузырь: белая обводка. Тени УБРАНЫ —
            // blur-тень за круглым клипом обрезалась прямоугольной
            // границей окна и выглядела как тёмный «квадрат» за пузырём.
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
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: _animatedAvatar(sz * 0.66, _avatarVariant),
              ),
              // Глянцевый блик сверху — «стеклянный» объём (как в web).
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
            child: Stack(
              children: [
                // Живой markdown-предпросмотр под полем: *курсив* виден
                // сразу, а не «звёздочками».
                Positioned.fill(
                  child: ClipRect(
                    child: IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedBuilder(
                            animation: _inputCtrl,
                            builder: (context, _) {
                              final t = _inputCtrl.text;
                              if (t.isEmpty) return const SizedBox.shrink();
                              return buildMarkdownText(
                                t,
                                TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: cs.onSurface,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                TextField(
                  magnifierConfiguration: TextMagnifierConfiguration.disabled,
                  contextMenuBuilder: minimalContextMenuBuilder,
                  controller: _inputCtrl,
                  focusNode: _inputFocus,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onTap: () async {
                    // Первый тап: снимаем FLAG_NOT_FOCUSABLE, ЖДЁМ ответа
                    // нативной стороны и только потом даём фокус полю —
                    // иначе клавиатура появляется лишь со второго тапа.
                    await _setFocusable(true);
                    if (mounted) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _inputFocus.requestFocus();
                      });
                    }
                  },
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: Colors.transparent,
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
              ],
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

class _OverlayAvatar extends StatelessWidget {
  final double size;
  final int variant;
  const _OverlayAvatar({super.key, required this.size, required this.variant});

  @override
  Widget build(BuildContext context) {
    final colors = _overlayGradients[variant];
    final icon = _overlayIcons[variant];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        // Без тени: она обрезалась прямоугольной границей окна и давала
        // видимый «квадрат» за круглой аватаркой.
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: size * 0.06,
            left: size * 0.16,
            child: Container(
              width: size * 0.42,
              height: size * 0.24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.5),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Icon(
            icon,
            size: size * 0.4,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ],
      ),
    );
  }
}

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
                child: _OverlayAvatar(
                  key: ValueKey('mini_av_$avatar'),
                  size: 18,
                  variant: avatar,
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
                  TextStyle(fontSize: 12.5, color: textColor, height: 1.3),
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
            _OverlayAvatar(size: 16, variant: widget.avatar),
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
                        transform: Matrix4.translationValues(
                          0,
                          -4 * (0.5 - 0.5 * cos((t * 2 * pi) - i * 0.9)),
                          0,
                        ),
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
