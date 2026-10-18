part of 'settings_screen.dart';

class _RealityCheckToggleCard extends StatelessWidget {
  const _RealityCheckToggleCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rc = RealityCheckService();
    return ListenableBuilder(
      listenable: rc,
      builder: (context, _) {
        final on = rc.enabled;
        final title = Translations.t(
          'rcSettingsTitle',
          context,
          Translations.realityChecksOf(context),
        );
        final body = Translations.t(
          'rcSettingsBody',
          context,
          // Аббревиатура из перевода (RC/РП/CR), чтобы даже фолбэк не
          // показывал кириллицу в нерусских языках.
          'Adds or removes the section entirely: the '
              '${Translations.rcOf(context)} tab in Home, schedule and notifications.',
        );
        // Плавный переход цвета карточки и текста вместо мгновенного прыжка.
        final bgColor = on
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh;
        final fgColor = on
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface;
        final fgMuted = on
            ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.75)
            : theme.colorScheme.onSurfaceVariant;
        final badgeBg = on
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surface;
        final badgeFg = on
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;
        // AnimatedContainer: фон карточки плавно перетекает между
        // состояниями (раньше был простой Container — цвет переключался
        // мгновенно, хотя текст/бейдж анимировались — выглядело дёргано).
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // blurRadius 4: большие размытые тени на карточках стоят
              // дорого при каждом кадре скролла на средних GPU.
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: on ? 0.07 : 0.03),
                blurRadius: 4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _toggle(context, rc, !on),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Бейдж иконки — плавная смена цвета.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: badgeBg,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (c, a) => ScaleTransition(
                          scale: Tween<double>(begin: 0.7, end: 1.0).animate(a),
                          child: FadeTransition(opacity: a, child: c),
                        ),
                        child: Icon(
                          Icons.psychology_outlined,
                          key: ValueKey(on),
                          size: 26,
                          color: badgeFg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            style: theme.textTheme.titleMedium!.copyWith(
                              fontWeight: FontWeight.w700,
                              color: fgColor,
                            ),
                            child: Text(title),
                          ),
                          const SizedBox(height: 4),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: fgMuted,
                            ),
                            child: Text(body),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    VolumetricSwitch(
                      value: on,
                      onChanged: (v) => _toggle(context, rc, v),
                      activeColor: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggle(BuildContext context, RealityCheckService rc, bool newValue) {
    rc.setEnabled(newValue);
    // When turning off: cancel any scheduled Rb notifications so they don't
    // surprise the user while the section is hidden. Turn-on is left for
    // the Rb screen initState to schedule next time it is shown.
    if (!newValue) {
      notificationService.cancelAllRealityChecks();
    }
    if (!context.mounted) return;
    // groupKey объединяет быстрые ON↔OFF-переключения в одну плашку — не даёт шторм.
    showBeautifulSnackBar(
      context,
      message: newValue
          ? Translations.t(
              'rcSettingsOn',
              context,
              'Раздел «Проверки реальности» включён',
            )
          : Translations.t(
              'rcSettingsOff',
              context,
              'Раздел «Проверки реальности» скрыт',
            ),
      icon: newValue
          ? Icons.check_circle_outline
          : Icons.visibility_off_outlined,
      iconColor: newValue ? Colors.green : Colors.orange,
      groupKey: 'rcSettingsToggle',
    );
  }
}

/// Кнопка-«трек» в стиле переключателей: чистый корпус с градиентной
/// заливкой, мягким цветным свечением и белой иконкой-капсулой. БЕЗ нижней
/// полосы-грани — объём только через тень и блик. Зажатие у всех таких
/// кнопок одинаковое: мягкое вдавливание по высоте + схлопывание тени.
/// Кнопка-«таблетка» способа оплаты в окне поддержки: градиентная широкая
/// строка с иконкой в кружке, названием и стрелкой. Используется внутри
/// bottom sheet (CloudTips / Boosty и др.).
class _SupportPill extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback onTap;

  const _SupportPill({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.onTap,
  });

  @override
  State<_SupportPill> createState() => _SupportPillState();
}

