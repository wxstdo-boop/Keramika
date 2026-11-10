import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

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
    this.keyHeight = 40,
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
        color: cs.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(theme, _digits, keyHeight),
          const SizedBox(height: 5),
          _row(theme, _row1, keyHeight),
          const SizedBox(height: 5),
          _row(theme, _row2, keyHeight),
          const SizedBox(height: 5),
          _row(theme, _row3, keyHeight, trailingBackspace: true),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _key(
                  theme,
                  label: 'пробел',
                  height: keyHeight,
                  onTap: onSpace,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _key(
                  theme,
                  icon: Icons.backspace_outlined,
                  height: keyHeight,
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
            child: _key(
              theme,
              label: c,
              height: height,
              onTap: () => onChar(c),
            ),
          ),
        if (trailingBackspace)
          Expanded(
            child: _key(
              theme,
              icon: Icons.backspace_outlined,
              height: height,
              onTap: onBackspace,
            ),
          ),
      ],
    );
  }

  Widget _key(
    ThemeData theme, {
    String? label,
    IconData? icon,
    required double height,
    required VoidCallback onTap,
  }) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: Container(
            height: height,
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 18, color: cs.onSurfaceVariant)
                : Text(
                    label!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: Weights.medium,
                      color: cs.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
