import 'package:flutter/material.dart';
import '../services/haptics.dart';

/// Переключатель в стиле Material 3: тонкий трек с цветной заливкой при
/// включении, белая шайба с цветным ядром и мягкой тенью. Объём лёгкий —
/// блик на шайбе + свечение трека, без «пухлого» корпуса. Аккуратный,
/// как стандартный switch на скриншоте, но чуть живее. При переключении
/// — короткий тактильный отклик.
class VolumetricSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  /// Масштаб трека/шайбы. 1.0 — стандартный (52×30). В плотных списках
  /// уголка разработчика берём крупнее — переключатель пару «объёмнее»
  /// и по нему комфортнее попадать пальцем.
  final double scale;

  const VolumetricSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = activeColor ?? scheme.primary;
    final trackOff = scheme.surfaceContainerHighest;
    final trackOn = active.withValues(alpha: 0.85);
    final k = scale;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null
          ? null
          : () {
              Haptics.select();
              onChanged!(!value);
            },
      child: AnimatedContainer(
        // Переключение цвета трека — медленное и тягучее (420 мс,
        // easeInOutCubic): свет «разгорается», а не щёлкает.
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        width: 52 * k,
        height: 30 * k,
        padding: EdgeInsets.all(3 * k),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15 * k),
          color: value ? trackOn : trackOff,
          border: Border.all(
            color: value
                ? active.withValues(alpha: 0.9)
                : scheme.outlineVariant.withValues(alpha: 0.7),
            width: 1 * k,
          ),
          boxShadow: [
            if (value)
              BoxShadow(
                color: active.withValues(alpha: 0.5 * k),
                blurRadius: 12 * k,
                offset: Offset(0, 2 * k),
              ),
          ],
        ),
        child: Stack(
          children: [
            // Стеклянный отлив поверх трека: подсветка сверху → тень
            // снизу — корпус читается выпуклым («объёмным») в любом
            // состоянии, а не плоской колбасой.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15 * k),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: value ? 0.34 : 0.20),
                        Colors.white.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.07),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Шайба-«клавиша» с пружинным ходом.
            AnimatedAlign(
              // Ход шайбы — дольше и «жирнее» прежнего: пружина доводит
              // клавишу с лёгким перебором на 460 мс.
              duration: const Duration(milliseconds: 460),
              curve: Curves.easeOutBack,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24 * k,
                height: 24 * k,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.5),
                    radius: 1.2,
                    colors: [Colors.white, Colors.white.withValues(alpha: 0.8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.34),
                      blurRadius: 6 * k,
                      offset: Offset(0, 2 * k),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 1 * k,
                  ),
                ),
                child: Center(
                  child: AnimatedContainer(
                    // Ядро на шайбе надувается медленнее (320 мс) — в такт
                    // ходу самой клавиши.
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutBack,
                    width: (value ? 9 : 8) * k,
                    height: (value ? 9 : 8) * k,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value
                          ? active
                          : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      boxShadow: [
                        BoxShadow(
                          color: value
                              ? active.withValues(alpha: 0.55)
                              : Colors.black.withValues(alpha: 0.12),
                          blurRadius: 2.5 * k,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
