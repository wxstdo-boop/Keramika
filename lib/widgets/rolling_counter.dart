import 'package:flutter/material.dart';

/// Число-«барабан», который едет за ДРОБНЫМ значением.
///
/// `AnimatedSwitcher` заводит отдельный переход на каждую смену строки.
/// Счётчик шапок в окне ивента перетекает волной 0→12 за 460 мс, то есть
/// двенадцать смен примерно через каждые 38 мс: переходы не успевали
/// закончиться и накладывались друг на друга — строки «переплетались».
/// Барабан устроен иначе: дробная часть значения напрямую задаёт смещение
/// ровно двух строк (текущей и следующей), поэтому слоёв всегда два, а ход
/// непрерывен вместе с волной.
///
/// [value] обязан быть неотрицательным. Ширина коробки равна ширине текущей
/// строки: при смене разрядности («9» → «10») соседние виджеты сдвинутся,
/// поэтому число ставят в конец строки.
class RollingCounter extends StatelessWidget {
  /// Показанное значение. Целая часть — какая строка стоит в окне,
  /// дробная — насколько барабан уже прокручен к следующей.
  final double value;
  final TextStyle? style;

  const RollingCounter({super.key, required this.value, this.style});

  @override
  Widget build(BuildContext context) {
    final lo = value.floor();
    final f = (value - lo).clamp(0.0, 1.0);
    // Табличные цифры: без них «1» уже «2», и барабан подёргивается по
    // горизонтали на каждом шаге.
    final s = (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ClipRect(
      child: Stack(
        children: [
          FractionalTranslation(
            translation: Offset(0, -f),
            child: Text('$lo', style: s, maxLines: 1),
          ),
          FractionalTranslation(
            translation: Offset(0, 1 - f),
            child: Text('${lo + 1}', style: s, maxLines: 1),
          ),
        ],
      ),
    );
  }
}
