import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/wake_task.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../widgets/smooth_keyboard_body.dart';

class WakeTaskScreen extends StatefulWidget {
  final WakeUpTask taskType;
  final bool isTest;
  final String? soundName;
  final String? customSoundPath;

  /// Вызывается вместо `Navigator.pop`, когда экран задачи — ДОМАШНИЙ
  /// виджет (холодный старт по будильнику). В этом случае его некуда
  /// «попить», и маршрут назад берёт на себя хост (см. [_AlarmBootHost]).
  final VoidCallback? onDismissed;

  const WakeTaskScreen({
    super.key,
    required this.taskType,
    this.isTest = true,
    this.soundName,
    this.customSoundPath,
    this.onDismissed,
  });

  @override
  State<WakeTaskScreen> createState() => _WakeTaskScreenState();
}

class _WakeTaskScreenState extends State<WakeTaskScreen>
    with WidgetsBindingObserver {
  bool _solved = false;
  bool _allowPop = false;
  late final AudioPlayer _player;

  /// Решение засчитано, но карточка ЕЩЁ не схлопывалась.
  ///
  /// Схлопывание к «Отлично, ты проснулся!» и отъезд клавиатуры — два
  /// независимых движения, и если они идут одновременно, окно выглядит так,
  /// будто дёргано сползает вверх: контент уезжает на высоту клавиатуры, а
  /// карточка в это же время меняет свою. Поэтому смену содержимого
  /// запускаем только когда `viewInsets.bottom` уже вернулся к нулю.
  bool _solvedPending = false;
  Timer? _flipGuard;

  /// Ключ слоя задачи — по нему меряем её высоту (см. [_challengeH]).
  final GlobalKey _slotKey = GlobalKey();

  /// Зафиксированная высота слоя задачи: ровно столько же занимает карточка,
  /// когда в ней появляется «Отлично, ты проснулся!».
  double? _challengeH;

  void _measureChallenge() {
    if (_solved || _solvedPending || !mounted) return;
    final ro = _slotKey.currentContext?.findRenderObject();
    if (ro is! RenderBox) return;
    final h = ro.size.height;
    if (h > (_challengeH ?? 0) + 0.5) {
      setState(() => _challengeH = h);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = AudioPlayer();
    // ReleaseMode выставляется в _playSound перед play: вызов без await отсюда
    // успевал догнать уже запущенный трек, и цикл будильника не держался.
    // Задержка чтобы AudioPlayer инициализировался.
    //
    // Для РЕАЛЬНОГО будильника звук НЕ играем: его уже крутит нативный
    // AlarmForegroundService выбранным файлом — он запущен приёмником и
    // работает даже с погашенным экраном. Раньше играли оба (плюс ещё
    // звук канала уведомления), и втроём это звучало как «будильник
    // звенит каким-то другим звуком». Свой плеер остаётся только для
    // предпросмотра («Тест» в редакторе будильника).
    if (widget.isTest) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _playSound();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flipGuard?.cancel();
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  /// Клавиатура доехала вниз (или её не было) — можно схлопывать карточку.
  @override
  void didChangeMetrics() {
    if (_solvedPending && MediaQuery.viewInsetsOf(context).bottom == 0) {
      _flipNow();
    }
  }

  void _flipNow() {
    _flipGuard?.cancel();
    _flipGuard = null;
    if (!mounted || !_solvedPending) return;
    setState(() {
      _solvedPending = false;
      _solved = true;
    });
  }

  /// Можно ли реально прочитать файл звука.
  ///
  /// Свой файл будильника лежит там, куда его положил системный пикер
  /// (Downloads, Music и т.п.). На Android 13+ у приложения НЕТ права читать
  /// произвольные пути — в манифесте только READ_EXTERNAL_STORAGE с
  /// maxSdkVersion=32, — поэтому `DeviceFileSource` на такой файл бросает
  /// исключение, и тест будильника замолкал совсем. Проверяем открытием на
  /// чтение: `existsSync()` проходит и на недоступный файл, а вот `openSync`
  /// — нет.
  static bool _readable(String path) {
    try {
      final raf = File(path).openSync();
      raf.closeSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Источник звука: свой файл — только если он действительно читается,
  /// иначе встроенный default. Тишины быть не должно ни в одном случае.
  Source _sourceFor(String? name, {bool allowCustom = true}) {
    if (name == 'Custom') {
      final path = widget.customSoundPath;
      if (allowCustom && path != null && _readable(path)) {
        return DeviceFileSource(path);
      }
      debugPrint(
        '[wake-sound] свой файл недоступен для чтения ($path) — играем default',
      );
      return AssetSource('sounds/default.wav');
    }
    switch (name) {
      case 'Gentle':
        return AssetSource('sounds/gentle.wav');
      case 'Classic':
        return AssetSource('sounds/classic.wav');
      case 'Digital':
        return AssetSource('sounds/digital.wav');
      case 'Nature':
        return AssetSource('sounds/nature.wav');
      default:
        return AssetSource('sounds/default.wav');
    }
  }

  /// Попытки запуска звука. Раньше при любой ошибке `catch` запускал
  /// БЕСКОНЕЧНУЮ цепочку повторов через 500 мс: звук молчал, а экран
  /// вечно крутил попытки (именно это вешало виджет-тест с
  /// «A Timer is still pending»). Теперь повторов три, второй и третий —
  /// заведомо рабочий встроенный файл, и каждая ошибка пишется в лог.
  int _playTries = 0;

  Future<void> _playSound() async {
    try {
      // Порядок важен: режим цикла настраиваем ДО play (без await Android
      // успевал запустить трек в обычном режиме, и «петля» будильника не
      // держалась).
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(_sourceFor(_playTries == 0 ? widget.soundName : null));
    } catch (e) {
      _playTries++;
      debugPrint('[wake-sound] попытка $_playTries не сыграла: $e');
      if (!mounted || _playTries >= 3) return;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _playSound();
      });
    }
  }

  Future<void> _finish() async {
    // Плавное затухание вместо резкого stop — без «щелчка» на конце.
    try {
      for (var i = 10; i > 0; i--) {
        await _player.setVolume(i / 10);
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await _player.stop();
      await _player.setVolume(1.0);
    } catch (_) {}
    // Останавливаем нативный звук будильника (MediaPlayer/Ringtone).
    try {
      const MethodChannel(
        'com.wetidom.keramika/alarm_payload',
      ).invokeMethod('stopAlarmSound');
    } catch (_) {}
    if (!mounted) return;

    // Хост (холодный старт по будильнику) сам решает, куда идти дальше.
    if (widget.onDismissed != null) {
      widget.onDismissed!();
      return;
    }

    setState(() {
      _allowPop = true;
    });

    // Small delay to ensure UI updates before popping
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _allowPop) {
        // Для реального будильника закрываем диалог; для теста — просто pop.
        if (!widget.isTest) {
          Navigator.of(context, rootNavigator: true).pop(true);
        } else {
          Navigator.of(context).pop(true);
        }
      }
    });
  }

  void _onSolved() {
    // Клавиатуру убираем ПЕРВОЙ, а содержимое карточки меняем только когда она
    // доехала вниз (см. `_solvedPending` и `didChangeMetrics`): два движения
    // одновременно и давали тот самый дёрганый съезд вверх.
    FocusScope.of(context).unfocus();
    setState(() => _solvedPending = true);
    if (MediaQuery.viewInsetsOf(context).bottom == 0) {
      _flipNow();
    } else {
      // Страховка: метрики не обязательно придут с последним кадром
      // анимации клавиатуры, а запереть пользователя в задаче нельзя.
      _flipGuard = Timer(const Duration(milliseconds: 420), _flipNow);
    }
    // При реальном будильнике — авто-закрытие через 1 секунду после решения
    if (!widget.isTest && mounted) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _solved) _finish();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    // Фон — из цветовой схемы темы (как на ПИН-экране), а не жёстко
    // заданный фиолетовый: на тёмной теме фиолетовое пятно выглядело
    // чужеродно, теперь фон подкрашивается primaryContainer выбранной темы.
    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              cs.surface,
              cs.surfaceContainerLow,
              Color.lerp(cs.surface, cs.primaryContainer, 0.28)!,
            ]
          : [
              cs.surfaceContainerLowest,
              cs.surface,
              Color.lerp(cs.surface, cs.primaryContainer, 0.35)!,
            ],
    );

    return PopScope(
      canPop: _allowPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        // Градиент висит НАД подъёмом по клавиатуре, а не внутри него: тогда
        // полоса высотой с клавиатуру, открывающаяся снизу при подъёме
        // контента, залита тем же градиентом. Раньше её красил плоский
        // scaffoldBackgroundColor, и над клавиатурой стояла чужеродная лента.
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: bgGradient),
          child: SmoothKeyboardBody(
            background: Colors.transparent,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 24,
                ),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(24),
                    // Без BackdropFilter: полноэкранный blur ронял кадры на
                    // Redmi Note 12 и экран выглядел «мыльно» при появлении.
                    // Полупрозрачная «стеклянная» карточка без blur — тот же
                    // вид, но дёшево и чётко.
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.85),
                        width: 1,
                      ),
                      // Тень-«подложка»: карточка читается как отдельное
                      // окно поверх градиента, а не как пятно того же фона.
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.30 : 0.08,
                          ),
                          blurRadius: 28,
                          spreadRadius: -6,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    // Плавный вход: карточка мягко всплывает (fade + подъём)
                    // при появлении экрана — раньше появлялась резко.
                    //
                    // ClipRRect ОБЯЗАТЕЛЕН: decoration скругляет только фон
                    // карточки, но не содержимое. Без него ripple от кнопок и
                    // слои кроссфейда «задача → решено» доезжали до прямых
                    // углов, и окно на весь экран выглядело квадратным.
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, child) => Opacity(
                          opacity: v,
                          child: Transform.translate(
                            offset: Offset(0, 26 * (1 - v)),
                            child: Transform.scale(
                              scale: 0.96 + 0.04 * v,
                              child: child,
                            ),
                          ),
                        ),
                        // Габарит карточки на смене «задача → решено» НЕ
                        // меняется: под слоем задачи зарезервирована его же
                        // высота (`_challengeH`), поэтому перелистывание — чистый
                        // кроссфейд БЕЗ движения. Любая анимация высоты — это
                        // движение, а движение в момент, когда следом за
                        // клавиатурой уезжает ещё и body, глаз и читал как
                        // «дёргано сползает вверх». AnimatedSize до этого
                        // только маскировал рывок: высота в момент перехода
                        // считалась по САМОМУ высокому из двух слоёв
                        // (Stack-раскладка AnimatedSwitcher), и карточка
                        // сначала проседала, потом доезжала до новой.
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: _challengeH ?? 0,
                          ),
                          child: AnimatedSwitcher(
                            // Смена «задача → решено» тоже плавная.
                            duration: const Duration(milliseconds: 380),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: _solved
                                ? KeyedSubtree(
                                    key: const ValueKey('solved'),
                                    child: _buildSolved(context, theme),
                                  )
                                : KeyedSubtree(
                                    key: _slotKey,
                                    child: Builder(
                                      builder: (context) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback(
                                              (_) => _measureChallenge(),
                                            );
                                        return _buildChallenge(context, theme);
                                      },
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.isTest
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(Translations.t('wtDismiss', context)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildSolved(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Значок успеха — в цветах темы, а не жёсткий Colors.green: на
        // розовой/персиковой теме зелёный круг выглядел чужеродно.
        _SuccessBadge(accent: cs.primary),
        const SizedBox(height: 16),
        Text(
          Translations.t('wtSolved', context),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (widget.isTest)
          FilledButton(
            onPressed: _finish,
            child: Text(Translations.t('wtDismiss', context)),
          ),
      ],
    );
  }

  Widget _buildChallenge(BuildContext context, ThemeData theme) {
    switch (widget.taskType) {
      case WakeUpTask.math:
        return _MathChallenge(onSolved: _onSolved);
      case WakeUpTask.pattern:
        return _PatternChallenge(onSolved: _onSolved);
      case WakeUpTask.memory:
        return _MemoryChallenge(onSolved: _onSolved);
      case WakeUpTask.none:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _finish,
              child: Text(Translations.t('wtDismiss', context)),
            ),
          ],
        );
    }
  }
}

