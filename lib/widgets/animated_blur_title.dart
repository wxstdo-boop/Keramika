import 'package:flutter/material.dart';
import '../services/prefs.dart';

class AnimatedBlurTitle extends StatefulWidget {
  const AnimatedBlurTitle({super.key});

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
    // «Keramika» без ёлочки. Новогодняя шапочка — НАСТОЯЩИЙ эмодзи 🎅,
    // обрезанный до самой шапки (красный конус + белая оторочка), а не
    // рисованная картинка. Сидит точно на букве «r»: заголовок собран из
    // трёх частей (Ke + r + amika) в Row, шапочка кладётся в Stack вместе
    // с «r» и перекрывает её верх.
    final style = const TextStyle(
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ke', style: style),
              // Буква «r» с шапочкой поверх неё (перекрывает верх буквы —
              // ничего не вылезает за AppBar, ничего не обрезается).
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('r', style: style),
                  Positioned(
                    top: -3,
                    left: -1,
                    // Эмодзи Санты, обрезанный до шапки: FittedBox cover +
                    // topCenter показывает только верхнюю часть глифа
                    // (красный конус с белой оторочкой), лицо скрыто.
                    child: SizedBox(
                      width: 27,
                      height: 11,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.hardEdge,
                        // Шапочка — настоящий цветной эмодзи 🎅 (как просил
                        // вернуть), обрезанный до самой шапки.
                        child: const Text(
                          '🎅',
                          style: TextStyle(fontSize: 27, height: 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Text('amika', style: style),
            ],
          ),
        ),
      ),
    );
  }
}
