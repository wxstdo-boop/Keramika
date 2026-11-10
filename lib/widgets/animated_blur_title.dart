import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/prefs.dart';
import '../services/profile_service.dart';
import 'online_dot.dart';

/// Заголовок шапки главного экрана: «Keramika» или короткое имя юзера.
///
/// Кружок онлайна сидит НАД последней буквой заголовка, справа сверху, и не
/// касается глифа (см. [_TitleWithDot]) — по нему открывается профиль
/// ([OnlineDot]). Новогодняя шапка Деда Мороза отсюда убрана.
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
              // а не мгновенная подмена текста.
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
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

/// Заголовок с кружком онлайна НАД последней буквой, справа сверху.
///
/// Позиция кружка считается по реальной геометрии текста ([TextPainter]):
/// берём рамку последнего глифа и вешаем кружок чуть выше и правее её — так
/// он не касается буквы и не «плавает» при смене имени или масштаба шрифта.
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

  /// Смещение кружка вниз от верха строки, px. Отрицательное значение
  /// ОПУСКАЕТ кружок к букве: ящик строки заметно выше чернил «a», и при
  /// нулевом зазоре кружок висел слишком высоко над глифом.
  static const double _gap = -2.5;

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
    // Видимый центр кружка: чуть правее конца последнего глифа и НАД его
    // верхом. Зона тапа OnlineDot — квадрат 30×30 с глифом по центру.
    final dotRadius = OnlineDot.dotSize / 2;
    final tapHalf = OnlineDot.tapTarget / 2;
    final dotCx = (lastGlyph?.right ?? painter.width) - dotRadius + 5;
    final dotCy = (lastGlyph?.top ?? 0) - dotRadius - _gap;

    // Stack хит-тестит только ВНУТРИ своих границ: кружок, вынесенный за верх
    // отрицательным `top`, было бы не нажать. Поэтому раздуваем рамку на
    // недостающие поля, а текст внутри сдвигаем на ту же величину. Сверху и
    // снизу отступ ОДИНАКОВЫЙ — вертикальный центр текста не меняется, шапка
    // не «съезжает» вниз.
    final padTop = math.max(0.0, tapHalf - dotCy);
    final padRight = math.max(0.0, dotCx + tapHalf - painter.width);
    return SizedBox(
      width: painter.width + padRight,
      height: painter.height + padTop * 2,
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
