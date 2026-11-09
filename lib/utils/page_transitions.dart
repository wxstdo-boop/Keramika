import 'package:flutter/material.dart';

import 'motion_prefs.dart';

/// Длительность перехода с учётом «убрать анимации».
///
/// Когда движение выключено (системный запрос или тумблер в настройках),
/// переход схлопывается в ноль: смена экрана происходит мгновенно, без
/// пролёта и масштаба. Раньше переходы шли всегда, даже когда человек прямо
/// просил систему их убрать.
Duration _routeDuration(Duration d) =>
    MotionPrefs.shouldReduceMotion ? Duration.zero : d;

/// Сколько длится закрытие [slideUpRoute] (обратная анимация).
///
/// Нужен вызывающей стороне: `await Navigator.push(...)` возвращается в
/// НАЧАЛЕ этого отрезка, а не в конце. Кто после закрытия окна меняет
/// порядок списка (переезд карточки), обязан дождаться конца, иначе
/// анимация перестановки накладывается на выезд страницы.
const Duration slideUpReverseDuration = Duration(milliseconds: 240);

/// Плавный переход снизу вверх (для горизонтальных списков).
///
/// Заметный, но лёгкий: страница поднимается снизу с fade — без масштаба.
/// ScaleTransition на тяжёлых экранах (add alarm/habit) заставлял GPU
/// перефильтровывать весь слой каждый кадр перехода.
Route<T> slideUpRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    // Имя роута = тип страницы: по нему jank-проба подписывает кадры
    // (см. lib/utils/jank_probe.dart).
    settings: RouteSettings(name: page.runtimeType.toString()),
    transitionDuration: _routeDuration(const Duration(milliseconds: 380)),
    reverseTransitionDuration: _routeDuration(slideUpReverseDuration),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      // Без ScaleTransition: масштаб на тяжёлых экранах (add alarm/habit)
      // заставляет GPU перефильтровывать весь слой каждый кадр перехода.
      // Slide + fade достаточно читаются и дешевле.
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: child,
        ),
      );
    },
  );
}

/// Сколько длится закрытие [lockRoute] (обратная анимация).
const Duration lockRouteReverseDuration = Duration(milliseconds: 340);

/// Переход к PIN-экрану и обратно — СИММЕТРИЧНЫЙ кросс-фейд.
///
/// Только fade — БЕЗ масштаба. Масштаб на весь экран ПИН-экрана
/// (медальон с бесконечным циклом + стеклянный витраж) заставлял GPU
/// каждый кадр перефильтровывать большой слой.
Route<T> lockRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    transitionDuration: _routeDuration(lockRouteReverseDuration),
    reverseTransitionDuration: _routeDuration(lockRouteReverseDuration),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

/// Лёгкий вход на ДОМАШНИЙ экран после сплэша/PIN.
///
/// Только мягкий crossfade. Дом содержит сразу 4 экрана (PageView +
/// keepAlive), поэтому тяжёлый slide+scale на весь контент на первом
/// кадре после сплэша выглядел как «подтормоз».
Route<T> homeEntryRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    transitionDuration: _routeDuration(const Duration(milliseconds: 340)),
    reverseTransitionDuration: _routeDuration(const Duration(milliseconds: 220)),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

/// Плавный переход снизу вверх для диалогов.
Route<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    transitionDuration: _routeDuration(const Duration(milliseconds: 300)),
    reverseTransitionDuration: _routeDuration(const Duration(milliseconds: 200)),
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
    settings: RouteSettings(name: page.runtimeType.toString()),
    transitionDuration: _routeDuration(const Duration(milliseconds: 300)),
    reverseTransitionDuration: _routeDuration(const Duration(milliseconds: 220)),
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
