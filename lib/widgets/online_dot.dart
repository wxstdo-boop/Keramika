import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/motion_prefs.dart';
import 'press_scale.dart';

/// Красный кружок онлайна: «горит» справа от последней буквы заголовка и рядом
/// с именем в профиле.
///
/// Слушает [ProfileService]: когда профиль переключает онлайн-статус, кружок
/// сам перетекает между «налитым красным» и «пустым» (прозрачная середина,
/// тонкое кольцо) — без резкого щелчка цвета. Тап по кружку открывает профиль
/// (или переключает статус — задаёт вызывающий): зона нажатия заметно больше
/// самого глифа (см. [tapTarget]), чтобы по нему было удобно попадать пальцем.
class OnlineDot extends StatefulWidget {
  /// Диаметр самого кружка по умолчанию, px.
  static const double dotSize = 9;

  /// Диаметр зоны тапа, px: сам кружок маленький, но палец должен попадать.
  /// Публичен, чтобы вызывающие могли скомпенсировать «свес» зоны в лэйауте
  /// (она шире глифа — см. шапку профиля).
  static const double tapTarget = 30;

  /// Тот же «кровавый», что у свежего релиза и сплэша.
  static const Color _blood = Color(0xFFE53935);

  final VoidCallback onTap;

  /// Диаметр кружка, px. В шапке он мельче ([dotSize]), у имени — крупнее.
  final double size;

  /// Глубина «вдавливания» под пальцем. Меньше 1 — кружок мягко сжимается.
  final double pressedScale;

  /// Радиус фона, подсвечиваемого при зажатии. По умолчанию круг (равен
  /// половине зоны тапа); у кружка в шапке профиля фон квадратный — там
  /// задаётся скруглённый прямоугольник, чтобы подсветка не читалась углом.
  final double pressedBorderRadius;

  /// Длительность перетекания «красный ↔ пустой» и вдавливания. Долгая по
  /// умолчанию: смена статуса читается как «дыхание», а не как мигание.
  final Duration duration;

  const OnlineDot({
    super.key,
    required this.onTap,
    this.size = dotSize,
    this.pressedScale = 0.78,
    this.pressedBorderRadius = tapTarget / 2,
    this.duration = const Duration(milliseconds: 640),
  });

  @override
  State<OnlineDot> createState() => _OnlineDotState();
}

class _OnlineDotState extends State<OnlineDot> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: ProfileService(),
      builder: (context, _) {
        final online = ProfileService().online;
        // При «убрать анимации» кружок переключается мгновенно: плавное
        // перетекание цвета — как раз тот декоративный эффект, который
        // выключает тумблер.
        final reduce = MotionPrefs.shouldReduceMotion;
        final duration = reduce ? Duration.zero : widget.duration;
        return PressScale(
          pressedScale: widget.pressedScale,
          duration: duration,
          child: Semantics(
            button: true,
            label: online ? 'Online' : 'Offline',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.light();
                widget.onTap();
              },
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              child: SizedBox(
                width: OnlineDot.tapTarget,
                height: OnlineDot.tapTarget,
                // Фон тапа — со скруглением, а не квадрат: под пальцем он
                // мягко подсвечивается в тон кружка и так же мягко гаснет.
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  decoration: BoxDecoration(
                    color: _pressed
                        ? OnlineDot._blood.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      widget.pressedBorderRadius,
                    ),
                  ),
                  child: Center(
                    // Пустой кружок чуть меньше налитого: смена статуса видна
                    // и по размеру, и по цвету — но мягко, вместе с цветом.
                    child: AnimatedScale(
                      scale: online ? 1.0 : 0.82,
                      duration: duration,
                      curve: Curves.easeInOutCubic,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeInOutCubic,
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // Монотонный полупрозрачный красный ↔ прозрачная
                          // середина: «пусто». Без свечения и градиента —
                          // ровная матовая заливка, ничего не «отсвечивает».
                          color: online
                              ? OnlineDot._blood.withValues(alpha: 0.55)
                              : Colors.transparent,
                          // У пустого остаётся тонкое кольцо — иначе он бы
                          // просто исчез и статус читался бы как «нет данных».
                          border: Border.all(
                            color: online
                                ? OnlineDot._blood.withValues(alpha: 0.75)
                                : theme.colorScheme.outline.withValues(
                                    alpha: 0.45,
                                  ),
                            width: online ? 1.0 : 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
