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

  /// Доля ширины карточки, после которой свайп считается «осознанным» и
  /// открывает подтверждение удаления. Поднято с дефолтных 0.40: списки
  /// живут внутри горизонтальной карусели разделов, и лёгкий боковой сдвиг
  /// (попытка свайпнуть раздел, случайное касание при скролле) на 40 %
  /// ширины уже выдёргивал диалог удаления — «свайпы удаляют везде».
  /// 0.60 требует явного, длинного свайпа, но не мешает осознанному.
  final double dismissThreshold;

  const SwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onDismissed,
    this.confirmDismiss,
    this.movementDuration,
    this.borderRadius = 20,
    this.horizontalInset = 0,
    this.dismissThreshold = 0.6,
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
      // Порог «осознанного» свайпа (см. [dismissThreshold]).
      dismissThresholds: <DismissDirection, double>{
        DismissDirection.endToStart: widget.dismissThreshold,
      },
      confirmDismiss: widget.confirmDismiss,
      onDismissed: widget.onDismissed,
      onUpdate: (d) => _progress.value = d.progress,
      background: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, p, _) {
          // Фон виден, только когда карточку реально тянут: раньше красная
          // плашка «УДАЛИТЬ» проявлялась уже с 8 % сдвига и мигала при
          // каждом случайном касании. 20 % — заметный, но осознанный жест.
          final opacity = ((p - 0.20) / 0.80).clamp(0.0, 1.0);
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
