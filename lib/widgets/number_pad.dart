import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';

/// Встроенная цифровая клавиатура вместо системной.
///
/// Нужна ровно для двух числовых полей (калорийность и вода): системная
/// клавиатура не одевается в тему приложения, поднимается над всем экраном и
/// на 60-герцевом Redmi перекрывает как раз те счётчики, ради которых поля и
/// открывают. Здесь панель лежит в потоке layout и раскрывается тем же
/// приёмом, что и карточки, — соседям есть куда расступиться.
///
/// Клавиши отзываются цветом и подсветкой, а не масштабом: «прыжок» размера
/// на слабом GPU читается как дёрганье, а нажатие без отклика вообще не
/// читается.
class NumberPad extends StatefulWidget {
  const NumberPad({
    super.key,
    required this.controller,
    this.maxDigits = 5,
    this.onAppendLimit,
  });

  /// Поле, которое клавиатура редактирует.
  final TextEditingController controller;

  /// Сколько цифр помещается: 5 для ккал (до 10000), 4 для мл.
  final int maxDigits;

  /// Вызывается, когда пользователь упёрся в потолок цифр.
  final VoidCallback? onAppendLimit;

  @override
  State<NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<NumberPad> {
  static const int _clearSlot = 10;
  static const int _backspaceSlot = 11;

  int _pressed = -1;

  void _press(int slot) => setState(() => _pressed = slot);
  void _release() => setState(() => _pressed = -1);

  void _append(String digit) {
    final text = widget.controller.text;
    if (text.length >= widget.maxDigits) {
      widget.onAppendLimit?.call();
      return;
    }
    Haptics.select();
    // Ведущий ноль заменяется первой же цифрой: «05» в поле ккал — мусор.
    final next = text == '0' ? digit : text + digit;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _backspace() {
    final text = widget.controller.text;
    if (text.isEmpty) return;
    Haptics.select();
    final next = text.substring(0, text.length - 1);
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _clear() {
    if (widget.controller.text.isEmpty) return;
    Haptics.light();
    widget.controller.value = TextEditingValue.empty;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final digits = List.generate(10, (i) => '$i')..removeAt(0);
    // 1 2 3 / 4 5 6 / 7 8 9 / ОЧИСТИТЬ 0 СТЕРЕТЬ. Слоты 0…9 заняли цифры,
    // 10 и 11 — служебные клавиши.
    final rows = <List<_PadSpec>>[
      for (var r = 0; r < 3; r++)
        [
          for (var k = 0; k < 3; k++)
            _PadSpec.digit(digits[r * 3 + k], r * 3 + k),
        ],
      [
        const _PadSpec.action(_clearSlot, Icons.vertical_align_top_rounded),
        _PadSpec.digit('0', 9),
        const _PadSpec.action(_backspaceSlot, Icons.backspace_outlined),
      ],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final spec in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _PadKey(
                        spec: spec,
                        label: spec.digit ?? _actionLabel(context, spec.slot),
                        pressed: _pressed == spec.slot,
                        colorScheme: cs,
                        onTapDown: () => _press(spec.slot),
                        onTapUp: () {
                          _release();
                          switch (spec.slot) {
                            case _clearSlot:
                              _clear();
                            case _backspaceSlot:
                              _backspace();
                            default:
                              _append(spec.digit!);
                          }
                        },
                        onTapCancel: _release,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _actionLabel(BuildContext context, int slot) => slot == _clearSlot
      ? Translations.t('clearAll', context, 'Очистить')
      : Translations.t('backspace', context, 'Стереть');
}

/// Что рисовать и по какому слоту нажимать.
class _PadSpec {
  const _PadSpec.digit(this.digit, this.slot) : icon = null;
  const _PadSpec.action(this.slot, this.icon) : digit = null;

  final String? digit;
  final int slot;
  final IconData? icon;
}

/// Одна клавиша панели: залитый скруглённый прямоугольник, который при
/// нажатии наливается акцентом и получает акцентную обводку.
class _PadKey extends StatelessWidget {
  const _PadKey({
    required this.spec,
    required this.label,
    required this.pressed,
    required this.colorScheme,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  final _PadSpec spec;
  final String label;
  final bool pressed;
  final ColorScheme colorScheme;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final icon = spec.icon;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: Key('numberpad_${spec.slot}'),
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => onTapDown(),
        onTapUp: (_) => onTapUp(),
        onTapCancel: onTapCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pressed
                ? cs.primary.withValues(alpha: 0.22)
                : cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: pressed
                  ? cs.primary.withValues(alpha: 0.55)
                  : cs.outline.withValues(alpha: 0.28),
            ),
          ),
          child: icon != null
              ? Icon(icon, size: 22, color: cs.onSurfaceVariant)
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
      ),
    );
  }
}
