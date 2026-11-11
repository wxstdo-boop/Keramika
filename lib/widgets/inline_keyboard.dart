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
/// цифры, пробел и возврат — этого достаточно, чтобы спокойно набрать и имя,
/// и счёт.
class InlineKeyboard extends StatelessWidget {
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;

  /// Высота одной клавиши.
  final double keyHeight;

  const InlineKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onSpace,
    this.keyHeight = 44,
  });

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
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        // Полупрозрачная панель с КРАСНЫМ отливом темы: сквозь клавиатуру
        // просвечивает лист, а тёплый алый тон привязывает её к остальным
        // «стеклянным» плашкам. Раньше здесь был нейтральный surfaceContainer
        // — панель читалась чужеродной серой плитой.
        color: Color.alphaBlend(
          cs.primary.withValues(alpha: 0.12),
          cs.surfaceContainer.withValues(alpha: 0.78),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        border: Border(
          top: BorderSide(color: cs.primary.withValues(alpha: 0.30)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(theme, _digits, keyHeight),
          const SizedBox(height: 6),
          _row(theme, _row1, keyHeight),
          const SizedBox(height: 6),
          _row(theme, _row2, keyHeight),
          const SizedBox(height: 6),
          _row(theme, _row3, keyHeight, trailingBackspace: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _Key(
                  theme: theme,
                  label: 'пробел',
                  height: keyHeight,
                  onTap: onSpace,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _Key(
                  theme: theme,
                  icon: Icons.backspace_outlined,
                  height: keyHeight,
                  // Возврат повторяется при удержании — как у системной
                  // клавиатуры: стереть длинное имя одним тапом было нельзя.
                  repeat: true,
                  onTap: onBackspace,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    List<String> chars,
    double height, {
    bool trailingBackspace = false,
  }) {
    return Row(
      children: [
        for (final c in chars)
          Expanded(
            child: _Key(
              theme: theme,
              label: c,
              height: height,
              onTap: () => onChar(c),
            ),
          ),
        if (trailingBackspace)
          Expanded(
            child: _Key(
              theme: theme,
              icon: Icons.backspace_outlined,
              height: height,
              repeat: true,
              onTap: onBackspace,
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

  /// Повторять действие, пока палец держится (для «стереть»).
  final bool repeat;

  const _Key({
    required this.theme,
    required this.height,
    required this.onTap,
    this.label,
    this.icon,
    this.repeat = false,
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
    // Полупрозрачные КРАСНЫЕ клавиши: тон primary (у Agysha он алый),
    // сильно разбавленный, — кнопки читаются «стеклянно-красными» на любом
    // фоне. Отдача и повтор — в [PressScale]/InkWell ниже.
    final keyColor = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.20),
      cs.surfaceContainerHighest.withValues(alpha: 0.72),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: PressScale(
        pressedScale: 0.9,
        duration: const Duration(milliseconds: 90),
        releaseDuration: const Duration(milliseconds: 180),
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
                color: cs.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Container(
              height: widget.height,
              alignment: Alignment.center,
              child: widget.icon != null
                  ? Icon(
                      widget.icon,
                      size: 20,
                      color: cs.primary,
                    )
                  : Text(
                      widget.label!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: Weights.semibold,
                        color: cs.onSurface,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
