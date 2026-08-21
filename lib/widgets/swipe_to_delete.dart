import 'package:flutter/material.dart';
import '../utils/animated_delete.dart';

/// Dismissible, у которого красный фон плавно проявляется по мере свайпа:
/// прозрачен при лёгких сдвигах и гаснет вместе с snap-back'ом. Так при
/// переходе в настройки (или любой другой роут) не мелькает «отголосок
/// свайпа» — красная полоса «УДАЛИТЬ».
class SwipeToDelete extends StatefulWidget {
  final Key dismissKey;
  final Widget child;
  final DismissDirectionCallback? onDismissed;
  final ConfirmDismissCallback? confirmDismiss;
  final Duration? movementDuration;
  final double borderRadius;

  /// Горизонтальный отступ карточки: фон удаления рисуется в тех же
  /// границах, чтобы красная плашка не «заезжала» за боковые края.
  final double horizontalInset;

  const SwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onDismissed,
    this.confirmDismiss,
    this.movementDuration,
    this.borderRadius = 20,
    this.horizontalInset = 0,
  });

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  final ValueNotifier<double> _progress = ValueNotifier(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: widget.dismissKey,
      // 320мс вместо 200: возврат карточки после отпускания плавнее,
      // не «отщёлкивает» резко (линейная анимация Dismissible).
      movementDuration:
          widget.movementDuration ?? const Duration(milliseconds: 320),
      // Сжатие высоты строки при удалении тоже плавное — карточка
      // «схлопывается» мягко, а не исчезает рывком.
      resizeDuration: const Duration(milliseconds: 340),
      direction: DismissDirection.endToStart,
      confirmDismiss: widget.confirmDismiss,
      onDismissed: widget.onDismissed,
      onUpdate: (d) => _progress.value = d.progress,
      background: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, p, _) {
          // Фон виден, только когда карточку реально тянут (>8% свайпа).
          final opacity = ((p - 0.08) / 0.92).clamp(0.0, 1.0);
          final inset = widget.horizontalInset;
          return Opacity(
            opacity: opacity,
            // Фон удаления тоже изолирован: при snap-back Dismissible
            // двигает слой, а не пересобирает градиент/текст каждый кадр.
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: RepaintBoundary(
                child: animatedDeleteBackground(
                  context,
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
          );
        },
      ),
      // RepaintBoundary кэширует карточку текстурой: при скролле и свайпе
      // список двигает готовую картинку, а не перерисовывает содержимое
      // каждой карточки каждый кадр (важно для слабых устройств).
      child: RepaintBoundary(child: widget.child),
    );
  }
}
