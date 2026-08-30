import 'dart:async';

import 'package:flutter/material.dart';

/// Всплывающая подсказка с ПЛАВНЫМ появлением и исчезанием (фейд + лёгкий
/// scale), в отличие от дефолтной `Tooltip`, которая у нас дёргается.
/// Триггер — долгое нажатие/зажатие, как и у системного тултипа.
class SmoothTooltip extends StatefulWidget {
  final String message;
  final Duration? waitDuration;
  final Duration showDuration;
  final Widget child;

  const SmoothTooltip({
    super.key,
    required this.message,
    this.waitDuration,
    this.showDuration = const Duration(seconds: 5),
    required this.child,
  });

  @override
  State<SmoothTooltip> createState() => _SmoothTooltipState();
}

class _SmoothTooltipState extends State<SmoothTooltip>
    with SingleTickerProviderStateMixin {
  final GlobalKey _anchorKey = GlobalKey();
  Timer? _showTimer;
  Timer? _dismissTimer;
  OverlayEntry? _entry;
  bool _locked = false;
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curved;
    _scale = Tween<double>(begin: 0.97, end: 1.0).animate(curved);
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    _dismount();
    _controller.dispose();
    super.dispose();
  }

  void _onHoldStart() {
    if (widget.message.isEmpty) return;
    _showTimer?.cancel();
    _showTimer = Timer(
      widget.waitDuration ?? const Duration(milliseconds: 220),
      _show,
    );
  }

  void _onHoldEnd() {
    _showTimer?.cancel();
    // Если таймер успел показать подсказку, оставляем её до конца показа.
  }

  /// Плавно показываем подсказку у зажатой кнопки.
  void _show() {
    if (!mounted || _locked) return;
    _dismissTimer?.cancel();
    final anchorContext = _anchorKey.currentContext;
    final box = anchorContext?.findRenderObject();
    if (anchorContext == null || box is! RenderBox) return;
    final overlay = Overlay.of(context);
    _locked = true;
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    // Сначала пробуем показать СВЕРХУ, если не хватает места — снизу.
    final bubbleWidth = _estimateWidth();
    final left = (pos.dx + box.size.width / 2 - bubbleWidth / 2)
        .clamp(4.0, overlayBox.size.width - bubbleWidth - 4);
    final above = pos.dy - 8;
    final below = pos.dy + box.size.height + 8;
    final useAbove = above >= 6.0;
    _entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: (useAbove ? above : below).clamp(4.0, overlayBox.size.height - 44),
          left: left,
          child: IgnorePointer(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                alignment: useAbove ? Alignment.bottomCenter : Alignment.topCenter,
                child: _Bubble(message: widget.message, above: useAbove),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    _controller.forward();
    // Не исчезать сразу после отпускания: тултип остаётся читаемым 5 секунд.
    _dismissTimer = Timer(widget.showDuration, _hide);
  }

  void _hide() {
    if (!_locked) return;
    if (!_controller.isAnimating && _controller.value == 0) {
      _dismount();
      return;
    }
    _controller.reverse().then((_) {
      if (mounted) _dismount();
    });
  }

  void _dismount() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _locked = false;
    _entry?.remove();
    _entry = null;
    _controller.value = 0;
  }

  double _estimateWidth() {
    // Грубая оценка ширины пузыря до его построения — втягиваем иконку/слово.
    const charW = 7.2;
    final textLength = widget.message.length;
    return (textLength * charW + 28).clamp(56.0, 240.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _anchorKey,
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressMoveUpdate: (_) => _onHoldEnd(),
      child: widget.child,
    );
  }
}

class _Bubble extends StatelessWidget {
  final String message;

  /// true — пузырь над кнопкой (стрелка снизу, указывает на кнопку),
  /// false — под кнопкой (стрелка сверху).
  final bool above;

  const _Bubble({required this.message, required this.above});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Лёгкий фирменный оттенок вместо чистого белого: такой пузырь не
    // читается как системная «спеллчек»-подсказка.
    final bg = dark
        ? cs.surfaceContainerHigh
        : Color.lerp(cs.surfaceContainerLowest, cs.primary, 0.08)!;
    final fg = cs.onSurface;
    final edge = cs.outlineVariant.withValues(alpha: 0.65);
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: edge, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          height: 1.25,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
    final arrow = CustomPaint(
      size: const Size(14, 7),
      painter: _BubbleArrowPainter(
        fill: bg,
        stroke: edge,
        pointingUp: !above,
      ),
    );
    // Стрелка-хвостик смотрит на кнопку: сверху (пузырь снизу) или снизу.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: above
          ? [bubble, arrow]
          : [arrow, bubble],
    );
  }
}

/// Маленькая стрелка-хвостик пузыря: равнобедренный треугольник.
class _BubbleArrowPainter extends CustomPainter {
  final Color fill;
  final Color stroke;

  /// true — остриё сверху (пузырь под кнопкой), false — остриё снизу.
  final bool pointingUp;

  const _BubbleArrowPainter({
    required this.fill,
    required this.stroke,
    required this.pointingUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    if (pointingUp) {
      path.moveTo(0, h);
      path.lineTo(w, h);
      path.lineTo(w / 2, 0);
    } else {
      path.moveTo(0, 0);
      path.lineTo(w, 0);
      path.lineTo(w / 2, h);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleArrowPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.stroke != stroke ||
      oldDelegate.pointingUp != pointingUp;
}