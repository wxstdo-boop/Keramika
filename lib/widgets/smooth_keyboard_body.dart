import 'package:flutter/material.dart';

/// Плавный подъём содержимого при появлении клавиатуры.
///
/// По умолчанию Scaffold сжимает body мгновенно (resizeToAvoidBottomInset)
/// — форма «сползает» одним рывком. Здесь вместо резкого resize оборачиваем
/// body в Padding с отступом = высота клавиатуры.
///
/// ВАЖНО: НЕ используем AnimatedPadding. На Android 11+ `viewInsets.bottom`
/// приходит от системы ПОКАДРОВО во время анимации клавиатуры — обычный
/// Padding двигает содержимое ровно вместе с ней. AnimatedPadding добавлял
/// свою 280 мс задержку: при закрытии клавиатуры она уже уехала, а контент
/// ещё стоял — и под ней открывалась белая полоса фона.
///
/// Использование: у Scaffold поставить `resizeToAvoidBottomInset: false`,
/// а body обернуть: `body: SmoothKeyboardBody(child: ...)`.
class SmoothKeyboardBody extends StatelessWidget {
  final Widget child;
  const SmoothKeyboardBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: child,
      ),
    );
  }
}
