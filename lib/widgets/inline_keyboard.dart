import 'dart:async';

import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../utils/design_tokens.dart';
import 'press_scale.dart';

/// Встроенная клавиатура «под тему приложения».
///
/// Используется вместо системной там, где это уместно по замыслу экрана
/// (например, лист «Добавить друга»): панель живёт прямо в листе, окрашена в
/// цвета текущей темы и не зависит от раскладок и скинов чужой клавиатуры.
/// Поля ввода при этом делают `readOnly`, чтобы системная панель не
/// выскакивала поверх.
///
/// Символы отдаются наружу через [onChar]; управление — через [onBackspace]
/// и [onSpace]. Набор намеренно короткий: буквы (кириллица + латиница),
/// цифры, пробел, возврат и КЛАВИША-РЕГИСТР — этого достаточно, чтобы
/// спокойно набрать и имя, и счёт.
///
/// Регистр держит сама клавиатура (состояние [_shift]): тап по «⇧» делает
/// СЛЕДУЮЩУЮ букву заглавной и сам гаснет — как на системной панели, где
/// Shift одноразовый. Раньше во второй строке стоял ВТОРОЙ «стереть»: две
/// одинаковые кнопки возврата в одной панели читались ошибкой раскладки, а
/// заглавную букву набрать было нельзя вообще.
class InlineKeyboard extends StatefulWidget {
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;

  /// Необязательная кнопка-действие прямо в клавиатуре (например, «Добавить»
  /// в листе друга): подпись и обработчик. Пусто — клавиатура остаётся
  /// «чистой», без кнопки. Так главное действие листа можно подтвердить,
  /// не отрывая палец от набора.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Акцентный тон кнопки-действия: её должно быть видно, она отличается от
  /// обычных клавиш набора.
  final bool actionEmphasized;

  /// Красный бренда: отлив клавиатуры не должен зависеть от роли темы
  /// (`primary` на дефолтной палитре — сиреневый, и панель серела).
  static const Color _brandRed = BrandColors.red;

  /// Высота одной клавиши.
  final double keyHeight;

  const InlineKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onSpace,
    this.actionLabel,
    this.onAction,
    this.actionEmphasized = true,
    this.keyHeight = 44,
  });

  @override
  State<InlineKeyboard> createState() => _InlineKeyboardState();
}