class _SupportPillState extends State<_SupportPill> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    // Контраст под текущую тему: на светлых темах градиент светлый →
    // тёмный текст, на тёмных → белый.
    final fg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xDE000000);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _setPressed(true);
        Haptics.medium();
      },
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        height: _pressed ? 58 : 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withValues(alpha: _pressed ? 0.2 : 0.35),
              blurRadius: _pressed ? 6 : 14,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.gradient,
          ),
          border: Border.all(color: fg.withValues(alpha: 0.40), width: 1.2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fg.withValues(alpha: 0.18),
                border: Border.all(color: fg.withValues(alpha: 0.40), width: 1),
              ),
              child: Icon(widget.icon, color: fg, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: fg.withValues(alpha: 0.7),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final VoidCallback? onTap;

  const _CtaButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.glow,
    this.onTap,
  });

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _setPressed(true);
        // Отдача при нажатии — как у остальных кнопок приложения.
        Haptics.medium();
      },
      onTapUp: (_) {
        _setPressed(false);
        widget.onTap?.call();
      },
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: _pressed ? 50 : 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: widget.glow.withValues(alpha: _pressed ? 0.22 : 0.38),
              blurRadius: _pressed ? 6 : 14,
              offset: Offset(0, _pressed ? 1 : 4),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.gradient,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.40),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Icon(widget.icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 11),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  letterSpacing: 0.6,
                  shadows: [
                    Shadow(
                      color: Color(0x33000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
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

/// Одна запись карусели тем: ключ темы, название и иконка.
class _ThemeEntry {
  final String key;
  final String label;
  final IconData icon;
  final bool specialMutilated;

  const _ThemeEntry(
    this.key,
    this.label,
    this.icon, {
    this.specialMutilated = false,
  });
}

/// Едва заметные кровавые пятна для карточки BERSERK.
/// Статичный слой: рисуется один раз на размер карточки, без анимации.
class _FlutterBadge extends StatelessWidget {
  const _FlutterBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = Color.lerp(cs.surfaceContainerHighest, cs.primary, 0.06)!;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, cs.surfaceContainerHighest],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: CustomPaint(
        size: const Size.square(16),
        painter: _FlutterLogoPainter(
          // Ступеньки в цвет текущей темы: светлый/средний/тёмный оттенки
          // primary вместо фирменных синих — значок подстраивается под
          // каждую тему.
          light: Color.lerp(cs.primary, Colors.white, 0.72)!,
          mid: Color.lerp(cs.primary, Colors.black, 0.05)!,
          dark: Color.lerp(cs.primary, Colors.black, 0.30)!,
        ),
      ),
    );
  }
}

class _FlutterLogoPainter extends CustomPainter {
  final Color light;
  final Color mid;
  final Color dark;

  const _FlutterLogoPainter({
    required this.light,
    required this.mid,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final lightPaint = Paint()..color = light;
    final midPaint = Paint()..color = mid;
    final darkPaint = Paint()..color = dark;

    final step = w / 3.0;
    // Верхняя ступенька: полная ширина, правый край скошен.
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w - step, h / 3)
        ..lineTo(0, h / 3)
        ..close(),
      lightPaint,
    );
    // Средняя ступенька: правая граница уходит дальше влево.
    canvas.drawPath(
      Path()
        ..moveTo(0, h / 3)
        ..lineTo(w - step, h / 3)
        ..lineTo(w - 2 * step, 2 * h / 3)
        ..lineTo(0, 2 * h / 3)
        ..close(),
      midPaint,
    );
    // Нижняя ступенька: самая узкая.
    canvas.drawPath(
      Path()
        ..moveTo(0, 2 * h / 3)
        ..lineTo(w - 2 * step, 2 * h / 3)
        ..lineTo(w - 3 * step, h)
        ..lineTo(0, h)
        ..close(),
      darkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FlutterLogoPainter oldDelegate) =>
      oldDelegate.light != light ||
      oldDelegate.mid != mid ||
      oldDelegate.dark != dark;
}
