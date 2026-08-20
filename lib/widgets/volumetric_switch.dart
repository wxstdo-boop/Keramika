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

  const VolumetricSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = activeColor ?? scheme.primary;
    final trackOff = scheme.surfaceContainerHighest;
    final trackOn = active.withValues(alpha: 0.85);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null
          ? null
          : () {
              Haptics.select();
              onChanged!(!value);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: 52,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: value ? trackOn : trackOff,
          border: Border.all(
            color: value
                ? active.withValues(alpha: 0.9)
                : scheme.outlineVariant.withValues(alpha: 0.7),
            width: 1,
          ),
          boxShadow: [
            if (value)
              BoxShadow(
                color: active.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Stack(
          children: [
            // Шайба-«клавиша» с пружинным ходом.
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.5),
                    radius: 1.2,
                    colors: [Colors.white, Colors.white.withValues(alpha: 0.8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: value ? 9 : 8,
                    height: value ? 9 : 8,
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
                          blurRadius: 2.5,
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
