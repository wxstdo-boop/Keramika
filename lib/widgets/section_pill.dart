import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/reality_check_service.dart';
import 'smooth_tooltip.dart';

// ── Общий стейт таблетки разделов ──────────────────────────────────────
// Таблетка живёт в Home НАД PageView (обычный поток, не поверх контента):
// при переключении разделов она остаётся на месте, а листается только
// содержимое под ней. Её состояние вынесено в общие notifier-ы: Home пишет
// сюда из PageView (текущая страница и её позиция), а тап по разделу Home
// слушает через [sectionTabTap].

/// Текущий выбранный раздел (индекс страницы PageView).
final ValueNotifier<int> sectionCurrentIndex = ValueNotifier<int>(0);

/// Непрерывная позиция страницы — индикатор таблетки следует за ней
/// плавно, без скачков при переходах через 1–2 раздела.
final ValueNotifier<double> sectionRailPage = ValueNotifier<double>(0);

/// Тик тапа по разделу: Home слушает и доезжает до нужной страницы.
final ValueNotifier<int> sectionTabTap = ValueNotifier<int>(0);

/// Значки разделов: у каждого своя геометрическая фигура.
const List<IconData> sectionIcons = [
  Icons.alarm_outlined,
  Icons.auto_awesome_outlined,
  Icons.checklist_outlined,
  Icons.psychology_outlined,
];

/// Названия разделов (для тултипов) — те же, что строит Home: РП-раздел
/// виден только когда проверки реальности включены в настройках.
List<String> sectionLabels(BuildContext context) {
  final rcOn = RealityCheckService().enabled;
  return [
    Translations.alarmsOf(context),
    Translations.habitsOf(context),
    Translations.tasksOf(context),
    if (rcOn) Translations.rcOf(context),
  ];
}

/// Значки разделов с учётом настроек: при выключенных проверках реальности
/// РП-раздел (и его значок) не должен быть виден вообще.
List<IconData> sectionIconsFor(BuildContext context) {
  final count = sectionLabels(context).length;
  return sectionIcons.sublist(0, count);
}

/// Единая объемная капсула разделов. Названия доступны только в тултипах
/// (показываются НАД таблеткой — иначе прячутся за пальцем), визуально —
/// только иконки в гео-фигурах.
class SectionPill extends StatefulWidget {
  const SectionPill({super.key});

  @override
  State<SectionPill> createState() => _SectionPillState();
}

class _SectionPillState extends State<SectionPill> {
  int? _pressedIndex;

