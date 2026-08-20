import 'dart:async';
import 'package:flutter/material.dart';

// Глобальный дедуп: одно и то же сообщение в окне кулдауна не показывается,
// а разные сообщения с одним groupKey обновляют активный снекбар плавно,
// не создавая шторм overlay-entries (важно для быстрых toggle-кнопок).
OverlayEntry? _activeSnackBar;
_AnimatedSnackBarState? _activeSnackState;
String? _activeGroupKey;
DateTime? _lastSnackTime;
String? _lastSnackMessage;
final Duration _snackCooldown = const Duration(milliseconds: 1200);

void showBeautifulSnackBar(
  BuildContext context, {
  required String message,
  IconData icon = Icons.check_circle_outline,
  Color? iconColor,
  Duration duration = const Duration(seconds: 3),
  String? groupKey,
  // Optional inline action-кнопка справа. Если задана, снекбар
  // перестаёт IgnorePointer'ить, иначе — пропускает тапы только внутрь.
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final now = DateTime.now();
  // Полный дедуп: точно тот же текст в окне кулдауна — игнорируем.
  if (_lastSnackMessage == message &&
      _lastSnackTime != null &&
      now.difference(_lastSnackTime!) < _snackCooldown) {
    return;
  }

  // Плавная замена внутри группы: если уже висит снекбар той же группы —
  // обновляем контент без удаления overlay. Это убирает шторм при быстром
  // ON↔OFF-переключении (например, тогл раздела «Проверки реальности»).
  if (groupKey != null &&
      _activeGroupKey == groupKey &&
      _activeSnackState != null &&
      _activeSnackState!.mounted) {
    _activeSnackState!.updateContent(message, icon, iconColor);
    _lastSnackTime = now;
    _lastSnackMessage = message;
    return;
  }

  _lastSnackTime = now;
  _lastSnackMessage = message;
  _activeGroupKey = groupKey;

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  _activeSnackBar?.remove();
  _activeSnackBar = null;
  _activeSnackState = null;

  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AnimatedSnackBar(
      message: message,
      icon: icon,
      iconColor: iconColor ?? colorScheme.onPrimaryContainer,
      theme: theme,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      onInit: (state) => _activeSnackState = state,
      onDispose: () {
        if (_activeSnackBar == entry) {
          _activeSnackBar = null;
          _activeSnackState = null;
          _activeGroupKey = null;
        }
      },
    ),
  );

  _activeSnackBar = entry;
  overlay.insert(entry);
}

class _AnimatedSnackBar extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color iconColor;
  final ThemeData theme;
  final Duration duration;
  final void Function(_AnimatedSnackBarState state)? onInit;
  final VoidCallback? onDispose;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _AnimatedSnackBar({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.theme,
    required this.duration,
    this.onInit,
    this.onDispose,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_AnimatedSnackBar> createState() => _AnimatedSnackBarState();
}

class _AnimatedSnackBarState extends State<_AnimatedSnackBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  late String _message;
  late IconData _icon;
  late Color _iconColor;
  String? _actionLabel;
  VoidCallback? _onAction;

  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _icon = widget.icon;
    _iconColor = widget.iconColor;
    _actionLabel = widget.actionLabel;
    _onAction = widget.onAction;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );

    // easeOutCubic вместо easeOutBack: мягкий выезд без резкого
    // «перелёта»/дребезга — плашка плавно оседает снизу и так же
    // мягко (reverseCurve easeInCubic) уплывает вниз при скрытии.
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(curved);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    _controller.forward();
    widget.onInit?.call(this);
    _scheduleDismiss();
  }

  /// Плавно обновляет содержимое без пересоздания overlay-entry.
  /// Используется при быстрых ON↔OFF-переключениях одной группы,
  /// чтобы пользователь видел одну плашку вместо шторма.
  void updateContent(String newMessage, IconData newIcon, Color? newColor) {
    setState(() {
      _message = newMessage;
      _icon = newIcon;
      if (newColor != null) _iconColor = newColor;
    });
    // Таймер отложенного скрытия — перезапускаем, чтобы пользователь успел
    // прочитать новый текст после быстрого toggle.
    _scheduleDismiss();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.duration, () {
      if (mounted) {
        // Уход — МЕДЛЕННЫЙ и плавный (750мс вместо тех же 520мс, что и вход):
        // снекбар не «выпадает» резко, а мягко уплывает вниз и растворяется.
        _controller
            .animateTo(
              0,
              duration: const Duration(milliseconds: 750),
              curve: Curves.easeInCubic,
            )
            .then((_) {
              _activeSnackBar?.remove();
              _activeSnackBar = null;
            });
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAction = _onAction != null && _actionLabel != null;
    return IgnorePointer(
      ignoring: !hasAction,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          if (_fadeAnimation.value <= 0.01) return const SizedBox.shrink();
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(position: _slideAnimation, child: child),
          );
        },
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 48, left: 16, right: 16),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: widget.theme.shadowColor.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.6,
                          end: 1.0,
                        ).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        _icon,
                        key: ValueKey(_icon.codePoint),
                        size: 20,
                        color: _iconColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.15, 0),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          _message,
                          key: ValueKey(_message),
                          style: widget.theme.textTheme.bodyMedium?.copyWith(
                            color: widget.theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                    if (hasAction) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: widget.theme.colorScheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(_actionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
