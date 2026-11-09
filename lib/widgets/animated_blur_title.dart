import 'package:flutter/material.dart';
import '../services/prefs.dart';
import 'online_dot.dart';

/// Заголовок «Keramika» в шапке главного экрана.
///
/// Новогодняя шапка Деда Мороза отсюда убрана: под буквой «K» теперь живёт
/// маленький красный кружок онлайна с зоной тапа под палец — по нему
/// открывается профиль (см. [OnlineDot]).
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
              // Буква «K» с кружком онлайна под ней. Кружок — Positioned-
              // ребёнок Stack, поэтому лэйаут заголовка не меняется: буква
              // остаётся единственным не-Positioned элементом и никуда не
              // сдвигается, а кружок висит под глифом.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('K', style: style),
                  Positioned(
                    // Под буквой, чуть ниже базовой линии: кружок «прижат» к
                    // низу «K», а не висит посреди слова.
                    left: -8,
                    bottom: -6,
                    child: OnlineDot(onTap: widget.onOnlineTap ?? () {}),
                  ),
                ],
              ),
              Text('eramika', style: style),
            ],
          ),
        ),
      ),
    );
  }
}
