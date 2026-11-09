import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/motion_prefs.dart';
import 'press_scale.dart';

/// Красный кружок онлайна под буквой «K» в заголовке «Keramika».
///
/// Слушает [ProfileService]: когда профиль переключает онлайн-статус, кружок
/// загорается/гаснет сам, без пересборки всего заголовка. Тап по кружку
/// открывает профиль — зона нажатия заметно больше самого глифа (см.
/// [_tapTarget]), чтобы по нему было удобно попадать пальцем.
class OnlineDot extends StatelessWidget {
  /// Диаметр самого кружка, px.
  static const double dotSize = 9;

  /// Диаметр зоны тапа, px: сам кружок маленький, но палец должен попадать.
  static const double _tapTarget = 30;

  final VoidCallback onTap;

  const OnlineDot({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProfileService(),
      builder: (context, _) {
        final online = ProfileService().online;
        // При «убрать анимации» кружок переключается мгновенно: плавное
        // перетекание цвета — как раз тот декоративный эффект, который
        // выключает тумблер.
        final reduce = MotionPrefs.shouldReduceMotion;
        return PressScale(
          pressedScale: 0.82,
          duration: reduce
              ? Duration.zero
              : const Duration(milliseconds: 160),
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
                width: _tapTarget,
                height: _tapTarget,
                child: Center(
                  child: AnimatedContainer(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: online
                          ? const Color(0xFFE53935).withValues(alpha: 0.88)
                          : Colors.grey.withValues(alpha: 0.45),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.65),
                        width: 1.2,
                      ),
                      boxShadow: online
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFFE53935,
                                ).withValues(alpha: 0.55),
                                blurRadius: 7,
                                spreadRadius: 0.6,
                              ),
                            ]
                          : null,
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
