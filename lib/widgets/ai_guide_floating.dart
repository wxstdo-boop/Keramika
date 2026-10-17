part of 'ai_guide.dart';

class AiFloatingBubble extends StatefulWidget {
  /// Развернуть в полный чат (кнопка со стрелками / тап по телу окошка).
  final VoidCallback onOpen;

  const AiFloatingBubble({super.key, required this.onOpen});

  @override
  State<AiFloatingBubble> createState() => _AiFloatingBubbleState();
}

class _AiFloatingBubbleState extends State<AiFloatingBubble>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _historyKey = 'ai_chat_history';
  static const double _expandedHeight = 240;
  static const double _collapsedSize = 64;

  /// Ширина развёрнутого окошка: компактная, ближе к квадрату.
  static double _windowWidth(double screenWidth) =>
      (screenWidth * 0.58).clamp(200.0, 250.0);

  Offset _pos = Offset.zero;
  // Позиция окошка — ValueNotifier: драг двигает только Positioned
  // (готовый слой), НЕ перестраивая весь чат на каждый пиксель.
  final ValueNotifier<Offset> _posNotifier = ValueNotifier<Offset>(Offset.zero);
  final List<AiMessage> _messages = [];
  String? _historySnapshot;
  bool _busy = false;
  bool _typingFade = false;
  bool _storageErrorShown = false;
  // Сколько сообщений было при открытии окошка: только новые проигрывают
  // анимацию входа, иначе при разворачивании вся история «вспыхивала».
  int _openedCount = 0;
  // Свёрнуто ли окошко в мелкий кружок-аватарку (тап по названию/аватарке).
  bool _collapsed = false;
  final _inputCtrl = WideDashController();
  final _scrollCtrl = ScrollController();
  // Плавное появление/исчезание окошка при переключении режима «в окне».
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: aiFloating.value ? 1.0 : 0.0,
  );
  // Троеточие «Ада печатает…» в мини-окошке (repeat пока busy).
  late final AnimationController _dotsCtrlMini = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHistory();
    aiFloating.addListener(_onFloatChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pos == Offset.zero) {
      final size = MediaQuery.of(context).size;
      try {
        _pos = Offset(
          (globalPrefs.getDouble('ai_bubble_fx') ?? 0.58) * size.width,
          (globalPrefs.getDouble('ai_bubble_fy') ?? 0.65) * size.height,
        );
      } catch (_) {
        _pos = Offset(size.width * 0.58, size.height * 0.65);
      }
      _clampPos(size);
      _posNotifier.value = _pos;
    }
  }

  /// Верхний пояс для окошка: статус-бар + шапка + таблетка разделов. Окошко
  /// лежит в корневом Stack НАД экранами раздела, и без пояса при
  /// перетаскивании вверх оно забиралось на категории «Полезные/Вредные».
  double get _topKeepout => adaTopKeepout(MediaQuery.paddingOf(context).top);

  void _clampPos(Size screen) {
    final w = _windowWidth(screen.width);
    final maxY = math.max(_topKeepout, screen.height - _expandedHeight - 8.0);
    _pos = Offset(
      _pos.dx.clamp(8.0, screen.width - w - 8.0),
      _pos.dy.clamp(_topKeepout, maxY),
    );
  }

  void _onFloatChanged() {
    _ctrl.animateTo(aiFloating.value ? 1.0 : 0.0, curve: Curves.easeOutCubic);
  }

  /// Загружаем ПОЛНУЮ историю диалога — единый контекст с полным чатом.
  /// Раньше здесь брался «хвост» из 20 сообщений и сохранялся обратно —
  /// из-за этого общий чат обрезался и контекст расходился.
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
            _messages
              ..clear()
              ..addAll(loaded);
            _openedCount = _messages.length;
          });
          _scrollToBottom(animate: false);
        }
      }
    } catch (error, stackTrace) {
      _reportStorageFailure(error, stackTrace);
    }
  }

  void _reportStorageFailure(Object error, StackTrace stackTrace) {
    debugPrint('Ada floating history operation failed: $error\n$stackTrace');
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

  Future<void> _saveHistory() async {
    try {
      var toSave = _messages;
      if (toSave.length > 1000) {
        toSave = toSave.sublist(toSave.length - 1000);
      }
      final value = jsonEncode(toSave.map((m) => m.toJson()).toList());
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

  void _scrollToBottom({bool animate = true}) {
    // Лента с reverse:true — индекс 0 это низ; открытие сразу показывает
    // последние сообщения без ретрай-цикла jumpTo (тот дёргал layout).
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

  /// Отправка прямо из компактного окошка. Язык — как у пользователя
  /// (раньше был захардкожен 'en', из-за чего Ада отвечала по-английски).
  Future<void> _send() async {
    final message = _inputCtrl.text.trim();
    if (message.isEmpty || _busy) return;
    // Поколение чата: если историю очистили в полном чате, пока Ада думала,
    // ответ не «проскочит» в очищенную историю.
    final gen = adaChatGeneration;
    _inputCtrl.clear();
    setState(() {
      _messages.add(
        AiMessage(
          isUser: true,
          text: message,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _busy = true;
      _typingFade = false;
    });
    // Горячий стрик: общение из компактного пузыря тоже считается.
    unawaited(AiGuideService.bumpAdaStreak());
    _dotsCtrlMini.repeat();
    _saveHistory();
    _scrollToBottom();
    try {
      final lang = await SettingsService.resolveLanguageCode();
      final answer = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: lang,
        // Мини-окно поверх чужого приложения: Ада видит текст экрана
        // (мессенджер и т.п.) и может подсказать ответ собеседнику.
        screenContext: await ScreenReaderService.snapshot(),
      );
      if (!mounted || gen != adaChatGeneration) return;
      // Эстафета «печатает…» → ответ: точки плавно гаснут, потом ответ
      // всплывает — как в полном чате, без резкого щелчка.
      _dotsCtrlMini.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _messages.add(
          AiMessage(
            isUser: false,
            text: answer,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      _scrollToBottom();
    } catch (_) {
      if (!mounted || gen != adaChatGeneration) return;
      setState(() {
        _busy = false;
        _typingFade = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Окошко не скрываем при переходе в фон/возврате.
  }

  @override
  void dispose() {
    aiFloating.removeListener(_onFloatChanged);
    _ctrl.dispose();
    _dotsCtrlMini.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _posNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _drag(Offset delta, Size screen) {
    final next = _pos + delta;
    final w = _windowWidth(screen.width);
    final maxY = math.max(_topKeepout, screen.height - _expandedHeight - 8.0);
    _pos = Offset(
      next.dx.clamp(8.0, screen.width - w - 8.0),
      next.dy.clamp(_topKeepout, maxY),
    );
    _posNotifier.value = _pos;
  }

  void _savePos(Size screen) {
    globalPrefs.setDouble('ai_bubble_fx', _pos.dx / screen.width);
    globalPrefs.setDouble('ai_bubble_fy', _pos.dy / screen.height);
  }

  /// Объёмная «пузырьковая» оболочка: градиентный корпус, глянцевый блик,
  /// цветное свечение + глубокая тень — выглядит как плавающий пузырь.
  BoxDecoration _bubbleDecoration(ColorScheme cs, bool collapsed) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(collapsed ? 32 : 24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cs.surfaceContainerHighest.withValues(alpha: 0.99),
          cs.surfaceContainerLowest.withValues(alpha: 0.99),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.4),
        width: 1.2,
      ),
      boxShadow: [
        // Цветное свечение — «объём» пузыря.
        BoxShadow(
          color: cs.primary.withValues(alpha: collapsed ? 0.4 : 0.25),
          blurRadius: collapsed ? 14 : 22,
          offset: const Offset(0, 4),
        ),
        // Убираем тёмный фон с незакруглёнными углами: прозрачная
        // поверх градиентного пузыря, остаётся только драг-хендл.
      ],
    );
  }

  /// Глянцевый блик сверху (стеклянная «выпуклость»).
  Widget _glassHighlight(ColorScheme cs, bool collapsed) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(collapsed ? 32 : 24),
            // Убираем тёмный фон с незакруглёнными углами: прозрачная
            // поверх градиентного пузыря, остаётся только драг-хендл.
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.of(context).size;
    final w = _windowWidth(screen.width);
    return ValueListenableBuilder<bool>(
      valueListenable: aiLockScreenVisible,
      builder: (context, locked, _) {
        if (locked) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: _ctrl,
          // Тяжёлый контент (лента сообщений, поле ввода) строится ОДИН раз
          // и живёт как готовый child — при анимации появления/закрытия
          // пересоздаётся только Opacity/Scale (готовый слой двигается),
          // а не весь чат на каждый кадр. Раньше на Redmi Note 12 каждый
          // тик 260-мс анимации перестраивал весь ListView — тормозило.
          child: AnimatedContainer(
            // easeOutBack давал overshoot — окошко «перелетало» размер
            // и дёргалось при разворачивании. Плавная easeOutCubic.
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            width: _collapsed ? _collapsedSize : w,
            height: _collapsed ? _collapsedSize : _expandedHeight,
            decoration: _bubbleDecoration(cs, _collapsed),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    // Меньше «сжатости» при разворачивании: чат больше не
                    // вылезает из «сжатой» 0.9-копии, а мягко проявляется.
                    child: ScaleTransition(
                      scale: Tween(begin: 0.965, end: 1.0).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _collapsed
                      ? _buildCollapsedCircle(cs, key: const ValueKey('circle'))
                      : _buildExpanded(
                          cs,
                          screen,
                          key: const ValueKey('expanded'),
                        ),
                ),
                // Блик поверх любого состояния.
                _glassHighlight(cs, _collapsed),
              ],
            ),
          ),
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_ctrl.value);
            if (t <= 0.001) return const SizedBox.shrink();
            return ValueListenableBuilder<Offset>(
              valueListenable: _posNotifier,
              builder: (context, pos, _) => Positioned(
                left: pos.dx,
                top: pos.dy,
                child: IgnorePointer(
                  ignoring: !aiFloating.value || t < 1.0,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * t,
                      child: child,
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

  /// Мелкий кружок-аватарка (свёрнутое состояние). Тап — развернуть.
  Widget _buildCollapsedCircle(ColorScheme cs, {Key? key}) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _collapsed = false),
      onPanUpdate: (d) => _drag(d.delta, MediaQuery.of(context).size),
      onPanEnd: (_) => _savePos(MediaQuery.of(context).size),
      child: Center(
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primaryContainer, cs.primary.withValues(alpha: 0.85)],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Center(child: AdaAvatar(size: 36)),
        ),
      ),
    );
  }

  /// Развёрнутое состояние: шапка (перетаскивание, скрутить, развернуть,
  /// закрыть) + лента сообщений + поле ввода.
  Widget _buildExpanded(ColorScheme cs, Size screen, {Key? key}) {
    return Column(
      key: key,
      children: [
        // Шапка — перетаскивание + скрутить в кружок + развернуть + закрыть.
        GestureDetector(
          onPanUpdate: (d) => _drag(d.delta, screen),
          onPanEnd: (_) => _savePos(screen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            // Прозрачная шапка поверх градиентного пузыря — без «квадратной»
            // заливки, остаётся только драг-хендл.
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _collapsed = true),
                  child: AdaAvatar(size: 26),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _collapsed = true),
                    child: Text(
                      Translations.t('aiGuide', context, 'AI guide'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                // Развернуть в полный чат — плавно.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.open_in_full_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                // Закрыть окошко (выключить режим).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    aiFloating.value = false;
                    globalPrefs.setBool('ai_floating', false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Лента последних сообщений. Тап по ней — плавно открыть полный чат.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        Translations.t(
                          'aiOverlayEmpty',
                          context,
                          'Chat with Ada',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_busy && i == 0) {
                        // «Печатает…»: точки гаснут плавно перед ответом
                        // (эстафета как в полном чате — _typingFade).
                        return AnimatedOpacity(
                          opacity: _typingFade ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: _TypingDotsMini(animation: _dotsCtrlMini),
                        );
                      }
                      final mi = _busy
                          ? _messages.length - i
                          : _messages.length - 1 - i;
                      return _MiniBubble(
                        message: _messages[mi],
                        colorScheme: cs,
                        avatar: 0,
                        // Анимация входа — только у новых сообщений
                        // (добавленных после открытия окошка).
                        animate: mi >= _openedCount,
                      );
                    },
                  ),
          ),
        ),
        const Divider(height: 1),
        // Поле ввода + отправка.
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          // Прозрачное поле ввода поверх градиентного пузыря — без «квадратной»
          // заливки, остаётся только драг-хендл.
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Каждую букву рисует SmoothTyping (как в основном чате).
                    SmoothTyping(
                      controller: _inputCtrl,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: cs.onSurface,
                      ),
                      builder: (style) => TextField(
                        style: style,
                        magnifierConfiguration:
                            TextMagnifierConfiguration.disabled,
                        contextMenuBuilder: minimalContextMenuBuilder,
                        controller: _inputCtrl,
                        minLines: 1,
                        maxLines: 2,
                        inputFormatters: [WideDashFormatter()],
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        // Автопробел клавиатуры — убираем подсказки.
                        enableSuggestions: false,
                        autocorrect: false,
                        cursorColor: cs.primary,
                        // Каретка мигает плавно (fade), а не резко вкл/выкл.
                        cursorOpacityAnimates: true,
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: cs.surfaceContainerHigh.withValues(
                            alpha: 0.7,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    // Плавная подсказка: гаснет при вводе, мягко возвращается
                    // при очистке поля.
                    IgnorePointer(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _inputCtrl,
                        builder: (context, v, _) => AnimatedOpacity(
                          opacity: v.text.isEmpty ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            child: Text(
                              Translations.t(
                                'aiInputHint',
                                context,
                                'Message…',
                              ),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 30,
                        height: 30,
                        child: Padding(
                          padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : IconButton.filled(
                        key: const ValueKey('send'),
                        onPressed: () {
                          Haptics.light();
                          _send();
                        },
                        icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                        style: IconButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Плавное «троеточие» Ада печатает… — три точки, прыгающие по очереди.
/// [animation] — внешний AnimationController (останавливается в _send),
/// чтобы точки не тикали, когда ответ уже пришёл.
class _TypingDotsMini extends StatefulWidget {
  final Animation<double> animation;
  const _TypingDotsMini({required this.animation});

  @override
  State<_TypingDotsMini> createState() => _TypingDotsMiniState();
}

class _TypingDotsMiniState extends State<_TypingDotsMini> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final t = widget.animation.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                    // Волна: каждая точка прыгает со своим сдвигом.
                    transform: Matrix4.translationValues(
                      0,
                      -4 * (0.5 - 0.5 * math.cos((t * 2 * math.pi) - i * 0.9)),
                      0,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Компактный пузырь сообщения в мини-окошке. Появление — плавное:
/// сообщение мягко всплывает (fade + slide вверх), как в полном чате.
/// Только у НОВЫХ сообщений ([animate] true) — старые при открытии
/// окошка не «прыгают» поверх разворачивания.
class _MiniBubble extends StatelessWidget {
  final AiMessage message;
  final int avatar;
  final ColorScheme colorScheme;
  final bool animate;
  const _MiniBubble({
    required this.message,
    required this.avatar,
    required this.colorScheme,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final cs = colorScheme;
    final Widget bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.55,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 14 : 12),
            topRight: Radius.circular(isUser ? 12 : 14),
            bottomLeft: const Radius.circular(14),
            bottomRight: const Radius.circular(14),
          ),
        ),
        child: buildMarkdownText(
          message.text,
          TextStyle(
            // Сообщения в мини-оверлее тоже увеличены, markdown не растёт.
            fontSize: 16,
            height: 1.3,
            color: isUser ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      child: bubble,
      builder: (context, value, child) {
        final e = Curves.easeOutCubic.transform(value);
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - e)),
            child: child,
          ),
        );
      },
    );
  }
}
