import 'package:flutter/material.dart';

/// Плавный переход снизу вверх (для горизонтальных списков).
///
/// Заметный, но лёгкий: страница поднимается снизу с лёгким «подскоком»
/// масштаба и fade — окно (будильник/задача) открывается ощутимо, но без
/// тяжёлых эффектов (blur/saveLayer) — кадры на Redmi Note 12 не роняются.
Route<T> slideUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Плавный переход снизу вверх для диалогов.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Плавный боковой переход (справа налево для входа, слева направо для выхода)
/// с лёгким затемнением фонового экрана.
///
/// Без BackdropFilter (blur) — он ронял кадры на Redmi Note 12. И без
/// FadeTransition: полупрозрачная страница поверх старого экрана выглядела
/// как «смазанный текст». Новая страница всегда НЕПРОЗРАЧНАЯ — текст
/// остаётся чётким, позади только лёгкое затемнение.
Route<T> slideSideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          // Лёгкое затемнение старого экрана — дёшево, без saveLayer/blur.
          Container(
            color: Colors.black.withValues(alpha: 0.10 * animation.value),
          ),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ],
      );
    },
  );
}
