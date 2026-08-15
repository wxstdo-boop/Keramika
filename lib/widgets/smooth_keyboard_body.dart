import 'package:flutter/material.dart';

/// Плавный подъём содержимого при появлении клавиатуры.
///
/// По умолчанию Scaffold сжимает body мгновенно (resizeToAvoidBottomInset)
/// — форма «сползает» одним рывком. Здесь вместо резкого resize оборачиваем
/// body в AnimatedPadding: отступ снизу = высота клавиатуры, и он плавно
/// наезжает (280 мс, easeOutCubic) при появлении/убирании клавиатуры.
///
/// Использование: у Scaffold поставить `resizeToAvoidBottomInset: false`,
/// а body обернуть: `body: SmoothKeyboardBody(child: ...)`.
class SmoothKeyboardBody extends StatelessWidget {
  final Widget child;
  const SmoothKeyboardBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
    );
  }
}
