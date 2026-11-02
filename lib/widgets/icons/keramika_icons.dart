import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Единая толщина обводки всех иконок Keramika.
const double kKkStroke = 2.0;

/// Базовый размер иконки (viewBox 24×24).
const double kKkIconSize = 24.0;

/// Общий виджет иконки с thin stroke.
class KkIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;
  final void Function(Canvas canvas, Size size, Color color, double strokeWidth) paint;

  const KkIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
    required this.paint,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _KkPainter(
          color: c,
          strokeWidth: strokeWidth,
          paintFn: paint,
        ),
      ),
    );
  }
}

class _KkPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final void Function(Canvas canvas, Size size, Color color, double strokeWidth) paintFn;

  const _KkPainter({
    required this.color,
    required this.strokeWidth,
    required this.paintFn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);
    paintFn(canvas, const Size(24, 24), color, strokeWidth);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_KkPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

// ────────────────────────────────────────────────────────────
// Helper-ы рисования (viewBox 24×24)
// ────────────────────────────────────────────────────────────

void _circle(Canvas canvas, double cx, double cy, double r, Paint p) =>
    canvas.drawCircle(Offset(cx, cy), r, p);

void _line(Canvas canvas, double x1, double y1, double x2, double y2, Paint p) =>
    canvas.drawLine(Offset(x1, y1), Offset(x2, y2), p);

void _path(Canvas canvas, Path path, Paint p) => canvas.drawPath(path, p);

Paint _p(Color c, double sw) => Paint()
  ..color = c
  ..strokeWidth = sw
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

// ────────────────────────────────────────────────────────────
// Разделы (таблетка разделов на главном экране)
// ────────────────────────────────────────────────────────────

/// Будильник: циферблат, два колокольчика, молоточек.
class KkAlarmIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkAlarmIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        // Циферблат
        _circle(canvas, 12, 12, 5.5, p);
        // Чёрточки часов
        _line(canvas, 12, 6.6, 12, 7.8, p);
        _line(canvas, 16.4, 14.9, 17.6, 16.1, p);
        _line(canvas, 12, 16.2, 12, 17.4, p);
        _line(canvas, 7.6, 14.9, 6.4, 16.1, p);
        // Колокольчики
        _circle(canvas, 8.2, 9.2, 2.6, p);
        _circle(canvas, 15.8, 9.2, 2.6, p);
        _line(canvas, 8.2, 6.6, 8.2, 7.9, p);
        _line(canvas, 15.8, 6.6, 15.8, 7.9, p);
        // Молоточек
        _line(canvas, 12, 8.6, 12, 10.4, p);
        _line(canvas, 12, 10.4, 13.4, 11.4, p);
      },
    );
  }
}

/// Привычки: три растущих дуги + капли.
class KkHabitsIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkHabitsIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        final p1 = Path()..addArc(Rect.fromCircle(center: Offset(8, 16), radius: 6), -math.pi, -math.pi / 2);
        final p2 = Path()..addArc(Rect.fromCircle(center: Offset(12, 16), radius: 6), -math.pi, -math.pi / 2);
        final p3 = Path()..addArc(Rect.fromCircle(center: Offset(16, 16), radius: 5), -math.pi, -math.pi / 2);
        _path(canvas, p1, p);
        _path(canvas, p2, p);
        _path(canvas, p3, p);
        _circle(canvas, 8, 15.6, 1.1, p);
        _circle(canvas, 12, 15.6, 1.1, p);
        _circle(canvas, 16, 15.4, 1.1, p);
      },
    );
  }
}

/// Задачи: три строки с галочками.
class KkTasksIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkTasksIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        for (final y in [8.2, 12.0, 15.8]) {
          _line(canvas, 6.4, y, 13.2, y, p);
          _line(canvas, 13.2, y, 14.6, y + 1.2, p);
          _line(canvas, 14.6, y + 1.2, 17.2, y - 1.2, p);
        }
      },
    );
  }
}

