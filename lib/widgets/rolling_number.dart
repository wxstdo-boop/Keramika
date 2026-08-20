import 'dart:async';
import '../services/haptics.dart';
import 'package:flutter/material.dart';

/// Стрелочный степпер с автоповтором — единый для всех пикеров времени.
///
/// Тап: один шаг с лёгким хаптиком. Зажатие: первый шаг сразу, затем через
/// 380мс плавный быстрый повтор каждые 85мс — цифры «прокручиваются»
/// без клавиатуры.
class HoldStepper extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStep;
  final double iconSize;
  final Color? color;

  const HoldStepper({
    super.key,
    required this.icon,
    required this.onStep,
    this.iconSize = 22,
    this.color,
  });

  @override
  State<HoldStepper> createState() => _HoldStepperState();
}

class _HoldStepperState extends State<HoldStepper> {
  Timer? _repeat;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _begin() {
    // Первый шаг — мгновенно (тап), хаптик только здесь, не на каждом
    // повторе (иначе при автоповторе телефон будет «зудеть»).
    Haptics.select();
    widget.onStep();
    _repeat?.cancel();
    // Короткая пауза, затем быстрый автоповтор.
    _repeat = Timer(const Duration(milliseconds: 380), () {
      _repeat = Timer.periodic(const Duration(milliseconds: 85), (_) {
        widget.onStep();
      });
    });
  }

  void _end() {
    _repeat?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _begin(),
      onTapUp: (_) => _end(),
      onTapCancel: _end,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: widget.color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// «Ролик» цифр: значение меняется плавным скольжением в сторону изменения
/// (вверх при инкременте, вниз при декременте) — как колёсико счётчика.
/// Оборачивается в [ClipRect], чтобы уходящая цифра не вылезала за рамку.
class RollingNumber extends StatelessWidget {
  final String value;
  final int delta;
  final TextStyle style;
  final BoxDecoration? decoration;
  final double? width;
  final EdgeInsetsGeometry padding;
  final Duration duration;
  final double slideFraction;

  const RollingNumber({
    super.key,
    required this.value,
    required this.delta,
    required this.style,
    this.decoration,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    this.duration = const Duration(milliseconds: 160),
    this.slideFraction = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      alignment: Alignment.center,
      decoration: decoration,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            // Инкремент: новая цифра въезжает снизу, старая уходит вниз.
            // Декремент: наоборот — сверху. Чистый эффект «колеса».
            final dir = delta >= 0 ? 1.0 : -1.0;
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, slideFraction * dir),
                end: Offset.zero,
              ).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Text(
            value,
            key: ValueKey(value),
            style: style,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
