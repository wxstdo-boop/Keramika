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
part 'lock_screen_painters.dart';

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
    with TickerProviderStateMixin {
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
        PinService.setPin(pinStr);
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
                            Color.lerp(cs.surface, cs.primaryContainer, 0.18)!
                                .withValues(alpha: 0.20),
                          ]
                        : [
                            cs.surface.withValues(alpha: 0.42),
                            Color.lerp(cs.surface, cs.primaryContainer, 0.26)!
                                .withValues(alpha: 0.26),
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
                                // IntrinsicWidth: подчёркивание строго по
                                // ширине текста, концы полоски закруглены.
                                IntrinsicWidth(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.isSetting
                                            ? (_confirmPin == null
                                                  ? Translations.t('setPin', context)
                                                  : Translations.t(
                                                      'confirmPin',
                                                      context,
                                                    ))
                                            : Translations.t('enterPin', context),
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      _WavyUnderline(),
                                    ],
                                  ),
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
List<Widget> _kidFrostedEdges(ColorScheme cs, bool isDark) {
  final tint = isDark ? cs.surfaceContainerLow : cs.surface;
  Widget edge({required bool left}) => Positioned(
    left: left ? 0 : null,
    right: left ? null : 0,
    top: 0,
    bottom: 0,
    child: Container(
      width: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            tint.withValues(alpha: 0.55),
            tint.withValues(alpha: 0.20),
            tint.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    ),
  );
  return [edge(left: true), edge(left: false)];
}

/// ID-капсула на PIN-экране: логотип + название + версия + кнопка «Выйти».
/// Слева — фирменная иконка и название, справа — кнопка выхода,
/// визуально продолжение той же капсулы (одна обводка, один фон).
/// Индикаторы ПИНа: четыре РАЗНЫЕ фигуры (ромб, шестиугольник, капля,
/// восьмиугольник) вместо четырёх одинаковых кружков. Заполненная фигура
/// горит цветом темы с мягким ореолом и градиентом, пустая — только тонкий
/// контур, так что набор цифр читается и как «отметка», и как узор.
/// Индикаторы ПИНа: четыре РАЗНЫЕ фигуры (ромб, шестиугольник, капля,
/// восьмиугольник) вместо четырёх одинаковых кружков. Фигура ПЛАВНО
/// наливается при вводе цифры и плавno высветляется при удалении:
/// TweenAnimationBuilder ведёт прогресс 0↔1 за 560 мс (easeInOutCubic),
/// контур контура растворяется по мере наполнения, заливка с мягким
/// ореолом и бликом проявляется вместе с лёгким «подъёмом» масштаба.
class _PinSlot extends StatelessWidget {
  final int shape;
  final bool filled;
  final Color color;
  final Color ghost;
  const _PinSlot({
    required this.shape,
    required this.filled,
    required this.color,
    required this.ghost,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: filled ? 1 : 0),
      duration: const Duration(milliseconds: 560),
      curve: Curves.easeInOutCubic,
      builder: (context, progress, _) {
        return CustomPaint(
          size: const Size.square(30),
          painter: _PinShapePainter(
            shape: shape,
            progress: progress,
            color: color,
            ghost: ghost,
          ),
        );
      },
    );
  }
}



class _IdBadgeCapsule extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onExit;
  const _IdBadgeCapsule({required this.theme, required this.onExit});

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final textPrimary = isDark ? cs.onSurface : cs.onSurface;

    // Стекло: градиент + полупрозрачность + белый блик + тень
    final glassGrad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.08),
              Colors.white.withValues(alpha: 0.02),
            ]
          : [
              Colors.white.withValues(alpha: 0.45),
              Colors.white.withValues(alpha: 0.15),
            ],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Короткий KID + версия (левая часть) со стеклом + зажатие
        _KIDCapsuleButton(
          isDark: isDark,
          cs: cs,
          glassGrad: glassGrad,
          textPrimary: textPrimary,
        ),
        // Кнопка «Выйти» (правая часть) со стеклом + отдача
        _ExitCapsuleButton(
          isDark: isDark,
          cs: cs,
          glassGrad: glassGrad,
          onExit: onExit,
        ),
      ],
    );
  }
}

