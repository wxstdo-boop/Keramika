import 'dart:math' as math;
import '../services/haptics.dart';
import 'package:flutter/material.dart';
import '../services/pin_service.dart';
import '../l10n/translations.dart';

class LockScreen extends StatefulWidget {
  final bool isSetting;
  final String? existingPin;
  final VoidCallback? onSet;
  final VoidCallback? onUnlock;

  const LockScreen({
    super.key,
    this.isSetting = false,
    this.existingPin,
    this.onSet,
    this.onUnlock,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  final _pin = <int>[];
  String? _error;
  String? _confirmPin;
  bool _initializing = true;

  static const _pinLength = 4;

  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    if (!widget.isSetting) {
      PinService.hasPin().then((has) {
        if (!has && widget.onUnlock != null) {
          widget.onUnlock!();
        } else {
          if (mounted) setState(() => _initializing = false);
        }
      });
    } else {
      _initializing = false;
    }
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onDigit(int d) {
    if (_pin.length >= _pinLength) return;
    setState(() {
      _pin.add(d);
      _error = null;
    });
    Haptics.select();
    if (_pin.length == _pinLength) {
      _onComplete();
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin.removeLast();
      _error = null;
    });
  }

  void _onComplete() {
    final pinStr = _pin.join();

    if (widget.isSetting) {
      if (_confirmPin == null) {
        // Плавный переход «ввод → подтверждение» (AnimatedSwitcher).
        setState(() {
          _confirmPin = pinStr;
          _pin.clear();
        });
      } else {
        if (pinStr == _confirmPin) {
          PinService.setPin(pinStr);
          widget.onSet?.call();
        } else {
          setState(() {
            _error = 'PINs do not match';
            _pin.clear();
            _confirmPin = null;
          });
          _shake();
          Haptics.heavy();
        }
      }
    } else {
      PinService.verifyPin(pinStr).then((match) {
        if (match) {
          widget.onUnlock?.call();
        } else {
          setState(() {
            _error = 'Wrong PIN';
            _pin.clear();
          });
          _shake();
          Haptics.heavy();
        }
      });
    }
  }

  void _shake() {
    _shakeCtrl.forward(from: 0);
  }

  String get _phaseKey =>
      widget.isSetting ? (_confirmPin == null ? 'set' : 'confirm') : 'unlock';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_initializing) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [Colors.grey[900]!, Colors.deepPurple[900]!, Colors.black87]
                : [Colors.purple[50]!, Colors.white, Colors.pink[50]!],
          ),
        ),
        child: SafeArea(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.8),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  // Переключение «ввод → подтверждение» (и текст, и иконка)
                  // плавно выезжает и уезжает — без мгновенных скачков.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey(_phaseKey),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isSetting
                              ? (_confirmPin == null
                                    ? Icons.lock_outline
                                    : Icons.lock_reset)
                              : Icons.lock_outline,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.isSetting
                              ? (_confirmPin == null
                                    ? Translations.t('setPin', context)
                                    : Translations.t('confirmPin', context))
                              : Translations.t('enterPin', context),
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  // Ошибка появляется/исчезает плавно: AnimatedSize
                  // сглаживает скачок высоты при появлении/исчезновении,
                  // AnimatedSwitcher даёт мягкий фейд — без «дёрганья».
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _error == null
                          ? const SizedBox(key: ValueKey('noerror'), height: 20)
                          : Padding(
                              key: const ValueKey('error'),
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _error == 'Wrong PIN'
                                    ? Translations.t('wrongPin', context)
                                    : _error == 'PINs do not match'
                                    ? Translations.t('pinsDoNotMatch', context)
                                    : _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Точки: «поп» при вводе (AnimatedScale + свечение),
                  // тряска при ошибке (AnimatedBuilder на _shakeCtrl).
                  AnimatedBuilder(
                    animation: _shakeCtrl,
                    builder: (context, child) {
                      final t = _shakeCtrl.value;
                      final dx = t > 0.0
                          ? (t < 0.85
                                ? math.sin(t * math.pi * 6) * 7 * (1 - t)
                                : 0.0)
                          : 0.0;
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pinLength, (i) {
                        final filled = i < _pin.length;
                        return AnimatedScale(
                          scale: filled ? 1.18 : 1.0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: filled
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              boxShadow: filled
                                  ? [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const Spacer(flex: 2),
                  ..._buildNumpad(theme),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNumpad(ThemeData theme) {
    final rows = [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ];

    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((d) => _digitButton(d, theme)).toList(),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 80),
            _digitButton(0, theme),
            _KeyButton(
              onTap: _onDelete,
              child: Icon(
                Icons.backspace_outlined,
                size: 26,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _digitButton(int d, ThemeData theme) {
    return _KeyButton(
      onTap: () => _onDigit(d),
      child: Text(
        '$d',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w300,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Клавиша нумпада с плавным «вдавливанием» при нажатии:
/// при зажатии уменьшается и подсвечивается, при отпускании возвращается.
/// Listener не участвует в gesture-арене — тап доходит до GestureDetector.
class _KeyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _KeyButton({required this.child, required this.onTap});

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _pressed
                  ? theme.colorScheme.primary.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
