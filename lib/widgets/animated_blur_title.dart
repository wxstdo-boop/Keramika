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
    // Ёлочка + «Keramika» в одном squircle-плашке. Наклон даёт лёгкий
    // курсив, обводка совпадает с цветом выбранной темы — «живая» и и
    // адаптируется вместо того, чтобы «залипать» стандартным курсивом.
    final cs = Theme.of(context).colorScheme;
    // Обводка — ТОЛЬКО вокруг ёлочки, не вокруг всего заголовка, как просил.
    // Сам «Keramika» остаётся наклонным, жирным, без рамки.
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.70),
                  width: 1.2,
                ),
              ),
              child: const Text('🎄', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Keramika',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    letterSpacing: -0.8,
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
