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

  Widget _withDetails(Widget child) =>
      details == null || details!.isEmpty
          ? child
          : Tooltip(message: details!, child: child);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBadge = isAdaModel || label.startsWith('ada-0.0.3');
    if (!showBadge) {
      return _withDetails(Text(label, style: textStyle));
    }

    // Золотой градиент — читается и на светлой, и на тёмной теме.
    final gold = const LinearGradient(
      colors: [Color(0xFFF5D374), Color(0xFFE0A52B)],
    );
    // Сине-бирюзовый градиент POOL — Poolside (основной источник Ады).
    final poolGradient = const LinearGradient(
      colors: [Color(0xFF00B8A9), Color(0xFF2E6FDB)],
    );
    return _withDetails(Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label, style: textStyle, overflow: TextOverflow.ellipsis),
        ),
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
    ));
  }
}
