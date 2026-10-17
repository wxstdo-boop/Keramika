import 'package:flutter/material.dart';

import 'press_scale.dart';

/// Чип категории с ПЛАВНОЙ шириной.
///
/// Ширина пилюли ведётся не снаружи: внешний `AnimatedSize` режет таблетку
/// прямоугольником — на глазах «расширяются острые углы», а подпись внутри
/// дёргается. Здесь ширина считается по реальной ширине подписи и анимируется
/// ВНУТРИ пилюли: подпись и ширина едут одним непрерывным движением, а
/// скругление остаётся целым на каждом кадре.
///
/// Из этого же следует, что соседи по ряду (и кнопка «+ Новая категория»)
/// переезжают кадр в кадр, а не прыгают на новое место: их позицию ведёт
/// ширина этого чипа, которая меняется плавно, а не мгновенно.
class CategoryChip extends StatefulWidget {
  const CategoryChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Высота пилюли (по ней же центрируется текст).
  static const double height = 36;

  /// Горизонтальная набивка подписи.
  static const double hPad = 14;

  /// Обводка. Толщина ПОСТОЯННАЯ (у невыбранного она прозрачная): иначе
  /// выбор «жирного» чипа добавлял бы 4 px ширины рывком.
  static const double borderWidth = 2;

  /// Длительность переезда ширины.
  static const Duration widthDuration = Duration(milliseconds: 300);

  @override
  State<CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<CategoryChip> {
  /// Ширина подписи, посчитанная тем же движком, что и рисует текст.
  double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = widget.selected;

    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final style = base.copyWith(
      fontSize: base.fontSize ?? 14,
      height: 1.25,
      letterSpacing: 0,
      // Насыщенность ОДНА И ТА ЖЕ у выбранного и обычного чипа. Раньше
      // выбранный был жирнее — и в момент выбора его ширина менялась, а
      // вместе с ней уезжали все соседи по ряду. Переключение читалось как
      // «дёрнулось». Выбор и так виден по заливке и цвету подписи.
      fontWeight: FontWeight.w600,
      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
    );

    // Ширина, к которой едет пилюля. +1 — запас на округление шрифтового
    // движка, чтобы последняя буква не обрезалась на пиксель.
    final target =
        _measure(context, widget.label, style) + CategoryChip.hPad * 2 + 1;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: PressScale(
          pressedScale: 0.96,
          duration: const Duration(milliseconds: 400),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: CategoryChip.widthDuration,
              // Та же кривая, что у ширины: заливка и обводка приезжают
              // синхронно с переездом таблетки, а не раньше/позже неё.
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected ? cs.primary : Colors.transparent,
                border: Border.all(
                  width: CategoryChip.borderWidth,
                  color: selected ? cs.primary : Colors.transparent,
                ),
              ),
              child: ClipRRect(
                // Клип по форме пилюли: пока ширина едет, подпись не
                // вылезает за скруглённые концы.
                borderRadius: BorderRadius.circular(999),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: target),
                  duration: CategoryChip.widthDuration,
                  curve: Curves.easeInOutCubic,
                  builder: (context, w, _) {
                    return SizedBox(
                      width: w,
                      height: CategoryChip.height,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        // Обе подписи лежат слева и НЕ влияют на размер: ширину
                        // ведёт только Tween выше. Иначе ряд прыгал бы на
                        // ширину более длинной из двух подписей.
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          clipBehavior: Clip.none,
                          children: [...previous, ?current],
                        ),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Padding(
                          key: ValueKey<String>('chip_label_${widget.label}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: CategoryChip.hPad,
                          ),
                          // Подпись тоже перетекает: цвет и насыщенность
                          // анимируются вместе с заливкой. Раньше стиль
                          // подставлялся готовым, и в момент выбора текст
                          // «щелчком» становился белым и жирным — при
                          // переключении между категориями это и читалось
                          // как рывок.
                          child: AnimatedDefaultTextStyle(
                            duration: CategoryChip.widthDuration,
                            curve: Curves.easeInOutCubic,
                            style: style,
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