class _InlineKeyboardState extends State<InlineKeyboard>
    with SingleTickerProviderStateMixin {
  /// Регистр включён: следующая буква уйдёт ЗАГЛАВНОЙ, после чего гаснет.
  bool _shift = false;

  /// Прогресс переключения регистра 0..1: ведёт плавный подъём/опускание букв.
  late final AnimationController _caseAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _caseCurve = CurvedAnimation(
    parent: _caseAnim,
    curve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _caseAnim.dispose();
    super.dispose();
  }

  void _setShift(bool on) {
    setState(() => _shift = on);
    if (on) {
      _caseAnim.forward();
    } else {
      _caseAnim.reverse();
    }
  }

  static const List<String> _digits = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
  ];
  static const List<String> _row1 = [
    'й', 'ц', 'у', 'к', 'е', 'н', 'г', 'ш', 'щ', 'з', 'х',
  ];
  static const List<String> _row2 = [
    'ф', 'ы', 'в', 'а', 'п', 'р', 'о', 'л', 'д', 'ж', 'э',
  ];
  static const List<String> _row3 = [
    'я', 'ч', 'с', 'м', 'и', 'т', 'ь', 'б', 'ю', 'ъ',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        // Полупрозрачная панель с ЯВНЫМ КРАСНЫМ отливом: сквозь клавиатуру
        // просвечивает лист, а алый тон привязывает её к остальным
        // «стеклянным» плашкам. Раньше отлив брался из `cs.primary`, а на
        // теме по умолчанию primary — сиреневый, и панель читалась просто
        // СЕРОЙ плитой. Красный задаём константой бренда, а не ролью темы.
        color: Color.alphaBlend(
          InlineKeyboard._brandRed.withValues(alpha: 0.30),
          theme.colorScheme.surfaceContainer.withValues(alpha: 0.66),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        border: Border(
          top: BorderSide(
            color: InlineKeyboard._brandRed.withValues(alpha: 0.38),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(theme, _digits, widget.keyHeight),
          const SizedBox(height: 6),
          _row(theme, _row1, widget.keyHeight),
          const SizedBox(height: 6),
          _row(theme, _row2, widget.keyHeight),
          const SizedBox(height: 6),
          // В нижнем ряду букв — РЕГИСТР. «Стереть» на панели ОДИН (в нижней
          // строке): второй возврат рядом с буквами читался ошибкой раскладки,
          // а заглавную букву набрать было нельзя вообще.
          _row(theme, _row3, widget.keyHeight, leadingShift: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                // Кнопка-действие отъедает часть строки у пробела: так она
                // заметная, но не отдельная «полка» под клавиатурой.
                flex: widget.actionLabel == null ? 5 : 3,
                child: _Key(
                  theme: theme,
                  label: 'пробел',
                  height: widget.keyHeight,
                  onTap: widget.onSpace,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _Key(
                  theme: theme,
                  icon: Icons.backspace_outlined,
                  height: widget.keyHeight,
                  // Возврат повторяется при удержании — как у системной
                  // клавиатуры: стереть длинное имя одним тапом было нельзя.
                  repeat: true,
                  onTap: widget.onBackspace,
                ),
              ),
              if (widget.actionLabel != null) ...[
                const SizedBox(width: 4),
                Expanded(
                  flex: 3,
                  child: _Key(
                    theme: theme,
                    label: widget.actionLabel,
                    height: widget.keyHeight,
                    emphasized: widget.actionEmphasized,
                    onTap: widget.onAction ?? () {},
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Отдать букву наружу. Регистр ОДНОРАЗОВЫЙ: заглавная уходит, и «⇧» сам
  /// гаснет — как на системной панели.
  void _tap(String ch) {
    final text = _shift ? ch.toUpperCase() : ch;
    if (_shift) _setShift(false);
    widget.onChar(text);
  }

  Widget _row(
    ThemeData theme,
    List<String> chars,
    double height, {
    bool leadingShift = false,
  }) {
    return Row(
      children: [
        if (leadingShift)
          Expanded(
            child: _Key(
              theme: theme,
              icon: _shift
                  ? Icons.keyboard_capslock
                  : Icons.keyboard_capslock_outlined,
              height: height,
              active: _shift,
              onTap: () => _setShift(!_shift),
            ),
          ),
        for (final c in chars)
          Expanded(
            // Регистр переключается ПЛАВНО: буква уходит вверх и возвращается
            // на место кроссфейдом со сдвигом, а не подменяется кадром
            // (владелец: «при делании заглавными буквы плавно поднимаются
            // опускаются»). Один общий прогресс [_caseAnim] — на все буквы
            // ряда сразу, поэтому ряд «дышит» синхронно.
            child: _CaseGlyph(
              lower: c,
              upper: c.toUpperCase(),
              animation: _caseCurve,
              height: height,
              theme: theme,
              onTap: () => _tap(c),
            ),
          ),
      ],
    );
  }
}

/// Одна клавиша: «вдавливание» под пальцем, тактильный отклик и (для возврата)
/// авто-повтор при удержании.
class _Key extends StatefulWidget {
  final ThemeData theme;
  final String? label;
  final IconData? icon;
  final double height;
  final VoidCallback onTap;

  /// Акцентная клавиша-действие: залита брендовым красным плотнее прочих и
  /// с белым текстом — она читается как кнопка, а не как буква.
  final bool emphasized;

  /// Повторять действие, пока палец держится (для «стереть»).
  final bool repeat;

  /// Клавиша-режим в активном состоянии (например, включённый регистр):
  /// подсвечена, чтобы было видно, что следующий ввод — заглавный.
  final bool active;

  const _Key({
    required this.theme,
    required this.height,
    required this.onTap,
    this.label,
    this.icon,
    this.repeat = false,
    this.emphasized = false,
    this.active = false,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  Timer? _hold;

  /// Задержка до первого повтора и шаг между повторами: сначала пауза, чтобы
  /// одиночный тап не «строчил», потом — ровное частое стирание.
  static const Duration _delay = Duration(milliseconds: 380);
  static const Duration _tick = Duration(milliseconds: 70);

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (!widget.repeat) return;
    _hold?.cancel();
    _hold = Timer(_delay, () {
      _hold = Timer.periodic(_tick, (_) {
        Haptics.select();
        widget.onTap();
      });
    });
  }

  void _stopHold() {
    _hold?.cancel();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final cs = theme.colorScheme;
    // Полупрозрачные КРАСНЫЕ клавиши: тон бренда, сильно разбавленный, —
    // кнопки читаются «стеклянно-красными» на любом фоне. Цвет берём из
    // константы, а не из `cs.primary`: на дефолтной теме primary сиреневый,
    // и клавиши выходили серо-фиолетовыми вместо красных.
    final keyColor = widget.emphasized
        ? InlineKeyboard._brandRed.withValues(alpha: 0.92)
        : widget.active
        ? InlineKeyboard._brandRed.withValues(alpha: 0.72)
        : Color.alphaBlend(
            InlineKeyboard._brandRed.withValues(alpha: 0.26),
            cs.surfaceContainerHighest.withValues(alpha: 0.66),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: PressScale(
        // Отдача клавиши — заметно медленнее и мягче прежних 90/180 мс:
        // на быстром наборе клавиша «щёлкала» кадром и не читалась как
        // вдавливание (владелец: «отдачу плавнее и медленнее надо, а то
        // быстро»). Вход мягче, возврат ещё длиннее — палец успевает
        // почувствовать ход, а следующая клавиша нажимается поверх.
        pressedScale: 0.86,
        duration: const Duration(milliseconds: 190),
        releaseDuration: const Duration(milliseconds: 340),
        // Отдачу рисует сам PressScale: `Material`+`InkWell` на каждую клавишу
        // — лишние слои и чернильные всплески. Держим только один «блик»
        // нажатия через `Listener` внутри PressScale, а тап отдаёт GestureDetector.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.select();
            widget.onTap();
          },
          onTapDown: (_) => _startHold(),
          onTapUp: (_) => _stopHold(),
          onTapCancel: _stopHold,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: keyColor,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(
                color: InlineKeyboard._brandRed.withValues(
                  alpha: widget.active || widget.emphasized ? 0.6 : 0.30,
                ),
              ),
            ),
            child: Container(
              height: widget.height,
              alignment: Alignment.center,
              child: widget.icon != null
                  ? Icon(
                      widget.icon,
                      size: 20,
                      color: widget.active
                          ? Colors.white
                          : InlineKeyboard._brandRed,
                    )
                  : Text(
                      widget.label!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: Weights.semibold,
                        color: widget.emphasized ? Colors.white : cs.onSurface,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Одна буква клавиши, у которой регистр меняется ПЛАВНО.
///
/// Обе начертания («а» и «А») стоят стопкой в одном слоте: нижнее уезжает
/// вниз и тает, верхнее поднимается из-под пальца и проявляется. Сдвиг —
/// только `Transform`/`Opacity`, поэтому раскладка клавиши не пересобирается.
class _CaseGlyph extends StatelessWidget {
  final String lower;
  final String upper;
  final Animation<double> animation;
  final double height;
  final ThemeData theme;
  final VoidCallback onTap;

  const _CaseGlyph({
    required this.lower,
    required this.upper,
    required this.animation,
    required this.height,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      pressedScale: 0.86,
      duration: const Duration(milliseconds: 190),
      releaseDuration: const Duration(milliseconds: 340),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.select();
          onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              InlineKeyboard._brandRed.withValues(alpha: 0.26),
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.66),
            ),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: InlineKeyboard._brandRed.withValues(alpha: 0.30),
            ),
          ),
          child: SizedBox(
            height: height,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Нижняя буква: уходит вниз и тает по мере включения.
                    Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 5 * t),
                        child: _glyph(lower),
                      ),
                    ),
                    // Верхняя буква: поднимается снизу и проявляется.
                    Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, -5 * (1 - t)),
                        child: _glyph(upper),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _glyph(String ch) => Text(
    ch,
    style: theme.textTheme.titleMedium?.copyWith(
      fontWeight: Weights.semibold,
      color: theme.colorScheme.onSurface,
    ),
  );
}
