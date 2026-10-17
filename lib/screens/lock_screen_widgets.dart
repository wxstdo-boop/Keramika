part of 'lock_screen.dart';

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

class _PinShapePainter extends CustomPainter {
  final int shape;

  /// 0 — пустая фигура (только контур), 1 — полностью залита.
  final double progress;
  final Color color;
  final Color ghost;
  _PinShapePainter({
    required this.shape,
    required this.progress,
    required this.color,
    required this.ghost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final r = size.width * 0.44;
    final path = _pathFor(shape, c, r);
    final pr = progress.clamp(0.0, 1.0);

    // Пустой контур: виден, пока фигура не залита; растворяется вместе
    // с наполнением, чтобы не «двойнить» линии.
    if (pr < 0.999) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = ghost.withValues(alpha: 0.6 * (1 - pr)),
      );
    }

    // Заливка: появляется со своей скоростью и лёгким «подъёмом».
    if (pr > 0.001) {
      final s = 0.92 + 0.08 * pr;
      canvas.save();
      canvas.translate(c, c);
      canvas.scale(s);
      canvas.translate(-c, -c);
      // Мягкий внешний ореол.
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35 * pr)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Основная заливка + тонкий верхний блик для объёма.
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: pr));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c - r * 0.25, c - r * 0.35),
          width: r * 0.9,
          height: r * 0.45,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.14 * pr),
      );
      canvas.restore();
    }
  }

  Path _pathFor(int shape, double c, double r) {
    final p = Path();
    switch (shape) {
      case 0:
        // Ромб.
        p.moveTo(c, c - r);
        p.lineTo(c + r, c);
        p.lineTo(c, c + r);
        p.lineTo(c - r, c);
        p.close();
        break;
      case 1:
        // Шестиугольник.
        for (int i = 0; i < 6; i++) {
          final a = -math.pi / 2 + i * math.pi / 3;
          final x = c + r * math.cos(a);
          final y = c + r * math.sin(a);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
        break;
      case 2:
        // Капля (острый кончик сверху, округлое дно).
        final tipY = c - r;
        final botY = c + r * 0.9;
        final w = r * 0.78;
        p.moveTo(c, tipY);
        p.cubicTo(c + w, c - r * 0.05, c + w, botY - r * 0.4, c, botY);
        p.cubicTo(c - w, botY - r * 0.4, c - w, c - r * 0.05, c, tipY);
        p.close();
        break;
      default:
        // Восьмиугольник.
        for (int i = 0; i < 8; i++) {
          final a = math.pi / 8 + i * math.pi / 4;
          final x = c + r * 0.92 * math.cos(a);
          final y = c + r * 0.92 * math.sin(a);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
    }
    return p;
  }

  @override
  bool shouldRepaint(_PinShapePainter old) =>
      old.shape != shape ||
      old.progress != progress ||
      old.color != color ||
      old.ghost != ghost;
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
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
        painter: _GlassPainter(loop: loop, color: color, isDark: isDark),
      ),
    );
  }
}

/// Рисует стакан с плещущейся жидкостью по фазе [loop] (0..1).
class _GlassPainter extends CustomPainter {
  _GlassPainter({required this.loop, required this.color, required this.isDark})
    : super(repaint: loop);

  final Animation<double> loop;
  final Color color;
  final bool isDark;

  /// Наклон-маятник: ±7.4° — заметно, но силуэт стакана всё время читается.
  static const double _tiltAmp = 0.13;

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value;
    final phase = _tau * t;
    final s = size.shortestSide;
    final cx = size.width / 2;

    // Лёгкая левитация: ±1.2% габарита; косинус на склейке витков совпадает.
    final bob = math.cos(phase) * s * 0.012;
    final cy = size.height / 2 + bob;

    final rimW = s * 0.60;
    final botW = s * 0.42;
    final gh = s * 0.62;
    final rimY = cy - gh / 2;
    final botY = cy + gh / 2;

    final theta = _tiltAmp * math.sin(phase);
    final pivot = Offset(cx, cy);
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    Offset rot(Offset p) {
      final dx = p.dx - pivot.dx;
      final dy = p.dy - pivot.dy;
      return Offset(
        pivot.dx + dx * cosT - dy * sinT,
        pivot.dy + dx * sinT + dy * cosT,
      );
    }

    // Наклонённый силуэт стакана (острые кромки сверху, скруглённое дно).
    final quad = <Offset>[
      rot(Offset(cx - rimW / 2, rimY)),
      rot(Offset(cx + rimW / 2, rimY)),
      rot(Offset(cx + botW / 2, botY)),
      rot(Offset(cx - botW / 2, botY)),
    ];
    final glass = _glassPath(quad, s * 0.055);

