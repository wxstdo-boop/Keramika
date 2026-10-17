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
/// поэтому число ставят в конец строки. Если сдвиг недопустим (счётчик стоит
/// по центру кольца или в заголовке листа), передают [sample] — «опорную»
/// строку, которая держит ширину, — и [alignment] для выравнивания в ней.
class RollingCounter extends StatelessWidget {
  /// Показанное значение. Целая часть — какая строка стоит в окне,
  /// дробная — насколько барабан уже прокручен к следующей.
  final double value;
  final TextStyle? style;

  /// Невидимая строка, по которой держится ширина коробки. Нужна там, где
  /// смена разрядности не должна двигать число по горизонтали.
  final String? sample;

  /// Как выравнивать барабан внутри [sample].
  final AlignmentGeometry alignment;

  const RollingCounter({
    super.key,
    required this.value,
    this.style,
    this.sample,
    this.alignment = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    // NaN/бесконечность не должны ронять `floor()` — на кривых данных
    // счётчик просто показывает ноль.
    final v = value.isFinite && value > 0 ? value : 0.0;
    final lo = v.floor();
    final f = (v - lo).clamp(0.0, 1.0);
    // Табличные цифры: без них «1» уже «2», и барабан подёргивается по
    // горизонтали на каждом шаге.
    final s = (style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final sampleText = sample;
    return ClipRect(
      child: Stack(
        alignment: alignment,
        children: [
          if (sampleText != null)
            // Опорная строка только держит ширину: чтец экрана не должен
            // произносить «99999» рядом с настоящим значением.
            ExcludeSemantics(
              child: Opacity(
                opacity: 0,
                child: Text(sampleText, style: s, maxLines: 1, softWrap: false),
              ),
            ),
          Stack(
            // По центру: при переходе «999 → 1000» обе строки стоят в общей
            // коробке, и цифры не съезжают влево на ширину нового разряда.
            alignment: Alignment.center,
            children: [
              FractionalTranslation(
                translation: Offset(0, -f),
                child: Text('$lo', style: s, maxLines: 1, softWrap: false),
              ),
              FractionalTranslation(
                translation: Offset(0, 1 - f),
                child: Text(
                  '${lo + 1}',
                  style: s,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Тот же барабан, но идущий за целью сам: обновления значения приходят
/// рывками (новая норма, граммы БЖУ, сводка трендов), а число докручивается
/// плавно. При первом появлении стартует с [from] (по умолчанию — сразу с
/// целевого значения, без «прокрутки от нуля»).
class AnimatedCounter extends StatelessWidget {
  final double value;
  final Duration duration;
  final Curve curve;
  final TextStyle? style;
  final String? sample;
  final AlignmentGeometry alignment;
  final double? from;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = const Duration(milliseconds: 460),
    this.curve = Curves.easeOutCubic,
    this.style,
    this.sample,
    this.alignment = Alignment.centerLeft,
    this.from,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // `begin` участвует только в первом построении: при следующих
      // обновлениях [TweenAnimationBuilder] сам стартует с текущего кадра,
      // поэтому барабан не прыгает назад к нулю.
      tween: Tween<double>(begin: from ?? value, end: value),
      duration: duration,
      curve: curve,
      builder: (context, shown, _) => RollingCounter(
        value: shown,
        style: style,
        sample: sample,
        alignment: alignment,
      ),
    );
  }
}
