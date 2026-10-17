import 'dart:async';
import 'package:flutter/material.dart';

// Глобальный дедуп и мягкая замена: пока плашка висит, новое сообщение
// подменяет её содержимое на месте (никаких «вторых» снекбаров поверх) —
// поэтому быстрые тапы не превращаются в шторм overlay-entries.
OverlayEntry? _activeSnackBar;
_AnimatedSnackBarState? _activeSnackState;
// Вставка нового снекбара отложена на время ухода старого.
Timer? _pendingInsert;
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
  // Плавная замена «на месте»: пока плашка висит, ЛЮБОЕ новое сообщение
  // мягко подменяет её текст. Второй снекбар поверх неё не появляется вовсе,
  // поэтому «наложения» двух плашек больше нет: нет ни дублей, ни рывка.
  // Единственное исключение — появление/исчезновение action-кнопки: её
  // нельзя дорисовать в уже существующей плашке, там идёт аккуратная эстафета.
  final visible = _activeSnackState;
  final wantsAction = onAction != null && actionLabel != null;
  if (visible != null &&
      visible.mounted &&
      !visible.isLeaving &&
      visible.hasAction == wantsAction) {
    visible.updateContent(
      message,
      icon,
      iconColor,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    _lastSnackTime = now;
    _lastSnackMessage = message;
    return;
  }

  _lastSnackTime = now;
  _lastSnackMessage = message;

  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final overlay = Overlay.of(context);

  void insert() {
    if (!context.mounted) return;
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
        // Вызывается, когда анимация ухода дошла до нуля. Колбэк знает СВОЙ
        // entry, поэтому уходящий снекбар не спилит тот, что встал поверх.
        onFinished: () {
          if (_activeSnackBar == entry) {
            _activeSnackBar = null;
            _activeSnackState = null;
          }
          entry.remove();
        },
        onDispose: () {
          if (_activeSnackBar == entry) {
            _activeSnackBar = null;
            _activeSnackState = null;
          }
        },
      ),
    );
    _activeSnackBar = entry;
    overlay.insert(entry);
  }

  // Смена снекбаров (например, при появлении action-кнопки): предыдущий
  // мягко уплывает вниз (400 мс, easeInOutCubic), а новый влетает ЧУТЬ
  // позже, когда первый уже ушёл — поэтому две плашки не накладываются
  // друг на друга, переход выглядит спокойным.
  // Очередь быстрых сообщений отменяет незапущенную вставку, так что на
  // экране оседает только последнее.
  final leaving = _activeSnackState;
  _activeSnackState = null;
  _activeSnackBar = null;
  _pendingInsert?.cancel();
  if (leaving != null && leaving.mounted) {
    leaving.dismissOut(ms: 400);
    _pendingInsert = Timer(const Duration(milliseconds: 430), () {
      _pendingInsert = null;
      insert();
    });
    return;
  }
  insert();
}

class _AnimatedSnackBar extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color iconColor;
  final ThemeData theme;
  final Duration duration;
  final void Function(_AnimatedSnackBarState state)? onInit;
  final VoidCallback? onDispose;
  final VoidCallback? onFinished;
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
    this.onFinished,
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
  bool _leaving = false;

  /// Когда плашка появилась (или обновилась) — окно «шквала» считается от
  /// этого момента.
  DateTime shownAt = DateTime.now();

  /// Плашка уже уплывает — новое сообщение должно идти эстафетой, а не
  /// «оживлять» уходящую.
  bool get isLeaving => _leaving;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    _icon = widget.icon;
    _iconColor = widget.iconColor;
    _actionLabel = widget.actionLabel;
    _onAction = widget.onAction;
    shownAt = DateTime.now();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );

    // easeOutCubic вместо easeOutBack: мягкий выезд без резкого
    // «перелёта»/дребезга — плашка плавно оседает снизу и так же
    // мягко (reverseCurve easeInOutCubic) уплывает вниз при скрытии.
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(curved);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    _controller.forward();
    widget.onInit?.call(this);
    _scheduleDismiss();
  }

  /// Плавно обновляет содержимое без пересоздания overlay-entry.
  /// Используется при быстрых ON↔OFF-переключениях одной группы и вообще
  /// для любого сообщения, пока плашка висит: пользователь видит одну
  /// плашку с мягко сменившимся текстом вместо второй поверх первой.
  void updateContent(
    String newMessage,
    IconData newIcon,
    Color? newColor, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Уже уплывает — не «оживляем» его, новый снекбар встанет следом.
    if (_leaving) return;
    shownAt = DateTime.now();
    setState(() {
      _message = newMessage;
      _icon = newIcon;
      if (newColor != null) _iconColor = newColor;
      _actionLabel = actionLabel;
      _onAction = onAction;
    });
    // Таймер отложенного скрытия — перезапускаем, чтобы пользователь успел
    // прочитать новый текст после быстрого toggle.
    _scheduleDismiss();
  }

  /// Есть ли у плашки action-кнопка — по этому признаку решается, можно ли
  /// обновить содержимое «на месте» или нужна эстафета плашек.
  bool get hasAction => _onAction != null && _actionLabel != null;

  /// Плавный уход вниз. 400 мс — при эстафете сообщений, 900 мс — когда
  /// снекбар сам дотикал до конца. Кривая easeInOutCubic: плашка трогается
  /// мягко и так же мягко «растворяется» в конце, без обрыва.
  void dismissOut({int ms = 320}) {
    if (_leaving || !mounted) return;
    _leaving = true;
    _dismissTimer?.cancel();
    _controller
        .animateTo(
          0.0,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeInOutCubic,
        )
        .then((_) => _finish());
    // Страховка: если тикер не доехал (быстрый тап, потеря vsync), entry
    // всё равно уберётся из overlay и не останется невидимым мусором.
    Timer(Duration(milliseconds: ms + 150), _finish);
  }

  bool _finished = false;
  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished?.call();
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.duration, () => dismissOut(ms: 900));
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
                        // 320 мс и ЧИСТЫЙ фейд без сдвига: общий префикс
                        // сообщений («Привычка закреплена» → «…откреплена»)
                        // остаётся на месте, буквы не «скачут» — меняется
                        // только хвост, мягко проявляясь.
                        duration: const Duration(milliseconds: 320),
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        // ВАЖНО: текст прижат ВЛЕВО и в стопке остаётся только
                        // предыдущий вариант. Стандартная стопка центрировала
                        // короткий текст, и при смене сообщения буквы уезжали
                        // в сторону.
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (previous.isNotEmpty) previous.last,
                            ?current,
                          ],
                        ),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(
                          _message,
                          key: ValueKey(_message),
                          style: widget.theme.textTheme.bodyMedium?.copyWith(
                            color: widget.theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            // «Чуть крупнее»: глобальная тема намеренно
                            // уменьшает bodyMedium (плотные разделы), но
                            // снекбар — короткое служебное сообщение,
                            // мелким быть не должно. +2 к базовому размеру
                            // (учитывает и Caveat-тему, и системный скейл,
                            // который применяется поверх при рендере).
                            fontSize:
                                (widget.theme.textTheme.bodyMedium?.fontSize ??
                                    14) +
                                2,
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
