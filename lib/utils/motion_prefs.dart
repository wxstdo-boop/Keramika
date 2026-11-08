import 'package:flutter/material.dart';

/// Уважение к системной и пользовательской настройке «убрать анимации».
///
/// Зачем: в приложении есть постоянные декоративные циклы (дыхание свечения,
/// блики стекла, стая птиц, «глитч» чисел статистики). Человеку, который
/// включил «Убрать анимации» в системе или в настройках приложения, они
/// мешают, а на слабом GPU ещё и жгут бюджет кадра. Здесь одна точка правды:
/// декоративные петли и переходы спрашивают [shouldReduceMotion] и
/// выключаются, если движение не нужно.
///
/// Системный флаг (`AccessibilityFeatures.disableAnimations`) имеет приоритет:
/// если человек уже попросил систему упростить анимации, приложение не должно
/// спорить. Пользовательский переключатель может только ДОБАВИТЬ упрощение,
/// но не отменить системный запрос. Само значение тумблера читает и пишет
/// `SettingsService` — здесь только живой флаг.
abstract final class MotionPrefs {
  MotionPrefs._();

  /// Живой флаг: виджеты с вечными циклами слушают его и останавливают
  /// контроллеры сразу при смене (см. [MotionAwareRepeat]).
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// Системный запрос «убрать анимации» без BuildContext.
  static bool get systemReduceMotion {
    try {
      return WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;
    } catch (_) {
      return false;
    }
  }

  /// Итог для мест без контекста: системный флаг ИЛИ ручной тумблер.
  static bool get shouldReduceMotion => systemReduceMotion || enabled.value;
}

/// Миксин для виджетов с бесконечными декоративными циклами: следит за
/// тумблером «убрать анимации» и останавливает/запускает контроллеры.
///
/// Использование:
/// ```dart
/// class _FooState extends State<Foo> with SingleTickerProviderStateMixin,
///     MotionAwareRepeat {
///   late final AnimationController _ctrl = ambientRepeat(
///     AnimationController(vsync: this, duration: const Duration(seconds: 2)),
///   );
/// }
/// ```
mixin MotionAwareRepeat<T extends StatefulWidget> on State<T> {
  final List<AnimationController> _motionCtrls = [];
  final List<bool> _motionReverse = [];
  bool _motionListenerAttached = false;

  void _ensureMotionListener() {
    if (_motionListenerAttached) return;
    MotionPrefs.enabled.addListener(_onMotionChanged);
    _motionListenerAttached = true;
  }

  /// Регистрирует вечный цикл: контроллер крутится, только если движение
  /// разрешено. Возвращает тот же контроллер для удобной инициализации.
  AnimationController ambientRepeat(
    AnimationController controller, {
    bool reverse = false,
  }) {
    _motionCtrls.add(controller);
    _motionReverse.add(reverse);
    _ensureMotionListener();
    if (!MotionPrefs.shouldReduceMotion) controller.repeat(reverse: reverse);
    return controller;
  }

  /// Подписаться на тумблер БЕЗ регистрации контроллера — для виджетов с
  /// условным повтором (зависит от `active`), которые переопределяют
  /// [onMotionChanged] и сами решают, что перезапустить.
  void watchMotion() => _ensureMotionListener();

  /// Хук на смену тумблера. Переопределяйте, если у виджета свой критерий
  /// «крутиться или нет» (например, активный таймер).
  @protected
  void onMotionChanged() {}

  void _onMotionChanged() {
    if (!mounted) return;
    for (var i = 0; i < _motionCtrls.length; i++) {
      final c = _motionCtrls[i];
      if (MotionPrefs.shouldReduceMotion) {
        c.stop();
      } else if (!c.isAnimating) {
        c.repeat(reverse: _motionReverse[i]);
      }
    }
    onMotionChanged();
  }

  @override
  void dispose() {
    if (_motionListenerAttached) {
      MotionPrefs.enabled.removeListener(_onMotionChanged);
    }
    super.dispose();
  }
}
