import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Единая толщина обводки всех иконок Agysha.
const double kAgStroke = 2.0;

/// Базовый размер иконки (viewBox 24×24).
const double kAgIconSize = 24.0;

/// Общий виджет иконки с thin stroke.
class AgIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;
  final void Function(Canvas canvas, Size size, Color color, double strokeWidth) paint;

  const AgIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
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
        painter: _AgPainter(
          color: c,
          strokeWidth: strokeWidth,
          paintFn: paint,
        ),
      ),
    );
  }
}

class _AgPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final void Function(Canvas canvas, Size size, Color color, double strokeWidth) paintFn;

  const _AgPainter({
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
  bool shouldRepaint(_AgPainter old) =>
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
class AgAlarmIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgAlarmIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        // Циферблат по центру.
        _circle(canvas, 12, 13, 6.8, p);
        // Стрелки.
        _line(canvas, 12, 13, 12, 9, p);
        _line(canvas, 12, 13, 15.2, 13, p);
        // Колокольчики сверху: две короткие дуги, разведённые наружу.
        _path(canvas, Path()
          ..addArc(
            Rect.fromCircle(center: const Offset(7.2, 6.6), radius: 2.6),
            math.pi * 1.02,
            math.pi * 0.52,
          ), p);
        _path(canvas, Path()
          ..addArc(
            Rect.fromCircle(center: const Offset(16.8, 6.6), radius: 2.6),
            math.pi * 1.46,
            math.pi * 0.52,
          ), p);
      },
    );
  }
}

/// Привычки: три растущих дуги + капли.
class AgHabitsIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgHabitsIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        // Огонёк серии: язык пламени с внутренним завитком — читается как
        // «держится уже N дней». Три дуги прежней версии не читались ни в
        // каком масштабе.
        _path(canvas, Path()
          ..moveTo(12, 4.2)
          ..cubicTo(15.4, 7.6, 17.4, 10.2, 17.4, 13.6)
          ..cubicTo(17.4, 17.2, 15.0, 19.8, 12, 19.8)
          ..cubicTo(9.0, 19.8, 6.6, 17.2, 6.6, 13.6)
          ..cubicTo(6.6, 11.4, 7.6, 9.6, 9.2, 7.6)
          ..cubicTo(9.6, 9.6, 10.6, 10.8, 12, 11.4)
          ..cubicTo(12, 8.8, 11.6, 6.4, 12, 4.2)
          ..close(), p);
      },
    );
  }
}

/// Задачи: три строки с галочками.
class AgTasksIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgTasksIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        // Планшет с зажимом и галочкой: одна ясная фигура вместо трёх строк
        // с наползающими галочками, которые в 18 px сливались в штриховку.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(5.6, 5.4, 18.4, 19.8),
            const Radius.circular(2.6),
          ),
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(9.4, 3.4, 14.6, 7.0),
            const Radius.circular(1.6),
          ),
          p,
        );
        _line(canvas, 8.8, 12.6, 11.0, 14.8, p);
        _line(canvas, 11.0, 14.8, 15.2, 10.2, p);
      },
    );
  }
}

/// Проверка реальности: глаз со зрачком.
class AgRealityCheckIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgRealityCheckIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
      size: size,
      color: color,
      strokeWidth: strokeWidth,
      paint: (canvas, size, c, sw) {
        final p = _p(c, sw);
        // Глаз строго по центру (был смещён вправо: 7.2…21.6 при центре 14.4
        // — значок выглядел «уехавшим» из своего бейджа).
        final eye = Path()
          ..moveTo(4.4, 12)
          ..cubicTo(7.0, 8.2, 9.6, 7.0, 12, 7.0)
          ..cubicTo(14.4, 7.0, 17.0, 8.2, 19.6, 12)
          ..cubicTo(17.0, 15.8, 14.4, 17.0, 12, 17.0)
          ..cubicTo(9.6, 17.0, 7.0, 15.8, 4.4, 12)
          ..close();
        _path(canvas, eye, p);
        _circle(canvas, 12, 12, 2.4, p);
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
// Общие действия
// ────────────────────────────────────────────────────────────

class AgAddIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgAddIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgCheckIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgCheckIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgDeleteIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgDeleteIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgEditIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgEditIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgSettingsIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgSettingsIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgBellIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgBellIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgClockIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgClockIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgStarIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgStarIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgHeartIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgHeartIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgMoonIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgMoonIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgSunIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgSunIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgArrowRightIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgArrowRightIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgArrowLeftIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgArrowLeftIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgMenuIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgMenuIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgCloseIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgCloseIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgSearchIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgSearchIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgFilterIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgFilterIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgShareIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgShareIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgDownloadIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgDownloadIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgUploadIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgUploadIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgLockIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgLockIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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

class AgUnlockIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const AgUnlockIcon({
    super.key,
    this.size = kAgIconSize,
    this.color,
    this.strokeWidth = kAgStroke,
  });

  @override
  Widget build(BuildContext context) {
    return AgIcon(
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
