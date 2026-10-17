import 'dart:async';

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
/// Отклик клавиши считывается сразу по указателю (`Listener`), а не по
/// tap-down арбитра жестов: внутри скролла tap-down приходит только после
/// ~100 мс (арбитр ждёт, не начнётся ли прокрутка), и подсветка «догоняла»
/// палец уже после отпускания. Действие при этом остаётся у [GestureDetector],
/// поэтому протяжка по панели по-прежнему прокручивает экран, а не набирает
/// цифры.
///
/// Клавиши отзываются мягким вдавливанием и заливкой акцентом, а не резким
/// «щелчком»: масштаб и цвет ведёт один короткий контроллер, поэтому нажатие
/// читается даже на слабом GPU и ничего не «дёргается» при быстром наборе.
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

  /// Автоповтор стереть: пауза, как у системной клавиатуры, затем учащение.
  static const Duration _holdDelay = Duration(milliseconds: 420);
  static const Duration _holdRepeat = Duration(milliseconds: 75);

  Timer? _hold;
  bool _holdRepeated = false;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

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

  /// Зажатие «стереть»: сначала одна цифра, затем ускоряющийся ряд.
  void _beginBackspaceHold() {
    _hold?.cancel();
    _holdRepeated = false;
    _hold = Timer(_holdDelay, () {
      _holdRepeated = true;
      _backspace();
      _hold = Timer.periodic(_holdRepeat, (_) => _backspace());
    });
  }

  void _endBackspaceHold() {
    _hold?.cancel();
    _hold = null;
  }

  void _backspaceTap() {
    // Если автоповтор уже стёр цифры, отпускание пальца не должно стереть
    // ещё одну — иначе «зажал и отпустил» съедало на две цифры больше.
    final repeated = _holdRepeated;
    _holdRepeated = false;
    if (!repeated) _backspace();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 1 2 3 / 4 5 6 / 7 8 9 / ОЧИСТИТЬ 0 СТЕРЕТЬ. Слоты 0…9 заняли цифры,
    // 10 и 11 — служебные клавиши.
    const digits = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9'];
    final rows = <List<_PadSpec>>[
      for (var r = 0; r < 3; r++)
        [
          for (var k = 0; k < 3; k++)
            _PadSpec.digit(digits[r * 3 + k], r * 3 + k),
        ],
      const [
        _PadSpec.action(_clearSlot, Icons.vertical_align_top_rounded),
        _PadSpec.digit('0', 9),
        _PadSpec.action(_backspaceSlot, Icons.backspace_outlined),
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
                        colorScheme: cs,
                        onTapDown: spec.slot == _backspaceSlot
                            ? _beginBackspaceHold
                            : null,
                        onTap: switch (spec.slot) {
                          _clearSlot => _clear,
                          _backspaceSlot => () {
                            _endBackspaceHold();
                            _backspaceTap();
                          },
                          _ => () => _append(spec.digit!),
                        },
                        onTapCancel: spec.slot == _backspaceSlot
                            ? _endBackspaceHold
                            : null,
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

/// Одна клавиша панели: скруглённый прямоугольник, который при нажатии
/// мягко вдавливается и наливается акцентом.
class _PadKey extends StatefulWidget {
  const _PadKey({
    required this.spec,
    required this.label,
    required this.colorScheme,
    required this.onTap,
    this.onTapDown,
    this.onTapCancel,
  });

  final _PadSpec spec;
  final String label;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapCancel;

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(vsync: this);
  bool _held = false;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    if (_held) return;
    _held = true;
    // 190 мс вместо 90: на 90 клавиша «проваливалась» за три кадра — это и
    // читалось как резкое зажатие. Вдавливание теперь успевает быть
    // замеченным, а быстрый набор всё равно не ждёт: нажатие засчитывается
    // сразу по указателю, анимация только догоняет.
    _press.animateTo(
      1,
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
    );
  }

  void _up() {
    if (!_held) return;
    _held = false;
    // Возврат мягче и длиннее вдавливания — отпускание не «щёлкает».
    _press.animateBack(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final icon = widget.spec.icon;
    return Semantics(
      button: true,
      label: widget.label,
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: GestureDetector(
          key: Key('numberpad_${widget.spec.slot}'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: (_) => widget.onTapDown?.call(),
          onTap: widget.onTap,
          onTapCancel: () {
            _up();
            widget.onTapCancel?.call();
          },
          child: AnimatedBuilder(
            animation: _press,
            builder: (context, _) {
              // Кривая уже применена самим контроллером (`animateTo(curve:)`).
              // Повторный easeOutCubic поверх неё сдвигал всю анимацию в
              // начало — клавиша «прыгала» в нажатое состояние и потом стояла.
              final t = _press.value;
              final foreground = Color.lerp(
                cs.onSurfaceVariant,
                cs.primary,
                t,
              )!;
              return Transform.scale(
                scale: 1 - 0.038 * t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      cs.primary.withValues(alpha: 0.22),
                      t,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Color.lerp(
                        cs.outline.withValues(alpha: 0.28),
                        cs.primary.withValues(alpha: 0.6),
                        t,
                      )!,
                      width: 1 + 0.3 * t,
                    ),
                  ),
                  child: SizedBox(
                    height: 46,
                    child: Center(
                      child: icon != null
                          ? Icon(icon, size: 22, color: foreground)
                          : Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: Color.lerp(cs.onSurface, cs.primary, t),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