    // Стекло: лёгкая заливка в тон акцента — контур дорисуем поверх.
    canvas.drawPath(
      glass,
      Paint()..color = color.withValues(alpha: isDark ? 0.10 : 0.08),
    );

    // Жидкость: уровень на четверть периода позже наклона.
    final fill = 0.44 + 0.045 * math.sin(phase - math.pi / 2);
    final surfaceY = botY - gh * fill;
    final liquid = _clipBelow(quad, surfaceY);
    if (liquid.length >= 3) {
      final path = Path()..moveTo(liquid.first.dx, liquid.first.dy);
      for (final p in liquid.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();

      canvas.save();
      canvas.clipPath(glass);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                color,
                Colors.white,
                0.18,
              )!.withValues(alpha: isDark ? 0.88 : 0.80),
              color.withValues(alpha: isDark ? 0.96 : 0.90),
            ],
          ).createShader(path.getBounds()),
      );
      // Кромка жидкости: в мировых координатах это ровная горизонталь —
      // качается стакан, а поверхность напитка остаётся спокойной.
      final edge = liquid.where((p) => (p.dy - surfaceY).abs() < 0.05).toList();
      if (edge.length >= 2) {
        edge.sort((a, b) => a.dx.compareTo(b.dx));
        canvas.drawLine(
          edge.first,
          edge.last,
          Paint()
            ..color = Color.lerp(
              color,
              Colors.white,
              0.45,
            )!.withValues(alpha: isDark ? 0.55 : 0.45)
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();
    }

    // Контур поверх заливок — стенки не «замываются» жидкостью.
    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.95),
    );

    // Блик у левой стенки — объём «на просвет».
    canvas.drawLine(
      rot(Offset(cx - rimW * 0.30, rimY + gh * 0.16)),
      rot(Offset(cx - rimW * 0.20, botY - gh * 0.18)),
      Paint()
        ..color = Colors.white.withValues(alpha: isDark ? 0.34 : 0.62)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Силуэт стакана: трапеция со скруглённым дном.
  static Path _glassPath(List<Offset> q, double r) {
    final tl = q[0], tr = q[1], br = q[2], bl = q[3];
    Offset toward(Offset from, Offset to, double d) {
      final v = to - from;
      return from + v / v.distance * d;
    }

    final brA = toward(br, tr, r);
    final brB = toward(br, bl, r);
    final blA = toward(bl, br, r);
    final blB = toward(bl, tl, r);
    return Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(brA.dx, brA.dy)
      ..quadraticBezierTo(br.dx, br.dy, brB.dx, brB.dy)
      ..lineTo(blA.dx, blA.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, blB.dx, blB.dy)
      ..close();
  }

  /// Отсечение выпуклого четырёхугольника полуплоскостью y ≥ [ys]
  /// (Сазерленд–Ходжман для одной плоскости).
  static List<Offset> _clipBelow(List<Offset> poly, double ys) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final aIn = a.dy >= ys;
      final bIn = b.dy >= ys;
      if (aIn) out.add(a);
      if (aIn != bIn) {
        final k = (ys - a.dy) / (b.dy - a.dy);
        out.add(Offset(a.dx + (b.dx - a.dx) * k, ys));
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.loop != loop || old.color != color || old.isDark != isDark;
}

const double _tau = math.pi * 2;

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

/// Пятно от нажатия: блин с рваным краем, стекающей вниз гранью и несколькими
/// брызгами-спутниками, которые вылетают чуть позже самого пятна.
class _SplatHighlightPainter extends CustomPainter {
  /// Яркость: 0 → 1 на подъёме, 1 → 0 на высыхании.
  final double t;

  /// Геометрия пятна (0 → 1 и чуть дальше): отдельно от яркости, чтобы
  /// высыхающее пятно расползалось, а не сжималось назад.
  final double spread;
  final Color color;
  final double seed;

  const _SplatHighlightPainter({
    required this.t,
    required this.spread,
    required this.color,
    required this.seed,
  });

  /// Единичное пятно (центр 0,0, радиус 1) на заданный seed.
  ///
  /// Геометрия `_blob` линейна по радиусу: точка = центр + r·f(угол, seed),
  /// поэтому путь достаточно построить ОДИН раз на seed, а дальше гонять его
  /// через `Path.transform` (один вызов вместо 45 moveTo/lineTo и 9 пар
  /// sin/cos на каждый кадр). Раньше пересборка шла ≈96 раз за одно зажатие
  /// клавиши, и вместе со свечением через MaskFilter это давало ощутимые
  /// просадки именно в момент нажатия — на слабом Adreno 610.
  ///
  /// Масштаб берём из path, а НЕ из CTM канваса: `MaskFilter.blur` задан в
  /// пикселях устройства, и трансформация канваса по-разному трактуется
  /// движками, а пиксельный результат обязан остаться прежним.
  static final Map<double, Path> _unitBlobs = {};

  static Path _unitBlob(double phase) {
    final cached = _unitBlobs[phase];
    if (cached != null) return cached;
    final path = Path();
    const n = 44;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final w =
          1 +
          0.14 * math.sin(a * 3 + phase) +
          0.09 * math.sin(a * 5 + phase * 1.7) +
          0.05 * math.sin(a * 9 + phase * 0.6);
      final drip = math.max(0.0, math.sin(a)) * 0.18;
      final x = math.cos(a) * w;
      final y = math.sin(a) * (w * 0.9 + drip);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    // Ключей реально 10 штук (по числу клавиш), потолок — на вырост.
    if (_unitBlobs.length > 32) _unitBlobs.clear();
    _unitBlobs[phase] = path;
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.004) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * (0.30 + 0.13 * spread);
    // Тот же контур, что и раньше: единичный путь, растянутый на r и
    // перенесённый в центр клавиши. Матрица записана столбцами напрямую
    // (X-базис, Y-базис, Z-базис, перенос) — так же, как делает Matrix4, но
    // без его deprecated-метода scale.
    final blob = _unitBlob(seed).transform(
      Float64List.fromList(<double>[
        r, 0, 0, 0, //
        0, r, 0, 0, //
        0, 0, 1, 0, //
        c.dx, c.dy, 0, 1, //
      ]),
    );
    // Сначала — свечение тем же цветом (эффект = цвет + свет, а не размер),
    // поверх него уже сам пигмент с рваным краем.
    canvas.drawPath(
      blob,
      Paint()
        ..color = color.withValues(alpha: 0.26 * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.34),
    );
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.62 * t),
          color.withValues(alpha: 0.44 * t),
          color.withValues(alpha: 0.16 * t),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.3));
    canvas.drawPath(blob, paint);

    // Брызги-спутники: стартуют с задержкой, поэтому нажатие читается как
    // удар капли, а не как появление лужи.
    for (var k = 0; k < 3; k++) {
      final tk = ((t - 0.22 - 0.14 * k) / 0.62).clamp(0.0, 1.0);
      if (tk <= 0) continue;
      final a = seed * 1.3 + k * 2.2;
      final d = r * (1.12 + 0.16 * k);
      final p = Offset(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d * 0.82);
      canvas.drawCircle(
        p,
        size.width * (0.028 + 0.022 * k % 2) * tk,
        Paint()..color = color.withValues(alpha: 0.44 * tk),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplatHighlightPainter old) =>
      old.t != t ||
      old.spread != spread ||
      old.color != color ||
      old.seed != seed;
}

