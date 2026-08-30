import 'dart:async';

import 'package:flutter/material.dart';

/// Всплывающая подсказка с ПЛАВНЫМ появлением и исчезанием (фейд + лёгкий
/// scale), в отличие от дефолтной `Tooltip`, которая у нас дёргается.
/// Триггер — долгое нажатие/зажатие, как и у системного тултипа.
class SmoothTooltip extends StatefulWidget {
  final String message;
  final Duration? waitDuration;
  final Widget child;

  const SmoothTooltip({
    super.key,
    required this.message,
    this.waitDuration,
    required this.child,
  });

  @override
  State<SmoothTooltip> createState() => _SmoothTooltipState();
}

class _SmoothTooltipState extends State<SmoothTooltip>
    with SingleTickerProviderStateMixin {
  final GlobalKey _anchorKey = GlobalKey();
  Timer? _showTimer;
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
      duration: const Duration(milliseconds: 260),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curved;
    _scale = Tween<double>(begin: 0.94, end: 1.0).animate(curved);
  }

  @override
  void dispose() {
    _showTimer?.cancel();
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
    _hide();
  }

  /// Плавно показываем подсказку у зажатой кнопки.
  void _show() {
    if (!mounted || _locked) return;
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
                child: _Bubble(message: widget.message),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
    _controller.forward();
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
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: dark ? cs.surfaceContainerHigh : cs.inverseSurface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18),
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
          color: dark ? cs.onSurface : cs.onInverseSurface,
        ),
      ),
    );
  }
}