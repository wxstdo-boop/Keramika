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
  const WakeTaskScreen({
    super.key,
    required this.taskType,
    this.isTest = true,
    this.soundName,
    this.customSoundPath,
  });

  @override
  State<WakeTaskScreen> createState() => _WakeTaskScreenState();
}

class _WakeTaskScreenState extends State<WakeTaskScreen> {
  bool _solved = false;
  bool _allowPop = false;
  late final AudioPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setReleaseMode(ReleaseMode.loop);
    // Задержка чтобы AudioPlayer инициализировался.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _playSound();
    });
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Source? _soundSource() {
    final name = widget.soundName;
    if (name == 'Custom' && widget.customSoundPath != null) {
      return DeviceFileSource(widget.customSoundPath!);
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

  Future<void> _playSound() async {
    try {
      final source = _soundSource();
      if (source != null) {
        await _player.play(source);
      }
    } catch (e) {
      // Повторяем через 500мс если не удалось.
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _playSound();
        });
      }
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
    setState(() => _solved = true);
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

    return PopScope(
      canPop: _allowPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SmoothKeyboardBody(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.grey[900]!,
                        Colors.deepPurple[900]!,
                        Colors.black87,
                      ]
                    : [Colors.purple[50]!, Colors.white, Colors.pink[50]!],
              ),
            ),
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
                    ),
                    // Плавный вход: карточка мягко всплывает (fade + подъём)
                    // при появлении экрана — раньше появлялась резко.
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
                      child: AnimatedSwitcher(
                        // Смена «задача → решено» тоже плавная.
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.94,
                              end: 1.0,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _solved
                            ? KeyedSubtree(
                                key: const ValueKey('solved'),
                                child: _buildSolved(context, theme),
                              )
                            : KeyedSubtree(
                                key: const ValueKey('challenge'),
                                child: _buildChallenge(context, theme),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 80, color: Colors.green[400]),
        const SizedBox(height: 16),
        Text(
          Translations.t('wtSolved', context),
          style: theme.textTheme.headlineSmall,
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
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

  void _check() {
    final val = int.tryParse(_ctrl.text.trim());
    if (val == _answer) {
      widget.onSolved();
    } else {
      setState(() {
        _error = Translations.t('wtWrong', context);
        _generate();
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calculate_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('wtMathTitle', context),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            '$_a $_op $_b = ?',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: TextField(
              magnifierConfiguration: TextMagnifierConfiguration.disabled,
              controller: _ctrl,
              contextMenuBuilder: minimalContextMenuBuilder,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
              decoration: InputDecoration(
                hintText: '?',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _check(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _check,
            child: Text(Translations.t('wtCheck', context)),
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
    final highlightIdx =
        _showingSequence && _sequence.isNotEmpty && _showStep > 0
        ? _sequence.sublist(0, min(_sequence.length, _showStep))
        : <int>[];

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('wtPatternTitle', context),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _showingSequence
                ? Translations.t('wtPatternWatch', context)
                : '${_userInput.length}/${_sequence.length}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_wrong)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                Translations.t('wtWrong', context),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
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
    _showSequence();
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
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
    for (int i = 0; i < _length; i++) {
      final val = int.tryParse(_ctrls[i].text.trim());
      if (val != _numbers[i]) {
        setState(() {
          _wrong = true;
          for (final c in _ctrls) {
            c.clear();
          }
        });
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            setState(() {
              _wrong = false;
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('wtMemoryTitle', context),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_showing)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: _numbers
                  .map(
                    (n) => Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$n',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            )
          else ...[
            if (_wrong)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  Translations.t('wtWrong', context),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
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
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: TextField(
                        magnifierConfiguration:
                            TextMagnifierConfiguration.disabled,
                        controller: _ctrls[i],
                        contextMenuBuilder: minimalContextMenuBuilder,
                        focusNode: _focus[i],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        style: theme.textTheme.titleLarge,
                        maxLength: 1,
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
            FilledButton(
              onPressed: _check,
              child: Text(Translations.t('wtCheck', context)),
            ),
          ],
        ],
      ),
    );
  }
}
