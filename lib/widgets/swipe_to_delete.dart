import 'package:flutter/material.dart';

import '../utils/animated_delete.dart';

/// Свайп-удаление влево: карточка едет 1:1 за пальцем, а красная плашка
/// ПРОЯВЛЯЕТСЯ по ходу жеста.
///
/// Логика (порог, подтверждение, удаление, схлопывание строки) целиком за
/// [Dismissible] — здесь только визуальная часть.
///
/// Раньше красный фон был нарисован с постоянной альфой: он возникал
/// мгновенно из-под пальца одним всполохом — читалось как «дёрнуло», а не
/// как плавное появление. Теперь альфа едет за прогрессом жеста: до 20 %
/// пути плашки не видно, дальше она наливается и к полному свайпу видна
/// целиком. Прогресс берём из [Dismissible.onUpdate] — он же тикает и на
/// возврате, поэтому плашка так же плавно уходит.
///
/// Возврат мягче штатного: у [Dismissible] скорость возврата постоянна и
/// равна `ширина / movementDuration`, поэтому короткий свайп возвращался
/// почти мгновенно (резкий щелчок). 450 мс даёт спокойный ход и на коротком
/// свайпе, и на полном смахивании, без догоняющего тикера и лишних слоёв.
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
  /// Прогресс свайпа 0..1 из [Dismissible.onUpdate]. Слушает только
  /// маленький фон удаления — сама карточка не пересобирается.
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: widget.dismissKey,
      movementDuration:
          widget.movementDuration ?? const Duration(milliseconds: 450),
      // Схлопывание строки при удалении — тоже мягко.
      resizeDuration: const Duration(milliseconds: 320),
      direction: DismissDirection.endToStart,
      confirmDismiss: widget.confirmDismiss,
      onDismissed: widget.onDismissed,
      onUpdate: (details) => _progress.value = details.progress,
      background: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalInset),
        // Фон удаления изолирован от перерисовки содержимого карточки.
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, p, _) {
              // Красный проявляется по ходу жеста: до 20 % пути плашки ещё
              // не видно, дальше она наливается и к полному свайпу видна
              // целиком. Альфа запекается в цвета (см.
              // [animatedDeleteBackground]), без слоя Opacity.
              final opacity = ((p - 0.20) / 0.80).clamp(0.0, 1.0);
              return animatedDeleteBackground(
                context,
                borderRadius: widget.borderRadius,
                opacity: opacity,
              );
            },
          ),
        ),
      ),
      child: widget.child,
    );
  }
}
