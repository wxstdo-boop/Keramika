import 'package:flutter/material.dart';

import '../utils/animated_delete.dart';

/// Свайп-удаление влево с красным фоном, который проявляется по ходу жеста.
///
/// Это ТОНКАЯ обёртка над [Dismissible]: вся логика (порог, подтверждение,
/// удаление, схлопывание строки) остаётся за ним.
///
/// Раньше здесь жил кастомный слой «сглаживания»: палец задавал цель, карточку
/// догоняла пружина на кадровом тикере, а поверх [Dismissible] навешивался
/// `Transform.translate` на «отставание». Это давало ЛАГ и лишнюю работу на
/// каждый кадр (два ValueListenableBuilder пересобирались на каждом тике,
/// карточка рисовалась в лишний слой), из-за чего свайп и скролл «дико
/// тормозили», а возврат шёл скачком. Карточка теперь едет 1:1 за пальцем —
/// максимально отзывчиво, без задержки и без лишних слоёв.
class SwipeToDelete extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Dismissible(
      key: dismissKey,
      // 400 мс: возврат после отпускания идёт мягко (плавный старт), но без
      // «желейного» довода — прежние 460 мс вместе с пружиной читались как
      // затянутый и дёрганый возврат, а слишком короткий срок давал резкий
      // рывок в первом кадре.
      movementDuration:
          movementDuration ?? const Duration(milliseconds: 400),
      // Сжатие высоты строки при удалении тоже плавное — карточка
      // «схлопывается» мягко, а не исчезает рывком.
      resizeDuration: const Duration(milliseconds: 300),
      direction: DismissDirection.endToStart,
      confirmDismiss: confirmDismiss,
      onDismissed: onDismissed,
      background: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalInset),
        // Фон удаления изолирован от перерисовки содержимого карточки.
        child: RepaintBoundary(
          child: animatedDeleteBackground(
            context,
            borderRadius: borderRadius,
          ),
        ),
      ),
      child: child,
    );
  }
}
