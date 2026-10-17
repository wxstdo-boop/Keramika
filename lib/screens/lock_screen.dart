import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import '../services/haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/new_year_event_service.dart';
import '../services/pin_service.dart';
import '../l10n/translations.dart';
import '../utils/jank_probe.dart';
import '../widgets/brand_emblem.dart';

part 'lock_screen_widgets.dart';

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
        // Не `SingleTickerProviderStateMixin`: контроллеров два (тряска и
        // стаканчик), и второй `createTicker` ронял экран в отладочной
        // сборке — из-за этого падали и диалог выхода, и его локализация.
        with
        TickerProviderStateMixin {
  final _pin = <int>[];
  String? _error;
  String? _confirmPin;
  bool _initializing = true;

  static const _pinLength = 4;

  late final AnimationController _shakeCtrl;

  /// ПИН набран полностью и мы ждём/проигрываем исход: ввод блокируем,
  /// иначе 5-й тап во время тряски сбивает состояние.
  bool _resolving = false;

  /// Момент, когда набрана последняя цифра — по нему считаем, сколько ещё
  /// доигрывать подсветку индикаторов (см. [_waitForDots]).
  DateTime? _fullAt;

  /// Контроллер анимации стаканчика — живёт на уровне LockScreen, чтобы
  /// при открытии/закрытии диалога анимация не сбрасывалась и не начиналась
  /// заново. Передаётся в диалог через параметр.
  late final AnimationController _glassLoop;

  @override
  void initState() {
    super.initState();
    // ПИН-экран монтируется НЕ как роут (он `home` у приложения), поэтому
    // NavigatorObserver его не увидит — подписываем сами. Это самый
    // «дорогой» по фонам экран (бэкдроп + пульс медальона), и без подписи в
    // логе кадров он смешался бы с домашним. Базовая метка — чтобы диалог
    // поверх ПИНа после закрытия не оставлял свою подпись на его кадрах.
    JankProbe.setBaseLabel('lock');
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _glassLoop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
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
    _glassLoop.dispose();
    super.dispose();
  }

  void _onDigit(int d) {
    if (_resolving || _pin.length >= _pinLength) return;
    setState(() {
      _pin.add(d);
      _error = null;
    });
    Haptics.select();
    // Роняем пятно из-под KID-капсулы: x зависит от нажатой цифры
    // (цифры 1-9 стоят в три ряда, x = 0.3, 0.5, 0.7 для колонок).
    if (_pin.length == _pinLength) {
      _fullAt = DateTime.now();
      _onComplete();
    }
  }

  void _onDelete() {
    if (_resolving || _pin.isEmpty) return;
    setState(() {
      _pin.removeLast();
      _error = null;
    });
  }

  /// Сколько ещё ждать, чтобы последняя точка УСПЕЛА подсветиться.
  ///
  /// Индикаторы анимируются 320 мс через AnimatedContainer, плюс кадр на
  /// старт анимации, а `verifyPin` — асинхронный: раньше переход на главный
  /// экран стартовал через кадр после 4-й цифры, и точка либо не доезжала до
  /// цвета, либо гасла на середине. Хеш обычно считается быстрее подсветки,
  /// поэтому держим экран ровно до конца подсветки (минус уже прошедшие
  /// миллисекунды).
  Future<void> _waitForDots({int total = 330}) async {
    final at = _fullAt;
    if (at == null) return;
    final left = total - DateTime.now().difference(at).inMilliseconds;
    if (left > 0) await Future.delayed(Duration(milliseconds: left));
  }

  /// Неправильный ПИН: трясём ЗАПОЛНЕННЫЕ точки и только потом гасим —
  /// сброс в тот же кадр выглядел как «индикаторы мигнули и пропали».
  void _reject(String message) {
    _shake();
    Haptics.heavy();
    setState(() => _error = message);
    Future.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      setState(() {
        _pin.clear();
        _fullAt = null;
        _resolving = false;
      });
    });
  }

  Future<void> _onComplete() async {
    final pinStr = _pin.join();

    if (widget.isSetting) {
      await _waitForDots();
      if (!mounted) return;
      if (_confirmPin == null) {
        setState(() {
          _confirmPin = pinStr;
          _pin.clear();
          _fullAt = null;
        });
      } else if (pinStr == _confirmPin) {
        _resolving = true;
        await PinService.setPin(pinStr);
        widget.onSet?.call();
      } else {
        _reject('PINs do not match');
        // Ошибка — начинаем заново, включая первый ввод.
        Future.delayed(const Duration(milliseconds: 420), () {
          if (mounted) setState(() => _confirmPin = null);
        });
      }
      return;
    }

    final match = await PinService.verifyPin(pinStr);
    await _waitForDots();
    if (!mounted) return;
    if (match) {
      _resolving = true;
      widget.onUnlock?.call();
    } else {
      _reject('Wrong PIN');
    }
  }

  void _shake() {
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _openExitDialog() async {
    await _showExitDialog(context, _glassLoop);
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

    final cs = theme.colorScheme;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
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
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Стекло окна KID ПРозрачнее, чем было: раньше плотный
                  // слой surface (0.5/0.7) на пол-экрана глушил фирменный
                  // градиент темы — «пропал красивый фон». Теперь градиент
                  // читается сквозь стекло, а читается контент потому, что
                  // сам фон темы — спокойный, без контрастных узоров.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            cs.surfaceContainerLow.withValues(alpha: 0.34),
                            Color.lerp(
                              cs.surface,
                              cs.primaryContainer,
                              0.18,
                            )!.withValues(alpha: 0.20),
                          ]
                        : [
                            cs.surface.withValues(alpha: 0.42),
                            Color.lerp(
                              cs.surface,
                              cs.primaryContainer,
                              0.26,
                            )!.withValues(alpha: 0.26),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark
                        ? cs.outlineVariant.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.8),
                    width: 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Бока окна KID: узкие полосы дымки по краям стекла.
                    ..._kidFrostedEdges(cs, isDark),
                    Column(
                      children: [
                        // ID-капсула: логотип + название/версия слева,
                        // кнопка «Выйти» как продолжение капсулы справа.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: _IdBadgeCapsule(
                            theme: theme,
                            onExit: _openExitDialog,
                          ),
                        ),
                        const Spacer(flex: 2),
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
                              const _PinMedallion(size: 104),
                              const SizedBox(height: 18),
                              _PinPrompt(
                                text: widget.isSetting
                                    ? (_confirmPin == null
                                          ? Translations.t('setPin', context)
                                          : Translations.t(
                                              'confirmPin',
                                              context,
                                            ))
                                    : Translations.t('enterPin', context),
                                style: theme.textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: _error == null
                                ? const SizedBox(
                                    key: ValueKey('noerror'),
                                    height: 20,
                                  )
                                : Padding(
                                    key: const ValueKey('error'),
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.error
                                            .withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: theme.colorScheme.error
                                              .withValues(alpha: 0.35),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        _error == 'Wrong PIN'
                                            ? Translations.t(
                                                'wrongPin',
                                                context,
                                              )
                                            : _error == 'PINs do not match'
                                            ? Translations.t(
                                                'pinsDoNotMatch',
                                                context,
                                              )
                                            : _error!,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        AnimatedBuilder(
                          animation: _shakeCtrl,
                          builder: (context, child) {
                            final t = _shakeCtrl.value;
                            final dx = t > 0.0
                                ? (t < 0.92
                                      ? math.sin(t * math.pi * 4) *
                                            9 *
                                            (1 - t) *
                                            (1 - t)
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
                              final c = theme.colorScheme;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: _PinSlot(
                                  shape: i % 4,
                                  filled: filled,
                                  color: c.primary,
                                  ghost: c.outlineVariant,
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
                  ],
                ),
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
              seed: 9.3,
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
      seed: d * 1.7 + 0.4,
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

/// Боковые полосы «морозного» градиента для карточки KID: узкая кромка
/// дымки у края окна, растворяющаяся к центру.
///
/// Раньше под градиентом тут лежал BackdropFilter(sigma 9) — и это была
/// главная статья расхода PIN-экрана: каждый кадр (пусть даже когда за
/// окном ничего не меняется) заставлял растеризатор заново читать бэкдроп
/// и пересчитывать размытие, потому что ниже живут анимируемые пятна и
/// медальон. Замер с телефона давал raster ≈ 22 мс при бюджете 16.6 мс.
///
/// Визуально blur здесь был бесплатным и стал не нужен: за кромкой лежит
/// только гладкий градиент фона (пятна из колонны DripBackdrop идут в
/// середине экрана, xSpread 0.62, и до краёв не доходят), а размытие
/// градиента даёт тот же градиент. Оставляем один градиент дымки —
/// вид «стекла по краям» сохраняется, растеризация кромки становится
/// обычной заливкой.