class _MathChallenge extends StatefulWidget {
  final VoidCallback onSolved;
  const _MathChallenge({required this.onSolved});

  @override
  State<_MathChallenge> createState() => _MathChallengeState();
}

class _MathChallengeState extends State<_MathChallenge> {
  late int _a, _b, _answer;
  late String _op;
  final _ctrl = TextEditingController();
  bool _wrong = false;

  /// Блокировка после неверного ответа. Без неё «Проверить» можно было тыкнуть
  /// пачкой, и пример перещёлкивался несколько раз за кадр — вместо плавной
  /// смены примеров.
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _generate();
    _ctrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {
      // Строка «неверно» гаснет, как только пользователь начал вводить новый
      // вариант, — высота у неё зарезервирована, поэтому колонка не дёргается.
      if (_wrong && _ctrl.text.isNotEmpty) _wrong = false;
    });
  }

  void _generate() {
    final rng = Random();
    _a = rng.nextInt(20) + 2;
    _b = rng.nextInt(20) + 2;
    final ops = ['+', '×'];
    _op = ops[rng.nextInt(ops.length)];
    switch (_op) {
      case '+':
        _answer = _a + _b;
        break;
      case '×':
        _answer = _a * _b;
        break;
      default:
        _answer = _a + _b;
        break;
    }
  }

  /// Кнопка активна ровно тогда, когда есть что проверять и когда предыдущая
  /// проверка уже отыграла смену примера.
  bool get _canCheck => !_locked && int.tryParse(_ctrl.text.trim()) != null;

  void _check() {
    if (!_canCheck) return;
    final val = int.tryParse(_ctrl.text.trim());
    if (val == _answer) {
      widget.onSolved();
      return;
    }
    setState(() {
      _wrong = true;
      _locked = true;
      _generate();
    });
    _ctrl.clear();
    // 460 мс перекрывает и перелистывание примера (300 мс), и затухание
    // «неверно»: за это время пример обязан смениться ОДНИМ движением.
    Future.delayed(const Duration(milliseconds: 460), () {
      if (!mounted) return;
      setState(() => _locked = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TaskTypeBadge(
            icon: Icons.calculate_rounded,
            a: cs.primary,
            b: cs.tertiary,
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('wtMathTitle', context),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Пример после неверного ответа менялся телепортом (числа
          // перещёлкивались за кадр). Теперь перелистывается.
          _SwapLabel(
            text: '$_a $_op $_b = ?',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: TextField(
              cursorOpacityAnimates: true,
              magnifierConfiguration: TextMagnifierConfiguration.disabled,
              controller: _ctrl,
              // Ответ набираем с клавиатуры: выделение, копирование и вставка
              // в полях задач пробуждения запрещены.
              enableInteractiveSelection: false,
              contextMenuBuilder: noContextMenuBuilder,
              keyboardType: TextInputType.number,
              // Потолок в 10 цифр без счётчика под полем: `maxLength` рисует
              // Material'овский «n/10», который и наезжал, и портил вид.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                LengthLimitingTextInputFormatter(10),
              ],
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(
                hintText: '?',
                // `errorText` здесь убран: Material вставляет подпись ошибки
                // в макет поля, и поле вместе с кнопкой под ним каждый раз
                // перескакивало на высоту ошибки.
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _check(),
            ),
          ),
          _WrongLine(show: _wrong),
          _CheckButton(
            enabled: _canCheck,
            onPressed: _check,
            label: Translations.t('wtCheck', context),
          ),
        ],
      ),
    );
  }
}

class _PatternChallenge extends StatefulWidget {
  final VoidCallback onSolved;
  const _PatternChallenge({required this.onSolved});

  @override
  State<_PatternChallenge> createState() => _PatternChallengeState();
}

class _PatternChallengeState extends State<_PatternChallenge> {
  late List<int> _sequence;
  late List<int> _userInput;
  late int _gridSize;
  bool _showingSequence = true;
  bool _wrong = false;
  int _showStep = 0;

  @override
  void initState() {
    super.initState();
    _gridSize = 3;
    _generate();
    _showSequence();
  }

  void _generate() {
    final rng = Random();
    const len = 3;
    final pool = List<int>.generate(_gridSize * _gridSize, (i) => i)
      ..shuffle(rng);
    _sequence = pool.take(len).toList();
    _userInput = [];
    _showingSequence = true;
    _wrong = false;
    _showStep = 0;
  }

  Future<void> _showSequence() async {
    await Future.delayed(const Duration(milliseconds: 500));
    for (int i = 0; i < _sequence.length; i++) {
      if (!mounted) return;
      setState(() => _showStep = i + 1);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    if (mounted) {
      setState(() {
        _showingSequence = false;
        _showStep = 0;
      });
    }
  }

  void _tap(int idx) {
    if (_showingSequence) return;
    final expected = _sequence[_userInput.length];
    if (idx == expected) {
      _userInput.add(idx);
      setState(() {});
      if (_userInput.length == _sequence.length) {
        widget.onSolved();
      }
    } else {
      setState(() {
        _wrong = true;
        _userInput = [];
        // Экран сразу возвращается в «показ последовательности»: тапы по
        // клеткам в эти 500 мс игнорируются (`_tap` выходил бы на новый
        // пример и запускал повторную генерацию — отсюда и «нажать можно
        // кучу раз», и скачущая сетка).
        _showingSequence = true;
        _showStep = 0;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _generate();
          _showSequence();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final highlightIdx =
        _showingSequence && _sequence.isNotEmpty && _showStep > 0
        ? _sequence.sublist(0, min(_sequence.length, _showStep))
        : <int>[];

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TaskTypeBadge(
            icon: Icons.touch_app_rounded,
            a: cs.primary,
            b: cs.tertiary,
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('wtPatternTitle', context),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // «Смотри» → «0/3» и сами счётчики раньше переключались кадром.
          _SwapLabel(
            text: _showingSequence
                ? Translations.t('wtPatternWatch', context)
                : '${_userInput.length}/${_sequence.length}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          _WrongLine(show: _wrong),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridSize,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _gridSize * _gridSize,
            itemBuilder: (context, i) {
              final isHighlighted = highlightIdx.contains(i);
              return GestureDetector(
                onTap: () => _tap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isHighlighted
                        ? theme.colorScheme.primary
                        : _userInput.contains(i)
                        ? theme.colorScheme.primary.withValues(alpha: 0.3)
                        : theme.colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MemoryChallenge extends StatefulWidget {
  final VoidCallback onSolved;
  const _MemoryChallenge({required this.onSolved});

  @override
  State<_MemoryChallenge> createState() => _MemoryChallengeState();
}

class _MemoryChallengeState extends State<_MemoryChallenge> {
  late List<int> _numbers;
  late int _length;
  bool _showing = true;
  bool _wrong = false;

  /// См. [_MathChallengeState._locked]: «Проверить» не должно работать пачкой.
  bool _locked = false;
  final _ctrls = <TextEditingController>[];
  final _focus = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _length = 4 + Random().nextInt(3);
    _numbers = List.generate(_length, (_) => Random().nextInt(9) + 1);
    _ctrls.clear();
    _focus.clear();
    for (int i = 0; i < _length; i++) {
      _ctrls.add(TextEditingController());
      _focus.add(FocusNode());
    }
    for (final c in _ctrls) {
      c.addListener(_onChanged);
    }
    _showSequence();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {
      if (_wrong) _wrong = false;
    });
  }

  /// Проверять можно только когда заполнены ВСЕ клетки: иначе первый же
  /// незаполненный хвост считался «неверным» и стирал уже введённое.
  bool get _complete {
    for (final c in _ctrls) {
      if (int.tryParse(c.text.trim()) == null) return false;
    }
    return true;
  }

  Future<void> _showSequence() async {
    final showMs = 3000 + _length * 500;
    await Future.delayed(Duration(milliseconds: showMs));
    if (mounted) setState(() => _showing = false);
  }

  void _regenerate() {
    _numbers = List.generate(_length, (_) => Random().nextInt(9) + 1);
  }

  void _check() {
    if (_locked || !_complete) return;
    for (int i = 0; i < _length; i++) {
      final val = int.tryParse(_ctrls[i].text.trim());
      if (val != _numbers[i]) {
        setState(() {
          _wrong = true;
          _locked = true;
          for (final c in _ctrls) {
            c.clear();
          }
        });
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _wrong = false;
              _locked = false;
              _regenerate();
              _showing = true;
            });
            _showSequence();
          }
        });
        return;
      }
    }
    widget.onSolved();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TaskTypeBadge(
            icon: Icons.visibility_rounded,
            a: cs.primary,
            b: cs.tertiary,
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('wtMemoryTitle', context),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _WrongLine(show: _wrong),
          // Пере showing → ввод склеивалась кадром, и сетка полей прыгала
          // ещё и по высоте (плитки 44×44 против полей 44×52). Теперь обе
          // ветки одной высоты, смена — кроссфейд, а рост колонки под
          // кнопку — AnimatedSize.
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1).animate(anim),
                  child: child,
                ),
              ),
              child: _showing
                  ? KeyedSubtree(
                      key: const ValueKey('show'),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_numbers.length, (i) {
                          final n = _numbers[i];
                          return Container(
                            width: 44,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              // Плитка «запомни» в том же стеклянном языке,
                              // что и значок типа: градиент темы + блик
                              // сверху + светлая кромка.
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.lerp(cs.primary, Colors.white, 0.22)!,
                                  cs.tertiary,
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.32),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.34),
                                  blurRadius: 12,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: _PopNumber(
                              key: ValueKey('n$n#$i'),
                              index: i,
                              text: '$n',
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 5,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('input'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(
                              _length,
                              (i) => SizedBox(
                                width: 44,
                                height: 52,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: theme.colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: TextField(
                                      cursorOpacityAnimates: true,
                                      magnifierConfiguration:
                                          TextMagnifierConfiguration.disabled,
                                      controller: _ctrls[i],
                                      // Цифру набираем с клавиатуры: вставка и
                                      // копирование в полях задачи запрещены.
                                      enableInteractiveSelection: false,
                                      contextMenuBuilder: noContextMenuBuilder,
                                      focusNode: _focus[i],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      textAlignVertical:
                                          TextAlignVertical.center,
                                      style: theme.textTheme.titleLarge,
                                      maxLength: 1,
                                      enableSuggestions: false,
                                      autocorrect: false,
                                      decoration: const InputDecoration(
                                        counterText: '',
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isCollapsed: true,
                                      ),
                                      onChanged: (v) {
                                        if (v.isNotEmpty && i < _length - 1) {
                                          _focus[i + 1].requestFocus();
                                        } else if (v.isEmpty && i > 0) {
                                          _focus[i - 1].requestFocus();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _CheckButton(
                            enabled: !_locked && _complete,
                            onPressed: _check,
                            label: Translations.t('wtCheck', context),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка «не верно» на ЗАРЕЗЕРВИРОВАННОМ месте.
///
/// Раньше она вставлялась в колонку через `if (_wrong)` и так же убиралась,
/// поэтому при неверном ответе вся задача подпрыгивала вниз, а после
/// исчезновения — обратно: ровно то «резкое съезжание», от которого экран
/// задач пробуждения и просили почистить. Высота не меняется, меняется
/// только прозрачность.
class _WrongLine extends StatelessWidget {
  final bool show;
  const _WrongLine({required this.show});

  static const _kHeight = 24.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _kHeight,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Text(
          Translations.t('wtWrong', context),
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    );
  }
}

/// Однострочный текст, который при смене значения перелистывается, а не
/// переключается кадром: старое гаснет и уходит вверх, новое приходит снизу.
/// Нужен для вещей, которые менялись телепортом: пример `7 + 12 = ?` после
/// неверного ответа менялся мгновенно, и глаз ловил смену чисел прыжком.
class _SwapLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _SwapLabel({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    // Ширина зафиксирована на всю карточку: без этого AnimatedSwitcher
    // во время перехода держит Stack по самому широкому слою, и короткая
    // строка «8 + 3 = ?» на долю кадра разъезжалась относительно длинной.
    return SizedBox(
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          // Уходящий слой едет ВВЕРХ (он же тот, что уже на месте), а новый
          // поднимается снизу: с одним Tween на оба направления старый уехал бы
          // вниз, и строки разъехались бы в разные стороны.
          final leaving = anim.status == AnimationStatus.reverse;
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, leaving ? -0.4 : 0.4),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          );
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: style,
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      ),
    );
  }
}

/// Значок типа задачи пробуждения — «камень» с фирменным градиентом.
///
/// Раньше это был голый `Icon(outlined, size: 64, color: primary)`: на
/// полупрозрачной стеклянной карточке контурная иконка выглядела сиротской
/// запятой и совсем не была привязана к теме. Теперь — squircle-подложка с
/// градиентом primary→tertiary, верхним бликом, световой кромкой и мягким
/// свечением, то есть тот же язык стекла, что у таблетки разделов и ПИНа.
/// Появляется пружиной, а не одним кадром.
class _TaskTypeBadge extends StatefulWidget {
  final IconData icon;
  final Color a;
  final Color b;

  const _TaskTypeBadge({required this.icon, required this.a, required this.b});

  @override
  State<_TaskTypeBadge> createState() => _TaskTypeBadgeState();
}

class _TaskTypeBadgeState extends State<_TaskTypeBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Реверс кривой в этом Flutter не работает (берёт прямую), поэтому ход
    // «пружины» задаём одной кривой на forward и не разворачиваем её.
    final scale = Tween<double>(
      begin: 0.55,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Opacity(
        opacity: _ctrl.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scale.value,
          alignment: Alignment.center,
          child: child,
        ),
      ),
      child: SizedBox(
        width: 68,
        height: 68,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Свечение ВНЕ клипа: внутри скругления оно обрезалось.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: widget.b.withValues(alpha: 0.38),
                      blurRadius: 24,
                      spreadRadius: -2,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [widget.a, widget.b],
                  ),
                  // Верхний зеркальный блик + светлая нижняя грань.
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.34),
                    width: 1,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.30),
                        Colors.white.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.10),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Icon(
              widget.icon,
              size: 34,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Значок «решено» — та же стеклянность, что у значка типа, только с галкой:
/// прилетает пружиной, кольцо-вспышка расходится один раз и гаснет.
class _SuccessBadge extends StatefulWidget {
  final Color accent;
  const _SuccessBadge({required this.accent});

  @override
  State<_SuccessBadge> createState() => _SuccessBadgeState();
}

class _SuccessBadgeState extends State<_SuccessBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0, 0.62, curve: Curves.easeOutBack),
      ),
    );
    final ring = Tween<double>(begin: 0.6, end: 1.5).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.18, 1, curve: Curves.easeOut),
      ),
    );
    return SizedBox(
      width: 92,
      height: 92,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Transform.scale(
                scale: ring.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.accent.withValues(
                        alpha: 0.5 * (1 - _ctrl.value),
                      ),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            Transform.scale(
              scale: pop.value,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.4),
                    colors: [
                      Color.lerp(widget.accent, Colors.white, 0.35)!,
                      widget.accent,
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.42),
                      blurRadius: 26,
                      spreadRadius: -2,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 42,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0x40000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка «Проверить» с ПЛАВНОЙ сменой доступности.
///
/// `FilledButton(onPressed: null)` переключает серый стиль одним кадром —
/// именно это и просили починить («кнопки проверить на недоступность должны
/// сменяться плавно»). Здесь фон, тень, кромка и цвет подписки перетекают
/// `AnimatedContainer`/`AnimatedDefaultTextStyle`, а габарит не меняется
/// вовсе, поэтому колонка под кнопкой не прыгает.
class _CheckButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onPressed;
  final String label;

  const _CheckButton({
    required this.enabled,
    required this.onPressed,
    required this.label,
  });

  @override
  State<_CheckButton> createState() => _CheckButtonState();
}

class _CheckButtonState extends State<_CheckButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = widget.enabled;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.label,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: GestureDetector(
          // Нажатие «в пустоту» при недоступной кнопке не должно отдавать
          // ложной обратной связи.
          onTap: on ? widget.onPressed : null,
          child: AnimatedScale(
            scale: (_pressed && on) ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: on
                      ? [cs.primary, cs.tertiary]
                      : [cs.surfaceContainerHighest, cs.surfaceContainerHigh],
                ),
                border: Border.all(
                  color: on
                      ? Colors.white.withValues(alpha: 0.26)
                      : cs.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: on ? 0.30 : 0.0),
                    blurRadius: 14,
                    spreadRadius: -2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: on
                      ? cs.onPrimary
                      : cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                child: Text(widget.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Цифра, которая появляется и убирается плавно, а не перещёлкивается кадром.
///
/// Нужна для плиток «запомни числа» в задаче на память: раньше набор цифр
/// возникал одним кадром и так же исчезал при переходе к вводу.
class _PopNumber extends StatelessWidget {
  final String text;
  final TextStyle? style;

  /// Индекс в ряду — по нему считается задержка каскада.
  final int index;

  const _PopNumber({
    super.key,
    required this.text,
    required this.style,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // 90 мс на каждый следующий элемент: цифры набегают волной.
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + 90 * index),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: (v * 3).clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.5 + 0.5 * v, child: child),
      ),
      child: Text(text, style: style),
    );
  }
}
