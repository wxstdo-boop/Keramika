import 'package:flutter/material.dart';
import '../services/haptics.dart';

/// Круглый плавный переключатель вместо кнопки-свитча: маленький кружок,
/// который мягко «наливается» цветом, растёт и получает галочку при
/// включении. Все переходы анимированы — без резких скачков.
class SmoothCircleToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final double size;

  const SmoothCircleToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = activeColor ?? scheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null
          ? null
          : () {
              Haptics.select();
              onChanged!(!value);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: value
              ? RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  radius: 1.1,
                  colors: [Color.lerp(active, Colors.white, 0.25)!, active],
                )
              : null,
          color: value
              ? null
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          border: Border.all(
            color: value
                ? active
                : scheme.outlineVariant.withValues(alpha: 0.7),
            width: value ? 1.6 : 1.4,
          ),
          boxShadow: [
            if (value)
              BoxShadow(
                color: active.withValues(alpha: 0.45),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: value
              ? Icon(
                  Icons.check,
                  key: const ValueKey('on'),
                  size: size * 0.6,
                  color: Colors.white,
                )
              : const SizedBox.shrink(key: ValueKey('off')),
        ),
      ),
    );
  }
}
