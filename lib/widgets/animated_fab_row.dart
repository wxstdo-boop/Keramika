import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Плавно прячет/возвращает ряд FAB-кнопок (плюс + Ада) при прокрутке.
///
/// [visible] — слушаемое состояние видимости: скрывается при скролле вниз,
/// возвращается при долистывании до верха. Анимация мягкая (slide + fade),
/// чтобы на слабых телефонах не было рывков.
class AnimatedFabRow extends StatelessWidget {
  final ValueListenable<bool> visible;
  final Widget child;
  const AnimatedFabRow({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, isVisible, _) {
        return AnimatedSlide(
          offset: isVisible ? Offset.zero : const Offset(0, 1.4),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: IgnorePointer(ignoring: !isVisible, child: child),
          ),
        );
      },
    );
  }
}

/// Универсальный слушатель скролла: прячет FAB, когда контент ушёл вниз
/// больше чем на [hideThreshold] пикселей, и возвращает при долистывании
/// до верха (offset <= [showThreshold]).
class FabScrollListener extends StatelessWidget {
  final ValueNotifier<bool> visible;
  final Widget child;
  final double hideThreshold;
  final double showThreshold;

  const FabScrollListener({
    super.key,
    required this.visible,
    required this.child,
    this.hideThreshold = 48,
    this.showThreshold = 8,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final pixels = n.metrics.pixels;
        if (pixels > hideThreshold && visible.value) {
          visible.value = false;
        } else if (pixels <= showThreshold && !visible.value) {
          visible.value = true;
        }
        return false;
      },
      child: child,
    );
  }
}
