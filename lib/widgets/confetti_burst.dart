import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Пасхалка: взрыв конфетти через Overlay. Частицы сыпятся сверху под
/// «гравитацией» с кувырканием; цвета — из актуальной темы (Material You),
/// поэтому конфетти всегда «в бренде». Ресурсы бережём: один CustomPainter,
/// RepaintBoundary, автоудаление entry по окончании.
void showConfettiBurst(BuildContext context, {int count = 90}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final scheme = Theme.of(context).colorScheme;
  final colors = [
    scheme.primary,
    scheme.tertiary,
    scheme.secondary,
    scheme.error,
    const Color(0xFFF06292), // фирменный FOSS-розовый со сплэша
  ];
  late final OverlayEntry entry;
  entry = OverlayEntry(
    // IgnorePointer: конфетти не перехватывает тапы под собой.
    builder: (_) => IgnorePointer(
      child: RepaintBoundary(
        child: _ConfettiLayer(colors: colors, count: count),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(milliseconds: 3200), entry.remove);
}

class _ConfettiLayer extends StatefulWidget {
  const _ConfettiLayer({required this.colors, required this.count});
  final List<Color> colors;
  final int count;

  @override
  State<_ConfettiLayer> createState() => _ConfettiLayerState();
}

class _ConfettiLayerState extends State<_ConfettiLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    _pieces = List.generate(widget.count, (i) {
      return _Piece(
        x0: rnd.nextDouble(),
        drift: (rnd.nextDouble() - 0.5) * 0.35,
        delay: rnd.nextDouble() * 0.35,
        fallSpeed: 0.75 + rnd.nextDouble() * 0.6,
        size: 5 + rnd.nextDouble() * 6,
        spin: (rnd.nextDouble() < 0.5 ? -1 : 1) * (4 + rnd.nextDouble() * 8),
        wobble: 0.02 + rnd.nextDouble() * 0.05,
        color: widget.colors[i % widget.colors.length],
        shape: i % 3,
      );
    });
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(_ctrl.value, _pieces),
      ),
    );
  }
}

class _Piece {
  _Piece({
    required this.x0,
    required this.drift,
    required this.delay,
    required this.fallSpeed,
    required this.size,
    required this.spin,
    required this.wobble,
    required this.color,
    required this.shape,
  });
  final double x0, drift, delay, fallSpeed, size, spin, wobble;
  final Color color;
  final int shape;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces);
  final double t;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Плавный разгон в начале и замедление к концу — «с мягким началом
      // и концом», без резкого старта.
      final eased = Curves.easeInCubic.transform(local);
      final fall = p.fallSpeed * eased;
      final y = -p.size + fall * (size.height + p.size * 4);
      if (y > size.height + p.size) continue;
      final x =
          (p.x0 +
              p.drift * eased +
              math.sin(local * math.pi * 6 * p.wobble * 10) * 0.03) *
          size.width;
      final angle = local * p.spin;
      final fade = local > 0.8 ? ((1 - local) / 0.2).clamp(0.0, 1.0) : 1.0;
      // Кувырок: ширина осциллирует — плоская фигура выглядит живой.
      final scaleX = math.cos(angle).abs() * 0.8 + 0.2;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle * 0.6);
      canvas.scale(scaleX, 1);
      paint.color = p.color.withValues(alpha: 0.9 * fade);
      final r = p.size / 2;
      switch (p.shape) {
        case 0:
          canvas.drawRect(Rect.fromLTRB(-r, -r * 0.6, r, r * 0.6), paint);
        case 1:
          canvas.drawCircle(Offset.zero, r * 0.7, paint);
        default:
          final path = Path()
            ..moveTo(0, -r)
            ..lineTo(r, r)
            ..lineTo(-r, r)
            ..close();
          canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
