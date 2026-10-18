import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/haptics.dart';

/// Чистая лупа поиска в AppBar настроек.
///
/// Оформление: полупрозрачная серая круглая плашка с тонкой обводкой и
/// ЧЁТКОЙ кастомной лупой внутри (своя кисть через CustomPaint, без
/// ShaderMask — градиентная маска давала «пиксельную»/мелкую картинку).
///
/// Пока функция поиска не подключена: тап только оживляет значок —
/// мягкий подскок и затухающее покачивание. Защита от мультитапов: пока
/// анимация жива, новые тапы игнорируются (тот же приём, что у канарейки).
class SettingsSearchIcon extends StatefulWidget {
  const SettingsSearchIcon({super.key});

  @override
  State<SettingsSearchIcon> createState() => _SettingsSearchIconState();
}

class _SettingsSearchIconState extends State<SettingsSearchIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    // Мультитап-защита: второй тап во время анимации её не «дёргает».
    if (_ctrl.isAnimating) return;
    Haptics.select();
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    // Полупрозрачный СЕРЫЙ фон плашки — читаемый и на светлой, и на
    // тёмной теме (не брём «чужой» цвет из палитры, а нейтральный серый).
    final bg =
        (dark ? const Color(0xFFC5CBD4) : const Color(0xFF8A919C))
            .withValues(alpha: dark ? 0.18 : 0.15);
    final stroke = cs.outlineVariant.withValues(alpha: dark ? 0.55 : 0.65);
    final iconColor = cs.onSurface.withValues(alpha: 0.86);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Padding(
        // Небольшая «подушка»: палец попадает легко, плашка остаётся
        // компактной.
        padding: const EdgeInsets.all(5),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            // Мягкий «взгляд»: подскок полуволной + затухающее покачивание.
            final pulse = math.sin(math.pi * t);
            final scale = 1.0 + 0.12 * pulse;
            final wiggle = 0.14 * math.sin(2 * math.pi * t) * (1 - t);
            return Transform.rotate(
              angle: wiggle,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    // Тоненькая красивая обводка по краю круглой плашки.
                    border: Border.all(color: stroke, width: 1),
                  ),
                  child: Center(
                    // Чёткая кастомная лупа (без «пикселей»).
                    child: _MagnifierIcon(size: 17, color: iconColor),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Чистая лупа собственной кистью (CustomPaint): тонкое кольцо + ножка со
/// скруглённым концом. Без ShaderMask — контур аккуратный и чёткий.
class _MagnifierIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _MagnifierIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _MagnifierPainter(color: color));
  }
}

class _MagnifierPainter extends CustomPainter {
  final Color color;
  _MagnifierPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Кольцо: слегка смещено в верхний-левый угол, чтобы ножка уходила
    // в правый нижний (классическая композиция лупы).
    final ringR = s * 0.34;
    final ringC = Offset(s * 0.43, s * 0.43);
    canvas.drawCircle(ringC, ringR, paint);

    // Ножка: от 45°-точки нижней части кольца вниз-вправо, с заострением.
    final start = ringC + Offset(ringR * 0.72, ringR * 0.72);
    final end = Offset(s * 0.86, s * 0.86);
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _MagnifierPainter old) => old.color != color;
}
