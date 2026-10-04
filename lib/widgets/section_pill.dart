import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/reality_check_service.dart';
import 'smooth_tooltip.dart';
import 'stained_glass.dart';

/// Занимаемая таблеткой высота (отступы 4 + капсула 54 + отступ 6).
/// Таблетка лежит в Stack НАД PageView, поэтому каждый экран-раздел
/// резервирует столько же сверху своего скролла: тогда в покое список
/// начинается под таблеткой, а при прокрутке уходит ПОД стекло.
const double kSectionPillSlotHeight = 64;

/// edgeOffset для RefreshIndicator разделов: кружок (40 px) в покое стоит
/// нижним краем вытягивания под капсулой, а при потягивании ВЫЕЗЖАЕТ ИЗ-ПОД
/// таблетки, а не появляется за ней.
///
/// Позиция круга в Material: низ = edgeOffset + sizeFactor*(displacement+40).
/// При sizeFactor=1 верх круга = edgeOffset + displacement (40) — поэтому
/// edgeOffset = 58 (низ капсулы) - 40 = 18.
const double kSectionRefreshEdgeOffset = kSectionPillSlotHeight - 6 - 40;

/// Верхний «запретный пояс» для плавающего окошка Ады: статус-бар + шапка +
/// таблетка разделов.
///
/// Окошко Ады — always-on-top поверхность (на Android системный оверлей, на
/// web слой поверх всех экранов), поэтому оно затирает таблетку и её
/// «Полезные/Вредные»: при перетаскивании вверх Ада «залезала» на категории.
/// Пояс считает её НУЛЕВОЙ верхней границей — выше окошко не пускаем ни
/// драгом, ни дрейфом.
double adaTopKeepout(double statusBarHeight) =>
    statusBarHeight + kToolbarHeight + kSectionPillSlotHeight;

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
          final dark = Theme.of(context).brightness == Brightness.dark;
          final rawPage = page.isFinite ? page : current.toDouble();
          final p = rawPage.clamp(0.0, (count - 1).toDouble());
          final selectedIndex = p.round().clamp(0, count - 1);
          final indicatorAlignment = count == 1
              ? 0.0
              : -1.0 + (2.0 * p / (count - 1));

          // «Змейка»: в полёте индикатор вытягивается (капля растёт до 1.4) и по
          // нему бежит световой блик — переливание/«волна». Парабола
          // (не sin) — без рывка на границах, плавно следует за [p].
          final transit = (p - p.roundToDouble())
              .abs(); // 0 в покое, 0.5 в полёте
          final t2 = transit * 2.0; // 0..1 (0 в покое, 1 в полёте)
          final wave = 1.0 - (1.0 - t2) * (1.0 - t2); // парабола 0 → 1 плавно
          final capStretch = 1.0 + 0.40 * wave; // растягивается до 1.4
          final capRadius = 21.5 + 12.0 * wave; // мягко закругляются концы
          // Фаза блика: бегает по индикатору вместе с [p] (-1..1).

          return Padding(
            // Таблетка в Home чуть выше (под AppBar), компактный отступ.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Center(
              child: SizedBox(
                width: 304,
                height: 54,
                child: _GlassCapsule(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        fit: StackFit.expand,
                        children: [
                          // Позиция индикатора берётся прямо из page —
                          // непрерывно, без AnimatedAlign-скачков. Внутри
                          // — «капля»: при перелёте сжимается + по ней
                          // бежит световой блик (переливание).
                          Align(
                            alignment: Alignment(indicatorAlignment, 0),
                            child: FractionallySizedBox(
                              widthFactor: capStretch / count,
                              heightFactor: 1,
                              child: _GlassStone(
                                capRadius: capRadius,
                                primary: cs.primary,
                                deep: Color.lerp(
                                  cs.primary,
                                  cs.tertiary,
                                  0.42,
                                )!,
                                dark: dark,
                              ),
                            ),
                          ),
                          Row(
                            children: List.generate(count, (i) {
                              final label = i < labels.length ? labels[i] : '';
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
                                        // Переключение — ТОЛЬКО при ОТПУСКАНИИ пальца (onTap).
                                        // Касание/свайп по таблетке не меняет активный раздел «на лету».
                                        onTapDown: (_) {
                                          setState(() => _pressedIndex = i);
                                        },
                                        onTapCancel: () {
                                          if (mounted) {
                                            setState(
                                              () => _pressedIndex = null,
                                            );
                                          }
                                        },
                                        onTap: () {
                                          if (!mounted) return;
                                          setState(() => _pressedIndex = null);
                                          Haptics.select();
                                          sectionCurrentIndex.value = i;
                                          sectionTabTap.value++;
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
          );
        },
      ),
    );
  }
}

/// Настоящее стекло капсулы разделов: реальный [BackdropFilter] (размывает
/// прокручиваемый контент, который уходит под таблетку) + дымная полупрозрачная
/// подложка с фирменным оттенком + зеркальный блик, светкая кромка и тень
/// ПОД клипом (внутри скругления тень обрезалась и стекло выглядело плоским).
///
/// Под таблеткой в покое лежит однотонный фон страницы, поэтому «преломления»
/// там нет и стекло продают именно оттенок подложки, блик, кромка и тень; при
/// прокрутке добавляется размытый контент, а поверх подложки лежат пятна
/// фирменного цвета темы — стекло выглядит окрашенным, а не плоским.
class _GlassCapsule extends StatelessWidget {
  final Widget child;

  /// Фильтр — `static const`: подложка перерисовывается каждый кадр прокрутки
  /// (контент под капсулой двигается, бэкдроп сбрасывается), и каждый раз
  /// создавать нативный ImageFilter значимо дороже, чем переиспользовать
  /// закэшированный объект того же blur.
  ///
  /// sigma 12 вместо 20: на Adreno 610 размытие упирается в fill-rate, а
  /// визуально 12 и 20 под полупрозрачной подложкой неотличимы — контент
  /// всё равно читается как матовое стекло.
  static final ImageFilter _blur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  const _GlassCapsule({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Убрали BackdropFilter и размытие — таблетка теперь выглядит как плотная
    // глина/пластик, а не стекло. Без блюра контент под ней виден чётко.
    final base = dark ? cs.surfaceContainerHigh : cs.surfaceContainerHighest;
    // Светлая глиняная основа с лёгким фирменным оттенком — матовая, без
    // стеклянного свечения изнутри. Глубину делаем минимальной для «сухого»
    // пластика вместо влажного стекла.
    final tint = Color.lerp(base, cs.primary, dark ? 0.12 : 0.10)!;
    return DecoratedBox(
      // Тень ВНЕ ClipRRect: внутри клипа она обрезалась на границе
      // скругления и капсула повисала без объёма.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.18 : 0.12),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        // MATTOVAYA PLOTKAYA GLINA: одноцветная твёрдая поверхность,
        // никакой прозрачности и подложек под ней нет — пластик сплошной.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            // Матовый градиент для лёгкого объёма сверху-вниз — без стеклянных
            // бликов и прозрачных переходов. Цвет плотный, непрозрачный.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: 0.92),
                tint.withValues(alpha: 0.88),
              ],
            ),
          ),
          child: CustomPaint(
            painter: StainedGlassPainter(
              color: cs.primary,
              alpha: dark ? 0.08 : 0.06,
              diffuse: 1,
              kiss: true,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Выбранный раздел — стеклянный «камень»: полупрозрачный, плотнее к центру
/// (там лежит иконка — нужен контраст) и всё более прозрачный к краям, через
/// которые читается матовое стекло капсулы. Сверху зеркальный блик, снизу
/// рефракция, по контуру светкая кромка, под камнем — тень на капсуле.
class _GlassStone extends StatelessWidget {
  final double capRadius;
  final Color primary;
  final Color deep;
  final bool dark;

  const _GlassStone({
    required this.capRadius,
    required this.primary,
    required this.deep,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Тень вне ClipRRect — иначе она обрезалась и камень не «отрывался»
      // от стекла.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(capRadius),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : primary).withValues(
              alpha: dark ? 0.45 : 0.32,
            ),
            blurRadius: 5,
            spreadRadius: -2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(capRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    primary.withValues(alpha: 0.74),
                    deep.withValues(alpha: 0.62),
                    deep.withValues(alpha: 0.42),
                  ],
                  stops: const [0.0, 0.62, 1.0],
                ),
              ),
            ),
            // Пятна-капли НА фоне самого камня (та же «витражная» техника,
            // что на стекле капсулы — общий StainedGlassPainter). Пигмент
            // белый, а не primary: фон камня и так залит цветом темы, и
            // цветное пятно на цветном стекле просто не читалось бы. Клип
            // выше по дереву, поэтому пятно не вылезает за контур камня.
            //
            // Паттерн квантован по размеру (см. stained_glass.dart), поэтому
            // растяжение камня в полёте не перестраивает геометрию каждый
            // кадр.
            CustomPaint(
              painter: StainedGlassPainter(
                color: Colors.white,
                alpha: dark ? 0.22 : 0.30,
                diffuse: 1,
                specks: 12,
              ),
            ),
            // Рефракция по нижнему краю — стекло утолщается и темнеет.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x22000000)],
                  stops: [0.58, 1.0],
                ),
              ),
            ),
            // Зеркальный блик.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.24 : 0.36),
                    Colors.white.withValues(alpha: dark ? 0.06 : 0.10),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.42, 0.74],
                ),
              ),
            ),
            // Светкая кромка по контуру камня.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(capRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: dark ? 0.26 : 0.42),
                    width: 1,
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

  /// Контуры значков зависят только от фигуры и размера — при перелистывании
  /// разделов цвет меняется каждый кадр, а геометрия нет. Звезда и
  /// скруглённый многоугольник считаются тригонометрией, поэтому держим их
  /// в маленьком кэше (размеров у таблетки ровно несколько).
  static final Map<String, Path> _shapes = {};

  static Path _shapeFor(int index, Size size) {
    final key = '$index:${size.width}x${size.height}';
    final cached = _shapes[key];
    if (cached != null) return cached;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.0;
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
    if (_shapes.length > 24) _shapes.clear();
    _shapes[key] = shape;
    return shape;
  }

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
    final shape = _shapeFor(index, size);

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
        ..shader =
            RadialGradient(
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
  static Path _star(Offset center, double r) {
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
  static Path _roundedPolygon(List<Offset> points, double radius) {
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
