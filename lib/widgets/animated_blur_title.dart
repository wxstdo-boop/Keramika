import 'package:flutter/material.dart';
import '../services/prefs.dart';
import '../services/profile_service.dart';
import 'online_dot.dart';

/// Заголовок «Keramika» в шапке главного экрана.
///
/// Новогодняя шапка Деда Мороза отсюда убрана: НАД первой буквой живёт
/// маленький красный кружок онлайна с зоной тапа под палец — по нему
/// открывается профиль (см. [OnlineDot]).
///
/// Если в профиле сохранено короткое имя, вместо «Keramika» показывается
/// оно — шапка становится личной.
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
          child: AnimatedBuilder(
            // Имя юзера в шапке: как только профиль сохраняет короткое имя,
            // заголовок сам меняется на него — без пересборки всего Home.
            animation: ProfileService(),
            builder: (context, _) {
              // Своё имя вместо «Keramika»: пустое поле оставляем брендом,
              // чтобы шапка не оставалась пустой у нового пользователя.
              final name = ProfileService().displayName;
              final title = name.isNotEmpty
                  ? Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('K', style: style),
                        Text('eramika', style: style),
                      ],
                    );
              // Кружок онлайна — Positioned-ребёнок Stack, поэтому лэйаут
              // заголовка не меняется: он висит НАД первой буквой и не
              // сдвигает текст (Stack не обрезает, Clip.none). Зона тапа
              // шире глифа, поэтому по кружку удобно попадать пальцем.
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  title,
                  Positioned(
                    // Над первой буквой: кружок «сидит» на верхушке глифа,
                    // а не болтается у базовой линии.
                    left: -6,
                    top: -6,
                    child: OnlineDot(onTap: widget.onOnlineTap ?? () {}),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