/// Левая часть ID-капсулы: KID + версия со стеклом (без зажатия/масштаба).
class _KIDCapsuleButton extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;
  final LinearGradient glassGrad;
  final Color textPrimary;
  const _KIDCapsuleButton({
    required this.isDark,
    required this.cs,
    required this.glassGrad,
    required this.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: glassGrad,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(22),
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.85),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isDark
                        ? cs.onSurface.withValues(alpha: 0.14)
                        : cs.surface.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? cs.outlineVariant.withValues(alpha: 0.4)
                          : cs.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    // Векторная эмблема вместо растрового логотипа: PNG в
                    // 24 px тянулся с потерей деталей и выглядел мылом,
                    // CustomPaint остаётся бритвенно-чётким на любой плотности.
                    child: BrandEmblem(
                      size: 22,
                      color: isDark ? cs.onSurface : cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Без версии — только KID, крупнее и шире, по центру капсулы.
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    'KID',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      letterSpacing: 1.6,
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
}

/// Правая часть ID-капсулы: кнопка «Выйти» со стеклом + плавным
/// «вдавливанием» при нажатии/зажатии.
class _ExitCapsuleButton extends StatefulWidget {
  final bool isDark;
  final ColorScheme cs;
  final VoidCallback onExit;
  final LinearGradient glassGrad;
  const _ExitCapsuleButton({
    required this.isDark,
    required this.cs,
    required this.onExit,
    required this.glassGrad,
  });

  @override
  State<_ExitCapsuleButton> createState() => _ExitCapsuleButtonState();
}

class _ExitCapsuleButtonState extends State<_ExitCapsuleButton> {
  bool _pressed = false;
  Color get accent => widget.isDark ? widget.cs.onSurface : widget.cs.primary;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: widget.onExit,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(22),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                gradient: widget.glassGrad,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(22),
                ),
                border: Border.all(
                  color: _pressed
                      ? widget.cs.primary.withValues(alpha: 0.45)
                      : (widget.isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.85)),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout_rounded, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    Translations.t('exit', context),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accent,
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
}

