import 'package:flutter/material.dart';

/// Лейбл модели с бейджем PREMIUM у основной модели Ады.
///
/// Имена текущих резервных провайдеров (Kilo, OVHcloud, AI Horde) показываются
/// обычным текстом. У «ada-0.0.3» рядом выводится маленькая золотая плашка
/// PREMIUM — чтобы было видно, что это основная, особенная модель.
class ModelLabel extends StatelessWidget {
  final String label;
  final TextStyle? textStyle;
  final bool isAdaModel;
  final String? details;

  const ModelLabel({
    super.key,
    required this.label,
    this.textStyle,
    this.isAdaModel = false,
    this.details,
  });

  Widget _withDetails(Widget child) => details == null || details!.isEmpty
      ? child
      : Tooltip(message: details!, child: child);

  @override
  Widget build(BuildContext context) {
    // Смена модели/провайдера — ПЛАВНО: старое имя мягко тает, новое
    // подъезжает снизу (280 мс). Раньше текст мгновенно «прыгал», что
    // читалось как дёрганье при переключении провайдеров.
    Widget labelText(String text, {bool ellipsis = false}) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: Text(
          text,
          key: ValueKey(text),
          style: textStyle,
          overflow: ellipsis ? TextOverflow.ellipsis : null,
          maxLines: ellipsis ? 1 : null,
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final showBadge = isAdaModel || label.startsWith('ada-0.0.3');
    if (!showBadge) {
      return _withDetails(labelText(label, ellipsis: true));
    }

    // Золотой градиент — читается и на светлой, и на тёмной теме.
    final gold = const LinearGradient(
      colors: [Color(0xFFF5D374), Color(0xFFE0A52B)],
    );
    // Сине-бирюзовый градиент POOL — Poolside (основной источник Ады).
    final poolGradient = const LinearGradient(
      colors: [Color(0xFF00B8A9), Color(0xFF2E6FDB)],
    );
    return _withDetails(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: labelText(label, ellipsis: true)),
          const SizedBox(width: 5),
          // PREMIUM — золотая плашка, из неё вынесен отдельный значок HF.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              gradient: gold,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFC98F1E).withValues(alpha: 0.35),
                  blurRadius: 5,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              'PREMIUM',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: cs.brightness == Brightness.dark
                    ? const Color(0xFF3A2A00)
                    : const Color(0xFF432F00),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Отдельная плашка POOL — Poolside.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              gradient: poolGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'POOL',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