/// Палитра подарочного скина «Метель»: северное сияние по белому снегу —
/// мята, ледяная лазурь и фиолет. Только для скина ПИН-скважины; обычные
/// темы остаются на акценте темы.
const List<Color> _kAurora = [
  Color(0xFF2FBF94),
  Color(0xFF4FB6E8),
  Color(0xFF7C6BE0),
];

/// Цвет сияния по позиции 0 → 1 по кругу (стык плавный: конец = начало).
Color _auroraAt(double x) {
  final p = (x % 1.0) * _kAurora.length;
  final i = p.floor() % _kAurora.length;
  final j = (i + 1) % _kAurora.length;
  return Color.lerp(_kAurora[i], _kAurora[j], p - p.floor())!;
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
                child: CustomPaint(
                  painter: _MedallionMotionPainter(
                    accent: accent,
                    isDark: isDark,
                    pulse: _pulse,
                    frost: frost,
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

/// Монотонная эмблема ПИН-экрана: ОДИН цвет темы, разнится только плотность.
///
/// Никаких градиентов, фасок, бликов, каустик и искр — вся «красивость»
/// держится на геометрии: корпус-кольцо, циферблат из двенадцати рисков и
/// указатель полудня. Скважина здесь не рисуется — она уехала в
/// [_MedallionMotionPainter] и проворачивается вместе со светом. Такой знак
/// читается и на 104 px, и на 24 px, и не рассыпается в кашу на слабом GPU.
class _MedallionPainter extends CustomPainter {
  final Color accent;
  final bool isDark;

  /// Скин «Метель» (подарок 12-го дня): корпус и риски циферблата горят
  /// северным сиянием вместо одного тона темы.
  final bool frost;

  _MedallionPainter({
    required this.accent,
    required this.isDark,
    this.frost = false,
  });

  /// Один тон, разная прозрачность — единственный «цветовой» приём здесь.
  Paint _ink(double a, {double? w}) => Paint()
    ..isAntiAlias = true
    ..color = accent.withValues(alpha: a)
    ..strokeWidth = w ?? 0
    ..style = w == null ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double u(double v) => v * s;
    final c = Offset(s / 2, s / 2);
    final outer = u(0.44);

    // Подложка чуть плотнее фона — плашка есть, а «стекла» нет.
    canvas.drawCircle(
      c,
      outer,
      // Скобки обязательны: каскад `..` нельзя ставить прямо в ветке
      // тернарного оператора — анализатор читает его как каскад к ВСЕМУ
      // выражению `frost ? … : …` и ломается на `Expected an identifier`.
      frost
          ? (Paint()
              ..color = _kAurora[1].withValues(alpha: isDark ? 0.16 : 0.12))
          : _ink(isDark ? 0.15 : 0.10),
    );
    if (frost) {
      // Корпус сияющей лентой: SweepGradient по кругу — тот же один шейдер,
      // что и у обычного мазка кисти, размытия и масок нет.
      canvas.drawCircle(
        c,
        outer,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(0.024)
          ..shader = SweepGradient(
            colors: [..._kAurora, _kAurora.first],
          ).createShader(Rect.fromCircle(center: c, radius: outer)),
      );
    } else {
      // Корпус.
      canvas.drawCircle(c, outer, _ink(isDark ? 0.66 : 0.78, w: u(0.024)));
    }
    // Волосок внутренней окружности: разделяет корпус и циферблат.
    canvas.drawCircle(c, u(0.335), _ink(0.26, w: u(0.010)));

    _dial(canvas, u, c);
  }

  /// Циферблат: двенадцать рисков между корпусом и внутренней окружностью.
  /// Крупные (каждая третья) плотнее и шире, мелкие — только намёк. На
  /// полудне вместо риска указатель-треугольник: он задаёт «верх» знака.
  void _dial(Canvas canvas, double Function(double) u, Offset c) {
    Paint inkAt(double a, int i, {double? w}) =>
        frost ? _auroraPaint(a, i / 12, w: w) : _ink(a, w: w);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      if (i == 0) {
        final perp = Offset(-dir.dy, dir.dx);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + dir.dx * u(0.348), c.dy + dir.dy * u(0.348))
            ..lineTo(
              c.dx + dir.dx * u(0.410) + perp.dx * u(0.030),
              c.dy + dir.dy * u(0.410) + perp.dy * u(0.030),
            )
            ..lineTo(
              c.dx + dir.dx * u(0.410) - perp.dx * u(0.030),
              c.dy + dir.dy * u(0.410) - perp.dy * u(0.030),
            )
            ..close(),
          inkAt(0.95, i),
        );
        continue;
      }
      final major = i % 3 == 0;
      canvas.drawLine(
        c + dir * u(major ? 0.358 : 0.378),
        c + dir * u(0.410),
        inkAt(major ? 0.72 : 0.30, i, w: u(major ? 0.024 : 0.012))
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Краска риски в скине «Метель»: тон сияния на своей позиции по кругу.
  Paint _auroraPaint(double a, double pos, {double? w}) => Paint()
    ..isAntiAlias = true
    ..color = _auroraAt(pos).withValues(alpha: a)
    ..strokeWidth = w ?? 0
    ..style = w == null ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  bool shouldRepaint(covariant _MedallionPainter old) =>
      old.accent != accent || old.isDark != isDark || old.frost != frost;
}

/// Доля цикла, за которую скважина проворачивается туда и обратно;
/// остальное — короткий покой на нулевом угле.
const double _kTurnSpan = 0.86;

/// Прогресс поворота 0 → 1 smootherstep'ом: скорость равна нулю и на
/// старте, и в момент, когда полость доворачивается до упора, — поэтому
/// движение начинается и заканчивается без рывка.
double _turnEase(double t) {
  final x = (t / _kTurnSpan).clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
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

/// Анимированный слой плашки: ореол вокруг корпуса, световой бегунок по его
/// кромке и чёрная скважина, которая вечно доворачивается вокруг своей оси.
///
/// Всё одним тоном и без saveLayer: ни blur, ни Shader-масок — только
/// RadialGradient-шейдер на ореоле, translate/rotate на скважине и обычные
/// дуги хвоста. На Adreno 610 размытие или маска стоили бы дороже всей плашки.
class _MedallionMotionPainter extends CustomPainter {
  final Color accent;
  final bool isDark;

  /// Контроллер цикла: painter читает точное значение в момент paint,
  /// минуя AnimatedBuilder и создание нового delegate на каждый кадр.
  final Animation<double> pulse;
  double get t => pulse.value;

  /// Скин «Метель»: свет становится северным сиянием — ореол, бегунок и
  /// обводка скважины переливаются по палитре, вокруг корпуса кружат
  /// снежинки-искры. Геометрия и тайминг те же, что в обычном медальоне.
  final bool frost;

  _MedallionMotionPainter({
    required this.accent,
    required this.isDark,
    required this.pulse,
    this.frost = false,
  }) : super(repaint: pulse);

  /// Шаг хвоста и число штрихов — в долях полного оборота.
  static const double _step = 1 / 44;
  static const int _tail = 9;

  /// Краска мазка: тон темы или, в скине, сияние на позиции [pos] по кругу.
  Color _tone(double pos) => frost ? _auroraAt(pos) : accent;

  Paint _ink(double a, {double? w, double pos = 0}) => Paint()
    ..isAntiAlias = true
    ..color = _tone(pos).withValues(alpha: a)
    ..strokeWidth = w ?? 0
    ..style = w == null ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final tau = math.pi * 2;
    _halo(canvas, s, c, _medallionBreath(t));
    _runner(canvas, s, c, tau);
    _keyhole(canvas, s, c, _medallionTurn(t));
    if (frost) _sparks(canvas, s, c, tau);
  }

  /// Свечение — кольцо ВОКРУГ плашки, тем же тоном и без оттенков.
  void _halo(Canvas canvas, double s, Offset c, double k) {
    final rect = Rect.fromCircle(center: c, radius: s * 0.5);
    canvas.drawCircle(
      c,
      s * 0.5,
      frost
          ? (Paint()
              ..isAntiAlias = true
              ..shader = RadialGradient(
                colors: [
                  _tone(t).withValues(alpha: 0.0),
                  _tone(t).withValues(alpha: (isDark ? 0.46 : 0.38) * k),
                  _tone(t + 0.33).withValues(alpha: (isDark ? 0.34 : 0.28) * k),
                  _tone(t + 0.33).withValues(alpha: 0.0),
                ],
                stops: const [0.86, 0.945, 0.975, 1.0],
              ).createShader(rect))
          : (Paint()
              ..isAntiAlias = true
              ..shader = RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.0),
                  accent.withValues(alpha: (isDark ? 0.34 : 0.34) * k),
                  accent.withValues(alpha: 0.0),
                ],
                stops: const [0.86, 0.945, 1.0],
              ).createShader(rect)),
    );
  }

  /// Бегунок по кромке корпуса: голова и затухающий хвост из штрихов.
  /// Идёт ровно по кругу ВСЁ время цикла, поэтому пауза скважины не читается
  /// как «анимация встала».
  void _runner(Canvas canvas, double s, Offset c, double tau) {
    final rect = Rect.fromCircle(center: c, radius: s * 0.44);
    final glint = _medallionGlint(t);
    // −π/2: цикл стартует ровно на полудне, где у знака указатель.
    final lead = t * tau - math.pi / 2;
    final stroke = _ink(0, w: s * 0.026)..strokeCap = StrokeCap.round;
    for (var i = 0; i < _tail; i++) {
      final k = 1 - i / _tail;
      stroke.color = _tone(
        t - i * _step,
      ).withValues(alpha: 0.55 * glint * k * k);
      canvas.drawArc(
        rect,
        lead - (i + 1) * _step * tau,
        _step * tau * 0.88,
        false,
        stroke,
      );
    }
    final at = c + Offset(math.cos(lead), math.sin(lead)) * s * 0.44;
    canvas
      ..drawCircle(at, s * 0.050, _ink(0.16 * glint, pos: t))
      ..drawCircle(at, s * 0.032, _ink(0.30 * glint, pos: t))
      ..drawCircle(at, s * 0.016, _ink(0.80 * glint, pos: t));
  }

  /// Снежинки-искры скина: восемь точек на волосок вне корпуса, кружатся
  /// вместе с бегунком и разгораются на каждом довороте скважины.
  ///
  /// Радиус дышит вместе с ореолом: на разгорании искры расходятся от
  /// корпуса, на покое прижимаются к нему — поэтому плашка не выглядит
  /// застывшей между доворотами ключа.
  void _sparks(Canvas canvas, double s, Offset c, double tau) {
    final k = _medallionBreath(t);
    for (var i = 0; i < 8; i++) {
      final spread = 0.468 + 0.022 * k + 0.008 * (i.isEven ? 1 : -1);
      final a = lead(t, tau) + i / 8 * tau;
      final at = c + Offset(math.cos(a), math.sin(a)) * s * spread;
      final big = i % 3 == 0;
      if (big) {
        // Крупная искра получает ореол — тем же приёмом, что и голова
        // бегунка: два круга вместо размытия (blur здесь не по карману).
        canvas.drawCircle(at, s * 0.036, _ink(0.10 + 0.16 * k, pos: i / 8));
      }
      canvas.drawCircle(
        at,
        s * (big ? 0.017 : 0.010),
        _ink(0.30 + 0.45 * k, pos: i / 8),
      );
    }
  }

  /// Угол головы бегунка (тот же, что в [_runner]).
  static double lead(double t, double tau) => t * tau - math.pi / 2;

  /// Скважина проворачивается целиком: вращение самого провала читается как
  /// проворачиваемый механизм замка. Дырка остаётся ЧЁРНОЙ — цветная в тон
  /// темы она выглядела пятном краски, а не полостью.
  ///
  /// Подсветка поворота сделана светом, а не размером: по контуру полости
  /// разгорается обводка в тон темы на ту же долю цикла.
  void _keyhole(Canvas canvas, double s, Offset c, double angle) {
    final headY = -s * 0.088;
    final headR = s * 0.118;
    final bottom = s * 0.222;
    final w1 = headR * 0.58;
    final w2 = headR * 1.02;
    final q = s * 0.030;
    Paint ink(double a) => Paint()
      ..isAntiAlias = true
      ..color = Colors.black.withValues(alpha: a)
      ..style = PaintingStyle.fill;
    Path hole(double dy) {
      final hd = headY + dy;
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(0, hd), radius: headR))
        ..moveTo(-w1, hd + headR * 0.30)
        ..lineTo(w1, hd + headR * 0.30)
        ..lineTo(w2, bottom + dy - q)
        ..quadraticBezierTo(w2, bottom + dy, w2 - q, bottom + dy)
        ..lineTo(-w2 + q, bottom + dy)
        ..quadraticBezierTo(-w2, bottom + dy, -w2, bottom + dy - q)
        ..close();
    }

    // Геометрия кадра не зависит от угла: подготовить обе позиции один раз,
    // затем повернуть канвас, как и раньше. Ранее hole(0) строил одинаковый
    // Path дважды за кадр, а смещённый контур — ещё раз.
    final baseHole = hole(0);
    final shiftedHole = hole(s * 0.010);

    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle)
      // Свечение идёт ПЕРЕД чёрной полостью: заливка забрала бы обводку
      // внутрь себя, и снаружи остался бы только тонкий ободок.
      ..drawPath(
        baseHole,
        _ink((isDark ? 0.34 : 0.30) * _medallionBreath(t), w: s * 0.055, pos: t)
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(shiftedHole, ink(isDark ? 0.30 : 0.22))
      ..drawPath(baseHole, ink(isDark ? 0.58 : 0.88))
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _MedallionMotionPainter old) =>
      old.pulse != pulse ||
      old.accent != accent ||
      old.isDark != isDark ||
      old.frost != frost;
}

/// Плавная извилистая красная линия под заголовком «Введите PIN» —
/// полупрозрачная, лёгкая волна, как росчерк кисти.
class _PinPrompt extends StatelessWidget {
  const _PinPrompt({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: style),
        CustomPaint(
          size: Size(width, 12),
          painter: _WavyLinePainter(
            color: const Color(0xFFB3121F).withValues(alpha: 0.42),
          ),
        ),
      ],
    );
  }
}

class _WavyLinePainter extends CustomPainter {
  final Color color;
  _WavyLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    final path = Path();
    final amplitude = size.height * 0.32;
    const frequency = 4.0;
    const steps = 100;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final y =
          size.height / 2 + amplitude * math.sin(t * math.pi * 2 * frequency);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavyLinePainter old) => old.color != color;
}