/// Показывает стеклянное окно подтверждения выхода.
///
/// Возвращается, когда маршрут окна полностью снят (обратная анимация
/// доиграна): по этому моменту вызывающий размораживает тикеры локскрина.
Future<void> _showExitDialog(
  BuildContext context,
  AnimationController glassLoop,
) async {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  // Одна длительность на вход и на выход — её же ждёт задержка перед
  // SystemNavigator.pop() в кнопке «Выйти».
  const glassMs = 380;
  await showGeneralDialog<Object?>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    // Анимация стекла: blur НЕ может жить внутри FadeTransition (слою
    // Opacity не остаётся валидного бэкдропа — экран заливает серым, см.
    // section_pill). Поэтому сам BackdropFilter — В transitionBuilder, и
    // sigma растёт вместе с проходом маршрута: стекло «собирается» с 0 до
    // 16, а контент под ним плавно всплывает и проявляется.
    transitionDuration: const Duration(milliseconds: glassMs),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      // Кривая одна на оба прохода и СИММЕТРИЧНАЯ: плавный старт И плавная
      // остановка. Раньше вперёд шёл easeOutCubic (рывок на старте), а назад
      // easeInCubic — blur почти весь ход висел на ~16 и обваливался в самом
      // конце, а масштаб наоборот уходил рывком; выход из окна читался как
      // «подвисание». easeInOutCubic к тому же мягче по скорости в середине
      // (пик 1.5x против 3x у easeOut) — значит реже выпадает кадр из 16.6 мс.
      //
      // Считается вручную, а НЕ через CurvedAnimation: тот создавался на
      // каждый кадр внутри transitionBuilder, каждый раз навешивая слушателя
      // на родительский animation — за 260 мс это десятки мусорных объектов
      // в самом горячем цикле рендера. Результат идентичен: кривая
      // симметрична, поэтому и в прямом, и в обратном ходе берётся одно
      // и то же значение.
      final t = Curves.easeInOutCubic.transform(animation.value);
      // Размытие теперь на ВЕСЬ экран: раньше BackdropFilter сжимался в
      // ClipRect по области окна (экономия fill-rate), но на границе
      // «размыто/не размыто» оставался видимый прямоугольный шов — при
      // открытии и закрытии он читался как обрубленные куски фона
      // («огрызки»). Полноэкранный бэкдроп рисует однородное стекло без
      // кромок; sigma ниже 16 компенсирует возросшую площадь.
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
        child: Center(
          child: Transform.scale(
            // Ход 0.82 → 1.0 вместо 0.94 → 1.0: при 6% масштабирования окно
            // на 6" экране смещается на ~1 мм за кадр — глаз такую анимацию
            // не регистрирует и «стекло» кажется появляющимся мгновенно.
            scale: 0.82 + 0.18 * t,
            child: Opacity(
              // Проявка заканчивается на середине прохода: контент обязан
              // быть уже видим, пока доигрывают blur и масштаб, иначе
              // первые ~150 мс анимации не показывают вообще ничего.
              opacity: (t * 2).clamp(0.0, 1.0),
              child: child,
            ),
          ),
        ),
      );
    },
    // Material(type: transparency) обязателен: без него showGeneralDialog
    // рисует контент поверх DefaultTextStyle самого MaterialApp, а там
    // лежит отладочный _errorTextStyle — моноширинный 48px красный текст с
    // жёлтым ДВОЙНЫМ подчёркиванием. Наш TextStyle перекрывает размер и
    // цвет, но decoration/decorationColor/decorationStyle наследуются —
    // отсюда и жёлтые подчёркивания. Material возвращает тексту стиль темы.
    pageBuilder: (ctx, _, _) => Material(
      type: MaterialType.transparency,
      child: Container(
        width: 312,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        decoration: BoxDecoration(
          // Полупрозрачное «стеклянное» основание:
          // тёмная тема → почти чёрный фон, светлая → почти белый,
          // чтобы текст всегда читался.
          // Тёмный фон чуть плотнее — на сильном свечении primary он
          // почти не читался, и «бьёт по глазам».
          color: isDark
              ? Colors.black.withValues(alpha: 0.62)
              : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
          // Красивая полупрозрачная обводка в акцентный цвет темы:
          // rose → розовая, peach → персиковая, grok → её акцент.
          border: Border.all(
            color: cs.primary.withValues(alpha: isDark ? 0.35 : 0.38),
            width: 1.5,
          ),
          boxShadow: [
            // Мягкое свечение акцентного цвета вокруг окна.
            BoxShadow(
              color: cs.primary.withValues(alpha: isDark ? 0.18 : 0.20),
              blurRadius: 24,
              spreadRadius: 0,
            ),
            // Дополнительная тень на тёмной теме — контраст к стеклу.
            if (isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 12,
                spreadRadius: 0,
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Стакан поверх мягкого свечения: ореол тянется из того же цвета
            // (cs.primary), поэтому на любом фоне читается «жидкость в свете».
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        cs.primary.withValues(alpha: isDark ? 0.16 : 0.20),
                        cs.primary.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
                _AnimatedGlass(
                  loop: glassLoop,
                  color: cs.primary,
                  isDark: isDark,
                  size: 40,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              Translations.t('exitConfirmTitle', context),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              Translations.t('exitConfirmBody', context),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            // Wrap, а не Row: у диалога жёсткая ширина 312, и в fr («Annuler» +
            // «Quitter») пара кнопок упирается в её край — Row в таком случае
            // рисует overflow-полосу, а Wrap просто переносит «Выйти» на вторую
            // строку. На en/ru, где кнопки влезают, вид не меняется.
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    Translations.t('cancel', context),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: cs.error.withValues(alpha: 0.55),
                      width: 1.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () {
                    // Обратный проход (glassMs) должен успеть отыграть:
                    // SystemNavigator.pop() убивает Activity в том же кадре,
                    // поэтому «стекло» обрывалось на середине и выход выглядел
                    // как резкое исчезание окна. Закрываем диалог из ctx —
                    // маршрут диалога, а не лока, — и гасим приложение после
                    // анимации (+40 мс на кадр конца).
                    Navigator.of(ctx).pop();
                    Future<void>.delayed(
                      const Duration(milliseconds: glassMs + 40),
                      SystemNavigator.pop,
                    );
                  },
                  child: Text(
                    Translations.t('exit', context),
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Маленький стаканчик из шапки диалога — единственное, что здесь
/// анимируется: он покачивается маятником, и напиток внутри плещется.
///
/// Раньше стакан был плоской иконкой, которую крутили вокруг вертикальной
/// оси (rotateY ±50°): на 34 px это читалось как «мигание» — контур дважды
/// за цикл сильно сплющивался. Теперь это CustomPaint, все фазы — синусы
/// от 2πt, поэтому цикл бесшовный:
///
/// * наклон θ(t) = ±7.4°·sin(2πt) — один период за цикл, на склейке витков
///   и угол, и скорость совпадают;
/// * жидкость отвечает на качку физично: её поверхность ВСЕГДА горизонтальна
///   в мировых координатах, а наклонённый стакан отсекается этой
///   полуплоскостью — при наклоне напиток заметно переливается к стенке;
/// * уровень дышит на четверть периода позже наклона (объём подыгрывает
///   качке), и весь стакан плавно левитирует на ±0.4 px.
///
/// Контроллер анимации живёт на уровне LockScreen — при открытии/закрытии
/// диалога анимация не сбрасывается и не начинается заново.
class _AnimatedGlass extends StatelessWidget {
  const _AnimatedGlass({
    required this.loop,
    required this.color,
    required this.isDark,
    this.size = 34,
  });

  final Animation<double> loop;
  final Color color;
  final bool isDark;

  /// Габарит стаканчика (обычный — 34, в диалоге чуть крупнее).
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GlassPainter(
          loop: loop,
          color: color,
          isDark: isDark,
        ),
      ),
    );
  }
}



/// Клавиша нумпада: при нажатии под цифру расходится пятно-брызг фирменного
/// цвета (тот же мотив, что и капли на таблетке разделов) — вместо дефолтного
/// круга. Пятно наливается и стекает плавно, клавиша слегка вдавливается.
class _KeyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  /// Сдвиг формы брызга: у каждой клавиши свой силуэт, иначе все девять
  /// выглядят как одна и та же фигура.
  final double seed;

  const _KeyButton({required this.child, required this.onTap, this.seed = 0});

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> with TickerProviderStateMixin {
  /// Полный ход «появления»: подъём + остывание под удержанием.
  static const _kIn = Duration(milliseconds: 900);
  static const _kOut = Duration(milliseconds: 700);

  /// Доля хода, за которую пятно наливается до максимума.
  static const _kPeak = 0.30;

  /// До чего пятно остывает, если палец всё ещё прижат.
  static const _kFloor = 0.45;

  /// Появление и исчезание пятна — ДВА прямых контроллера.
  ///
  /// Реверс одного не подходит: `reverseCurve` в этой версии Flutter на
  /// обратном ходе не применяется, и пятно «хлопало» в конце вместо плавного
  /// высыхания. Здесь яркость = уровень × (1 − спад), поэтому форму спада
  /// задаёт обычный кривой `easeInOut` и она гарантированно работает.
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: _kIn,
  );
  late final AnimationController _out = AnimationController(
    vsync: this,
    duration: _kOut,
  );

  /// Уровень пигмента по прогрессу удержания: налилось до 1 за первые 30%
  /// хода, дальше ПОД ПАЛЬЦЕМ плавно остывает до 0.45.
  ///
  /// Подъём — именно `easeInOutSine`, а не `easeOutSine`: у ease-out самая
  /// крутая производная стоит на нуле, и первый же кадр давал ~13% яркости
  /// сразу — пятно «вспыхивало» в момент касания. С гладижащей по краям
  /// кривой первые кадры почти неподвижны, а на стыке с веткой остывания
  /// производная тоже нулевая с обеих сторон, поэтому щелчка нет нигде.
  static double _level(double v) {
    if (v <= _kPeak) return Curves.easeInOutSine.transform(v / _kPeak);
    final k = Curves.easeInOutSine.transform((v - _kPeak) / (1 - _kPeak));
    return 1.0 - (1.0 - _kFloor) * k;
  }

  @override
  void dispose() {
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  void _down() {
    _out.reset();
    // Ход ОБЯЗАТЕЛЬНО с нуля: `_up()` оставляет контроллер остановленным на
    // пике (0.30), и `forward()` без `from: 0` продолжал бы с этой точки —
    // второе нажатие той же клавиши давало пятно сразу на 100 % яркости и
    // полностью вжатую клавишу в первом же кадре. Замер покадрово:
    // 1-е нажатие scale 1.000 → 0.963 → 0.934 → … → 0.880 за 9 кадров,
    // 2-е нажатие до правки: 0.880 уже на кадре 0.
    _in.forward(from: 0);
  }

  void _up() {
    // Если палец ушёл раньше пика, короткий тап всё равно дорастает до максимума
    // (остальное время — уже спад). Долгое зажатие замораживается на своём
    // остывшем уровне и оттуда плавно дотухает.
    if (_in.value < _kPeak) {
      final left = _kPeak - _in.value;
      _in.animateTo(
        _kPeak,
        duration: Duration(milliseconds: (_kIn.inMilliseconds * left).round()),
      );
    } else {
      _in.stop();
    }
    _out.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // На тёмной теме primary почти чёрный — пятно читалось бы как тень.
    // Поднимаем СВЕТЛОТУ, оставляя тон и насыщенность: пигмент остаётся
    // фирменным, но видимым (смешивание с белым давало серую кашу).
    final hsl = HSLColor.fromColor(cs.primary);
    final pigment = isDark
        ? hsl
              .withLightness(math.max(0.62, hsl.lightness))
              .withSaturation(math.max(0.55, hsl.saturation))
              .toColor()
        : cs.primary;
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_in, _out]),
          builder: (context, _) {
            final level = _level(_in.value);
            final fall = Curves.easeInOut.transform(_out.value);
            final t = level * (1 - fall);
            // Пока палец прижат, пятно продолжает медленно расползаться — это
            // и есть «плавное появление»; на спаде геометрия уже стоит.
            final spread = Curves.easeOutCubic.transform(_in.value);
            // Клавиша вдавливается мгновенно и возвращается пружиной, а не
            // ждёт 700мс высыхания.
            final press = Curves.easeOutCubic.transform(
              (_in.value / 0.16).clamp(0.0, 1.0),
            );
            final lift = Curves.easeOutCubic.transform(
              (_out.value / 0.26).clamp(0.0, 1.0),
            );
            return Transform.scale(
              scale: 1 - 0.12 * press * (1 - lift),
              // transformHitTests: false — критично. По умолчанию Transform
              // ТРАНСФОРМИРУЕТ и попадания, а клавиша на нажатии тут же
              // садится до 0.88: палец, взятый у самого края (внешние 12%
              // = ~5 логических пикселя), к моменту отпускания оказывался
              // ВНЕ уменьшенной клавиши — GestureDetector рвал onTap, и цифра
              // просто не вводилась. Вид тот же, попадания — по исходному
              // прямоугольнику 80x80.
              transformHitTests: false,
              child: SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _SplatHighlightPainter(
                    t: t,
                    spread: spread,
                    color: pigment,
                    seed: widget.seed,
                  ),
                  child: Center(child: widget.child),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}



/// Эмблема ПИН-экрана вместо стандартного замка: монотонный знак кодового
/// замка — кольцо-корпус, циферблат из двенадцати рисков с указателем полудня
/// и плоская скважина. Всё одним цветом темы, различается только плотность.
/// Вектор, поэтому держит бритвенную чёткость и на 104 px: растровая иконка
/// так бы не могла.
class _PinMedallion extends StatefulWidget {
  final double size;
  const _PinMedallion({required this.size});

  @override
  State<_PinMedallion> createState() => _PinMedallionState();
}

class _PinMedallionState extends State<_PinMedallion>
    with SingleTickerProviderStateMixin {
  /// Цикл 7200 мс: скважина проворачивается на четверть оборота ТУДА и на
  /// четверть ОБРАТНО за первые 86 % цикла, потом коротко отдыхает. Обе
  /// границы — начало и конец гребка — стоят ровно на нулевом угле, поэтому
  /// стык цикла невидим: ни щелчка, ни залипания повёрнутой полости.
  ///
  /// Раньше было 4600 мс при 62 %: пик угловой скорости 372 °/с (6.2° на
  /// кадр 60 Гц), и маховик выглядел лёгким — полость пролетала центр на
  /// скорости, а между гребками висела 1.75 с. Теперь гребок тянется 6.19 с
  /// с пиком 171 °/с (2.85°/кадр), а покой — около секунды: движение стало
  /// тяжелее и почти непрерывное.
  ///
  /// Угол — синус от smootherstep: скорость нулевая и на старте, и в каждом
  /// упоре, поэтому движение читается как ключ в руках, а не как карусель.
  /// Ореол разгорается на каждом из двух доворотов, а бегунок по кромке
  /// крутится весь цикл подряд, так что плашка не выглядит зависшей во время
  /// паузы.
  ///
  /// Раньше цикл шёл через [AmbientVsync] (~20 fps). Для дыхания
  /// прозрачности это незаметно, а вращение на 20 fps глазом читается
  /// именно как дерганье. Теперь это один слой на честных 60 fps, и он
  /// дешёвый: плашка лежит в своём [RepaintBoundary], поэтому грязным
  /// остаётся квадрат ~104×104 лог. px, а не весь экран с витражом.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = cs.primary;
    // Скин скважины дарится на 12-й день ивента и снимается вместе с
    // подарком: после сброса события медальон снова обычный.
    final frost = NewYearEventService().prizeGranted;
    return RepaintBoundary(
      // Граница на всю плашку: перерисовывается только её квадрат, а не
      // страница с витражом. Статичный нижний слой при этом остаётся чистым
      // и заново не растеризуется.
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Корпус и циферблат — статичный слой: он не должен
            // перерисовываться ради движения света.
            CustomPaint(
              size: Size.square(widget.size),
              painter: _MedallionPainter(
                accent: accent,
                isDark: isDark,
                frost: frost,
              ),
            ),
            // Единственный анимированный слой: ореол + бегунок по кромке +
            // скважина, доворачивающаяся вокруг своей оси.
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _MedallionMotionPainter(
                      accent: accent,
                      isDark: isDark,
                      t: _pulse.value,
                      frost: frost,
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
}




/// Угол скважины: пол-оборота В ОДНУ сторону и пол-оборота В ДРУГУЮ
/// (±90° от вертикали), как будто ключ проворачивают туда-обратно.
/// sin(0) == sin(2π) == 0, а производная нулевая и там, и там, так что
/// стык цикла и смена направления не дают ни скачка, ни торможения.
double _medallionTurn(double t) =>
    math.pi / 2 * math.sin(2 * math.pi * _turnEase(t));

/// Дыхание ореола: разгорается на КАЖДОМ довороте (там, где ключ у упора)
/// и гаснет к 0.20 на покое. Косинус с двойной частотой — гладкий, без
/// излома в нуле, и совпадает по значению и скорости на t=0 и t=1.
double _medallionBreath(double t) =>
    0.20 + 0.80 * (0.5 - 0.5 * math.cos(4 * math.pi * _turnEase(t)));

/// Яркость бегунка по ходу цикла: максимум на полудне (оттуда идёт «свет»),
/// минимум в нижней точке. Полный оборот → конец совпадает с началом.
double _medallionGlint(double t) =>
    0.26 + 0.74 * (0.5 + 0.5 * math.cos(t * math.pi * 2));



/// Плавная извилистая красная линия под заголовком «Введите PIN» —
/// полупрозрачная, лёгкая волна, как росчерк кисти.
class _WavyUnderline extends StatelessWidget {
  const _WavyUnderline();

  @override
  Widget build(BuildContext context) {
    // Ширина = доступная (даёт IntrinsicWidth от текста), высота 12.
    // Концы закруглены (StrokeCap.round в пейнтере), поэтому полоска
    // ровно укладывается под границы надписи и не вылезает в стороны.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = (constraints.maxWidth.isFinite ? constraints.maxWidth : 200).toDouble();
        return CustomPaint(
          size: Size(w, 12),
          painter: _WavyLinePainter(
            color: const Color(0xFFB3121F).withValues(alpha: 0.42),
          ),
        );
      },
    );
  }
}


