import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/prefs.dart';
import '../services/profile_service.dart';
import 'online_dot.dart';

/// Заголовок шапки главного экрана: «Keramika» или короткое имя юзера.
///
/// Кружок онлайна «растёт» из нижнего правого угла последней буквы заголовка,
/// от буквы к нему идёт тонкий хвостик (см. [_TitleWithDot]) — по кружку
/// открывается профиль ([OnlineDot]). Новогодняя шапка Деда Мороза отсюда
/// убрана.
///
/// Имя в профиле можно сменить на лету: заголовок меняется плавно
/// (AnimatedSwitcher — кросс-фейд с лёгким масштабом), а не подменяется кадром.
///
/// Сам заголовок остался «затемняемым»: тап по нему плавно приглушает буквы
/// (это прежнее поведение, к которому пользователь привык).
class AnimatedBlurTitle extends StatefulWidget {
  /// Тап по кружку онлайна — открыть профиль.
  final VoidCallback? onOnlineTap;

  const AnimatedBlurTitle({super.key, this.onOnlineTap});

  @override
  State<AnimatedBlurTitle> createState() => _AnimatedBlurTitleState();
}

class _AnimatedBlurTitleState extends State<AnimatedBlurTitle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _hidden = globalPrefs.getBool('title_blurred') ?? false;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
      value: _hidden ? 0.0 : 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _hidden = !_hidden);
    globalPrefs.setBool('title_blurred', _hidden);
    if (_hidden) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 27,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.8,
    );
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedBuilder(
            // Имя юзера в шапке: как только профиль сохраняет короткое имя,
            // заголовок сам меняется на него — без пересборки всего Home.
            animation: ProfileService(),
            builder: (context, _) {
              // Своё имя вместо «Keramika»: пустое поле оставляем брендом,
              // чтобы шапка не оставалась пустой у нового пользователя.
              final name = ProfileService().displayName;
              final title = name.isNotEmpty ? name : 'Keramika';
              // Смена имени — плавная: кросс-фейд со лёгким «проявлением»,
              // а не мгновенная подмена текста. Заметно медленнее обычного —
              // читается как мягкое перетекание.
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 520),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(anim),
                    child: child,
                  ),
                ),
                child: _TitleWithDot(
                  key: ValueKey(title),
                  text: title,
                  style: style,
                  onDotTap: widget.onOnlineTap ?? () {},
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Заголовок с кружком онлайна ВНИЗУ, справа от последней буквы.
///
/// Позиция кружка считается по реальной геометрии текста ([TextPainter]):
/// берём рамку последнего глифа и вешаем кружок к её нижнему правому углу —
/// он «растёт» из хвостика буквы, как ягодка на черешке, и не «плавает» при
/// смене имени или масштаба шрифта. От буквы к кружку идёт тонкий хвостик
/// ([_DotTailPainter]) — кружок читается продолжением росчерка, а не
/// отдельной точкой рядом.
class _TitleWithDot extends StatelessWidget {
  final String text;
  final TextStyle style;
  final VoidCallback onDotTap;

  const _TitleWithDot({
    super.key,
    required this.text,
    required this.style,
    required this.onDotTap,
  });

  /// Зазор между правым краем последней буквы и ЛЕВЫМ краем кружка, px.
  /// Кружок стоит справа с воздухом — на букву не налезает. Считается от
  /// диаметра кружка: он растёт, а зазор должен оставаться прежним.
  static const double _gapLeft = 3.0;

  /// Смещение центра кружка от СЕРЕДИНЫ высоты последней буквы, px.
  /// Отрицательное — приподнимает кружок над серединой («ещё над»).
  static const double _dropY = -2.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    Rect? lastGlyph;
    if (text.isNotEmpty) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: text.length - 1, extentOffset: text.length),
      );
      if (boxes.isNotEmpty) lastGlyph = boxes.last.toRect();
    }
    // Центр кружка: СПРАВА от последней буквы, у СЕРЕДИНЫ её высоты (чуть
    // выше середины — «ещё над»). Зона тапа OnlineDot — квадрат 30×30.
    final tapHalf = OnlineDot.tapTarget / 2;
    // Левый край кружка ставим в фиксированный зазор от буквы: диаметр кружка
    // может меняться, а воздух до буквы должен оставаться тем же.
    final dotRadius = OnlineDot.dotSize / 2;
    final dotCx =
        (lastGlyph?.right ?? painter.width) + _gapLeft + dotRadius;
    final dotCy = ((lastGlyph?.top ?? 0) + (lastGlyph?.bottom ?? painter.height)) / 2 + _dropY;

    // Stack хит-тестит только ВНУТРИ своих границ: кружок, вынесенный за
    // границы, было бы не нажать. Поэтому раздуваем рамку на недостающие поля,
    // а текст внутри сдвигаем на ту же величину — вертикальный центр текста не
    // меняется, шапка не «съезжает».
    final padTop = math.max(0.0, tapHalf - dotCy);
    final padBottom = math.max(0.0, dotCy + tapHalf - painter.height);
    final padRight = math.max(0.0, dotCx + tapHalf - painter.width);
    // Короткий росчерк от середины буквы к кружку — кружок читается
    // продолжением имени, а не отдельной точкой.
    final tailFrom = Offset(
      lastGlyph?.right ?? painter.width,
      ((lastGlyph?.top ?? 0) + (lastGlyph?.bottom ?? painter.height)) / 2 - 1,
    );
    final tailTo = Offset(dotCx - 2.6, dotCy - 1.4);
    return SizedBox(
      width: painter.width + padRight,
      height: painter.height + padTop + padBottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: padTop,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (lastGlyph != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DotTailPainter(
                    from: tailFrom.translate(0, padTop),
                    to: tailTo.translate(0, padTop),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          if (lastGlyph != null)
            Positioned(
              left: dotCx - tapHalf,
              top: dotCy - tapHalf + padTop,
              child: OnlineDot(onTap: onDotTap),
            ),
        ],
      ),
    );
  }
}

/// Тонкий «хвостик» от буквы заголовка к кружку онлайна: короткая дуга с
/// лёгким изгибом вниз — росчерк, из которого «вырастает» кружок.
///
/// Цвет берётся из темы с малой альфой: на светлой теме хвостик тёмный и
/// деликатный, на тёмной — светлый; он не спорит с глифом, а только ведёт
/// взгляд от буквы к статусу.
class _DotTailPainter extends CustomPainter {
  const _DotTailPainter({
    required this.from,
    required this.to,
    required this.color,
  });

  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Контрольная точка «под» хвостиком: линия получается выпуклой вниз, как
    // росчерк пера, а не прямой штрих.
    final mid = Offset(
      (from.dx + to.dx) / 2 + 1.6,
      (from.dy + to.dy) / 2 + 3.2,
    );
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _DotTailPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.color != color;
}
