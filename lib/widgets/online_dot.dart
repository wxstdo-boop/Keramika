import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/motion_prefs.dart';
import 'press_scale.dart';

/// Красный кружок онлайна: «горит» над последней буквой заголовка и рядом с
/// именем в профиле.
///
/// Слушает [ProfileService]: когда профиль переключает онлайн-статус, кружок
/// сам перетекает между «налитым красным» и «пустым» (прозрачная середина,
/// тонкое кольцо) — без резкого щелчка цвета. Тап по кружку открывает профиль
/// (или переключает статус — задаёт вызывающий): зона нажатия заметно больше
/// самого глифа (см. [_tapTarget]), чтобы по нему было удобно попадать пальцем.
class OnlineDot extends StatelessWidget {
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

  const OnlineDot({super.key, required this.onTap, this.size = dotSize});

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
        // Длиннее обычного: переход красный ↔ пустой читается как «дыхание»,
        // а не как мигание.
        final duration = reduce
            ? Duration.zero
            : const Duration(milliseconds: 420);
        return PressScale(
          pressedScale: 0.82,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
          child: Semantics(
            button: true,
            label: online ? 'Online' : 'Offline',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.light();
                onTap();
              },
              child: SizedBox(
                width: tapTarget,
                height: tapTarget,
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
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Монотонный полупрозрачный красный ↔ прозрачная
                        // середина: «пусто». Без свечения и градиента —
                        // ровная матовая заливка, ничего не «отсвечивает».
                        color: online
                            ? _blood.withValues(alpha: 0.55)
                            : Colors.transparent,
                        // У пустого остаётся тонкое кольцо — иначе он бы
                        // просто исчез и статус читался бы как «нет данных».
                        border: Border.all(
                          color: online
                              ? _blood.withValues(alpha: 0.75)
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
        );
      },
    );
  }
}