/// Проверка реальности: глаз со зрачком.
class KkRealityCheckIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkRealityCheckIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        final eye = Path()
          ..moveTo(7.2, 12)
          ..cubicTo(7.2, 9.4, 10.8, 7.8, 14.4, 7.8)
          ..cubicTo(18.0, 7.8, 21.6, 9.4, 21.6, 12)
          ..cubicTo(21.6, 14.6, 18.0, 16.2, 14.4, 16.2)
          ..cubicTo(10.8, 16.2, 7.2, 14.6, 7.2, 12)
          ..close();
        _path(canvas, eye, p);
        _circle(canvas, 14.4, 12, 2.2, p);
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
// Общие действия
// ────────────────────────────────────────────────────────────

class KkAddIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkAddIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 12, 8, 12, 16, p);
        _line(canvas, 8, 12, 16, 12, p);
      },
    );
  }
}

class KkCheckIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkCheckIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 8, 12, 11.4, 15.4, p);
        _line(canvas, 11.4, 15.4, 16.4, 8.6, p);
      },
    );
  }
}

class KkDeleteIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkDeleteIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 8.6, 7.2, 8.6, 17.2, p);
        _line(canvas, 15.4, 7.2, 15.4, 17.2, p);
        _line(canvas, 6.8, 17.2, 17.2, 17.2, p);
        _line(canvas, 7.8, 7.2, 16.2, 7.2, p);
        _line(canvas, 8.2, 8.4, 7.8, 7.2, p);
        _line(canvas, 15.8, 8.4, 16.2, 7.2, p);
        _line(canvas, 15.8, 8.4, 15.4, 7.2, p);
        _line(canvas, 7.2, 5.6, 16.8, 5.6, p);
        _line(canvas, 7.6, 5.6, 7.6, 7.2, p);
        _line(canvas, 16.4, 5.6, 16.4, 7.2, p);
      },
    );
  }
}

class KkEditIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkEditIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 16.4, 5.6, 19.6, 8.8, p);
        _line(canvas, 19.6, 8.8, 18.4, 10, p);
        _line(canvas, 18.4, 10, 15.2, 6.8, p);
        _line(canvas, 15.2, 6.8, 16.4, 5.6, p);
        _line(canvas, 17.6, 4.4, 19.2, 6, p);
        _line(canvas, 19.2, 6, 20.4, 4.8, p);
        _line(canvas, 4.8, 20.4, 6, 19.2, p);
      },
    );
  }
}

class KkSettingsIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkSettingsIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _circle(canvas, 12, 12, 4, p);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          _line(canvas,
              12 + 5.4 * math.cos(a).toDouble(),
              12 + 5.4 * math.sin(a).toDouble(),
              12 + 7.2 * math.cos(a).toDouble(),
              12 + 7.2 * math.sin(a).toDouble(),
              p);
        }
        _line(canvas, 12, 16.2, 12, 17.8, p);
      },
    );
  }
}

class KkBellIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkBellIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _path(canvas, Path()
          ..moveTo(8, 10)
          ..cubicTo(8, 6, 10, 4, 12, 4)
          ..cubicTo(14, 4, 16, 6, 16, 10), p);
        _line(canvas, 12, 4, 12, 14, p);
        _line(canvas, 7.4, 10, 7.4, 14, p);
        _line(canvas, 16.6, 10, 16.6, 14, p);
        _line(canvas, 6.8, 14, 17.2, 14, p);
        _line(canvas, 12, 14, 12, 17.6, p);
      },
    );
  }
}

class KkClockIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkClockIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _circle(canvas, 12, 12, 5, p);
        _line(canvas, 12, 12, 12, 7.4, p);
        _line(canvas, 12, 12, 15.4, 12, p);
      },
    );
  }
}

class KkStarIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkStarIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        final path = Path();
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / 5;
          final x = 12 + 4.6 * math.cos(a).toDouble();
          final y = 12 + 4.6 * math.sin(a).toDouble();
          if (i == 0) path.moveTo(x, y);
          path.lineTo(x, y);
        }
        path.close();
        _path(canvas, path, p);
      },
    );
  }
}

class KkHeartIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkHeartIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _path(canvas, Path()
          ..moveTo(12, 17.4)
          ..cubicTo(12, 17.4, 8.4, 15.4, 8.4, 11.4)
          ..cubicTo(8.4, 8.4, 10.6, 6.8, 12, 8)
          ..cubicTo(13.4, 6.8, 15.6, 8.4, 15.6, 11.4)
          ..cubicTo(15.6, 15.4, 12, 17.4, 12, 17.4)
          ..close(), p);
      },
    );
  }
}

class KkMoonIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkMoonIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _circle(canvas, 10, 10, 4, p);
        _circle(canvas, 12.8, 8.2, 4, p);
      },
    );
  }
}

class KkSunIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkSunIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _circle(canvas, 12, 12, 3, p);
        for (final (dx, dy) in const [
          (0, -5),
          (0, 5),
          (-5, 0),
          (5, 0),
          (-3.6, -3.6),
          (3.6, -3.6),
          (-3.6, 3.6),
          (3.6, 3.6),
        ]) {
          final dxd = dx.toDouble();
          final dyd = dy.toDouble();
          _line(canvas, 12 + dxd * 0.5, 12 + dyd * 0.5, 12 + dxd, 12 + dyd, p);
        }
      },
    );
  }
}

class KkArrowRightIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkArrowRightIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 8, 10, 16, 10, p);
        _line(canvas, 14, 8, 16, 10, p);
        _line(canvas, 14, 12, 16, 10, p);
      },
    );
  }
}

class KkArrowLeftIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkArrowLeftIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 16, 10, 8, 10, p);
        _line(canvas, 10, 8, 8, 10, p);
        _line(canvas, 10, 12, 8, 10, p);
      },
    );
  }
}

class KkMenuIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkMenuIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 6, 8, 18, 8, p);
        _line(canvas, 6, 12, 18, 12, p);
        _line(canvas, 6, 16, 18, 16, p);
      },
    );
  }
}

class KkCloseIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkCloseIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 8, 8, 16, 16, p);
        _line(canvas, 16, 8, 8, 16, p);
      },
    );
  }
}

class KkSearchIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkSearchIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _circle(canvas, 10, 10, 4, p);
        _line(canvas, 12.8, 12.8, 16.6, 16.6, p);
      },
    );
  }
}

class KkFilterIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkFilterIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 12, 6, 12, 12, p);
        _line(canvas, 10, 10, 14, 10, p);
        _line(canvas, 8, 14, 16, 14, p);
        _line(canvas, 6, 18, 18, 18, p);
      },
    );
  }
}

class KkShareIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkShareIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 12, 6, 12, 14, p);
        _line(canvas, 8, 10, 12, 14, p);
        _line(canvas, 16, 10, 12, 14, p);
        _line(canvas, 12, 18, 8, 22, p);
        _line(canvas, 12, 18, 16, 22, p);
      },
    );
  }
}

class KkDownloadIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkDownloadIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 12, 6, 12, 14, p);
        _line(canvas, 10, 10, 12, 14, p);
        _line(canvas, 14, 10, 12, 14, p);
        _line(canvas, 8, 18, 16, 18, p);
      },
    );
  }
}

class KkUploadIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkUploadIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _line(canvas, 12, 10, 12, 18, p);
        _line(canvas, 10, 12, 12, 18, p);
        _line(canvas, 14, 12, 12, 18, p);
        _line(canvas, 8, 18, 16, 18, p);
      },
    );
  }
}

class KkLockIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkLockIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _path(canvas, Path()
          ..moveTo(12, 8)
          ..lineTo(12, 12)
          ..lineTo(8.4, 12)
          ..lineTo(8.4, 17)
          ..lineTo(15.6, 17)
          ..lineTo(15.6, 12)
          ..lineTo(12, 12)
          ..close(), p);
        _line(canvas, 12, 8, 12, 10.4, p);
        _line(canvas, 11.4, 11.4, 12.6, 11.4, p);
      },
    );
  }
}

class KkUnlockIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const KkUnlockIcon({
    super.key,
    this.size = kKkIconSize,
    this.color,
    this.strokeWidth = kKkStroke,
  });

  @override
  Widget build(BuildContext context) {
    return KkIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        _path(canvas, Path()
          ..moveTo(12, 8)
          ..lineTo(12, 12)
          ..lineTo(8.4, 12)
          ..lineTo(8.4, 17)
          ..lineTo(15.6, 17)
          ..lineTo(15.6, 12)
          ..lineTo(12, 12)
          ..close(), p);
        _line(canvas, 12.6, 9, 14.6, 9, p);
        _line(canvas, 14.6, 9, 14.6, 11.4, p);
      },
    );
  }
}