  @override
  Widget build(BuildContext context) {
    final labels = sectionLabels(context);
    final icons = sectionIconsFor(context);
    final count = icons.length;
    if (count == 0) return const SizedBox.shrink();

    return ValueListenableBuilder<int>(
      valueListenable: sectionCurrentIndex,
      builder: (context, current, _) => ValueListenableBuilder<double>(
        valueListenable: sectionRailPage,
        builder: (context, page, __) {
          final cs = Theme.of(context).colorScheme;
          final rawPage = page.isFinite ? page : current.toDouble();
          final p = rawPage.clamp(0.0, (count - 1).toDouble());
          final selectedIndex = p.round().clamp(0, count - 1);
          final indicatorAlignment = count == 1
              ? 0.0
              : -1.0 + (2.0 * p / (count - 1));

          return Padding(
            // Таблетка в Home чуть выше (под AppBar), компактный отступ.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),            child: Center(
              child: SizedBox(
              width: 304,
              height: 54,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                // BackdropFilter убран: внутри скролл-контента страниц
                // PageView размытие не находит валидный фон и заливает
                // весь экран серым. «Морозное стекло» — полупрозрачным
                // градиентом, без blur.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          cs.surfaceContainerHighest.withValues(alpha: 0.85),
                          cs.surfaceContainerLow.withValues(alpha: 0.93),
                        ],
                      ),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.55),
                          width: 1.3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 12,
                            spreadRadius: -3,
                            offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.07),
                            blurRadius: 8,
                            spreadRadius: -4,
                            offset: const Offset(0, -1),
                          ),
                        ],
                      ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            fit: StackFit.expand,
                            children: [
                              // Позиция индикатора берётся прямо из page —
                              // непрерывно, без AnimatedAlign-скачков.
                              Align(
                                alignment: Alignment(indicatorAlignment, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 1 / count,
                                  heightFactor: 1,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(21.5),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          cs.primary,
                                          Color.lerp(
                                            cs.primary,
                                            cs.tertiary,
                                            0.42,
                                          )!,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: cs.primary.withValues(
                                            alpha: 0.34,
                                          ),
                                          blurRadius: 6,
                                          spreadRadius: -2,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Row(
                                children: List.generate(count, (i) {
                                  final label = i < labels.length
                                      ? labels[i]
                                      : '';
                                  final proximity = (1.0 - (p - i).abs()).clamp(
                                    0.0,
                                    1.0,
                                  );
                                  final iconColor = Color.lerp(
                                    cs.onSurfaceVariant,
                                    cs.onPrimary,
                                    proximity,
                                  );
                                  final isPressed = _pressedIndex == i;
                                  final isSelected = selectedIndex == i;
                                  final badgeT = proximity;
                                  final restingScale = isSelected ? 1.05 : 1.0;
                                  final pressedScale = isSelected ? 0.96 : 0.90;
                                  return Expanded(
                                    // Подсказка — НАД таблеткой (preferredAbove):
                                    // иначе пузырь ложится на саму таблетку и
                                    // прячется за пальцем.
                                    child: SmoothTooltip(
                                      message: label,
                                      waitDuration: const Duration(
                                        milliseconds: 350,
                                      ),
                                      preferredAbove: true,
                                      child: Semantics(
                                        button: true,
                                        selected: isSelected,
                                        label: label,
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              21.5,
                                            ),
                                            splashColor: Colors.transparent,
                                            highlightColor: Colors.transparent,
                                            // Переключение — СРАЗУ при
                                            // нажатии (не при отпускании):
                                            // даже если палец задержался на
                                            // кнопке, раздел уже переключился,
                                            // никакого «замедления».
                                            onTapDown: (_) {
                                              setState(
                                                () => _pressedIndex = i,
                                              );
                                              Haptics.select();
                                              sectionCurrentIndex.value = i;
                                              sectionTabTap.value++;
                                            },
                                            onTapCancel: () {
                                              if (mounted) {
                                                setState(
                                                  () => _pressedIndex = null,
                                                );
                                              }
                                            },
                                            onTap: () {
                                              if (mounted) {
                                                setState(
                                                  () => _pressedIndex = null,
                                                );
                                              }
                                            },
                                            child: Center(
                                              child: AnimatedScale(
                                                scale: isPressed
                                                    ? pressedScale
                                                    : restingScale,
                                                duration: const Duration(
                                                  milliseconds: 160,
                                                ),
                                                curve: Curves.easeOutCubic,
                                              child: _GeoBadge(
                                                index: i,
                                                size: 31,
                                                // Невыбранная — заметный
                                                // фирменный оттенок (чтобы
                                                // фигуры читались), выбранная —
                                                // сочный градиентный «камень».
                                                color: Color.lerp(
                                                  cs.primary.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                  cs.primary,
                                                  badgeT,
                                                )!,
                                                child: Icon(
                                                  icons[i],
                                                  size: 17,
                                                  color: iconColor,
                                                ),
                                              ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Значок раздела: иконка сидит внутри своей «драгоценной» фигуры
/// (круг, скруглённый квадрат, ромб, гексагон). У каждого раздела свой
/// контур; градиент + блик + гранёный ободок — фигура читается объёмной.
class _GeoBadge extends StatelessWidget {
  final int index;
  final double size;
  final Color color;
  final Widget child;

  const _GeoBadge({
    required this.index,
    required this.size,
    required this.color,
    required this.child,
  });

  /// Коэффициент иконки внутри фигуры: у «колючих» фигур (ромб, звезда)
  /// иконка меньше, чтобы не вылезать за острые края.
  double get _iconScale => switch (index) {
        2 => 0.5,
        3 => 0.44,
        _ => 0.56,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShapePainter(index, color),
        child: Center(
          child: SizedBox(
            width: size * _iconScale,
            height: size * _iconScale,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final int index;
  final Color color;

  const _ShapePainter(this.index, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.0;
    // «Драгоценный» градиент: свет сверху-слева, глубина снизу-справа.
    final light = Color.lerp(color, Colors.white, 0.42)!;
    final deep = Color.lerp(color, Colors.black, 0.18)!;
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light, color, deep],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(Offset.zero & size);

    // Фигура: 🔵 круг, ⬜ скруглённый квадрат, 💠 вытянутый ромб,
    // ✦ пятиконечная звезда («искра» проверок реальности).
    final Path shape;
    if (index == 0) {
      shape = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    } else if (index == 1) {
      shape = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: center, radius: r),
            Radius.circular(r * 0.38),
          ),
        );
    } else if (index == 2) {
      // 💠 Ромб — широкий (0.96r), чтобы значок свободно помещался;
      // острые верх/низ по-прежнему читаются как гранёный камень.
      final pts = [
        Offset(center.dx, center.dy - r),
        Offset(center.dx + r * 0.96, center.dy),
        Offset(center.dx, center.dy + r),
        Offset(center.dx - r * 0.96, center.dy),
      ];
      shape = _roundedPolygon(pts, r * 0.08);
    } else {
      // Пятиконечная звезда: острые лучи, без скруглений.
      shape = _star(center, r);
    }

    canvas.drawPath(shape, Paint()..shader = shader);

    // Гранёный ободок: тонкая светлая кромка по контуру фигуры.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.38),
    );

    // Глянцевый блик: мягкое светлое пятно в верхней части фигуры.
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawCircle(
      Offset(center.dx - r * 0.30, center.dy - r * 0.34),
      r * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(center.dx - r * 0.30, center.dy - r * 0.34),
            radius: r * 0.7,
          ),
        ),
    );
    canvas.restore();
  }

  /// Пятиконечная звезда с центром [center] и внешним радиусом [r].
  Path _star(Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final ang = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? r : r * 0.46;
      final pt = Offset(
        center.dx + rad * math.cos(ang),
        center.dy + rad * math.sin(ang),
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  /// Скруглённый многоугольник по точкам (radius — радиус скругления углов).
  Path _roundedPolygon(List<Offset> points, double radius) {
    final path = Path();
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final p = points[i];
      final prev = points[(i - 1 + n) % n];
      final next = points[(i + 1) % n];
      final u1 = (p - prev);
      final u2 = (next - p);
      final rad = radius.clamp(0.0, math.min(u1.distance, u2.distance) / 2);
      final a = p - u1 / u1.distance * rad;
      final b = p + u2 / u2.distance * rad;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(p.dx, p.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.color != color;
}
