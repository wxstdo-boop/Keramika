import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import 'stained_glass.dart';

/// Стиль текста тултипа — один и тот же для замера и для отрисовки,
/// иначе пузырь не совпадёт с реальным текстом.
const TextStyle _kTooltipTextStyle = TextStyle(
  fontSize: 12,
  height: 1.2,
  fontWeight: FontWeight.w500,
);

const Duration _kFade = Duration(milliseconds: 420);
const double _kRadius = 9;
const double _kArrowW = 13;
const double _kArrowH = 6;
const double _kPadX = 11;
const double _kPadY = 6;

/// Общий реестр активных пузырей по тексту подсказки. При переходе между
/// экранами старые и новые экземпляры SmoothTooltip (например, таблетки
/// разделов) одновременно снимают/ставят пузырь для ОДНОГО И ТОГО ЖЕ текста —
/// в общем оверлее они налезали друг на друга и подсказка «показывалась по
/// два раза». Реестр хранит живые СОСТОЯНИЯ владельцев по тексту: перед новым
/// показом для данного текста все ЧУЖИЕ пузыри той же подписи принудительно
/// гасятся (вместе со своими таймерами), поэтому в оверлее одновременно
/// существует не более одного пузыря на подпись.
///
/// Раньше реестр хранил только OverlayEntry, а состояния чужих владельцев
/// оставались «живыми»: их отложенные таймеры продолжали тикать и заново
/// показывали пузырь уже после снятия — отсюда «тултип появляется по много
/// раз» и «вечное» самопоявление при переходах между экранами.
final Map<String, Set<_SmoothTooltipState>> _activeTips =
    <String, Set<_SmoothTooltipState>>{};

/// Гасит все ЧУЖИЕ пузыри с тем же текстом и регистрирует [keep].
void _purgeForeignTips(String msg, _SmoothTooltipState keep) {
  final set = _activeTips[msg];
  if (set != null) {
    for (final s in set.toList()) {
      if (!identical(s, keep)) s._forceHide();
    }
  }
  (_activeTips[msg] ??= <_SmoothTooltipState>{}).add(keep);
}

/// Снимает [state] с реестра (при гашении пузыря или смерти владельца).
void _unregisterTip(String msg, _SmoothTooltipState state) {
  final set = _activeTips[msg];
  if (set == null) return;
  set.remove(state);
  if (set.isEmpty) _activeTips.remove(msg);
}

/// Всплывающая подсказка со стрелкой-указателем.
///
/// - Размер пузыря считается ТОЧНО (TextPainter): текст никогда не вылезает
///   за границы, а пузырь центрируется ровно на кнопке, стрелка указывает на
///   её центр.
/// - Пузырь и стрелка — ОДНА закрашенная фигура (см. [_BubblePainter]): у
///   стрелки нет отдельной полупрозрачной подложки, поэтому указатель не
///   темнее и не «стекляннее» самого пузыря.
/// - Появление при зажатии, исчезание ВСЕГДА плавное (420 мс): и при
///   отпускании, и при повторном нажатии, и при уходе с экрана — пузырь
///   доигрывает фейд даже после того, как виджет-владелец уже удалён.
class SmoothTooltip extends StatefulWidget {
  final String message;
  final Duration? waitDuration;
  final Duration showDuration;

  /// Показывать СВЕРХУ кнопки (стрелка снизу). Если false и сверху нет
  /// места — уходит вниз автоматически.
  final bool preferredAbove;
  final Widget child;

  const SmoothTooltip({
    super.key,
    required this.message,
    this.waitDuration,
    this.showDuration = const Duration(milliseconds: 1200),
    this.preferredAbove = true,
    required this.child,
  });

  @override
  State<SmoothTooltip> createState() => _SmoothTooltipState();
}

class _SmoothTooltipState extends State<SmoothTooltip> {
  final GlobalKey _anchorKey = GlobalKey();
  Timer? _showTimer;
  Timer? _hideTimer;
  Timer? _backstop;
  Timer? _routeMonitor;
  OverlayEntry? _entry;
  _TipShellState? _shell;
  bool _showing = false;
  bool _pointerDown = false;
  bool _reshowPending = false;

  // Геометрия текущего пузыря (считается один раз на показ).
  double _w = 0;
  double _unitH = 0;
  bool _above = true;

  // Стиль, разрешённый из DefaultTextStyle КНОПКИ (шрифт приложения).
  // Пузырь живёт в OverlayEntry — выше Material, где Flutter подставляет
  // fallback-стиль (monospace + жёлтое двойное подчёркивание). Без явного
  // стиля замер и отрисовка шли бы РАЗНЫМИ шрифтами: пузырь выходил уже
  // текста, и последняя буква обрезалась.
  TextStyle _textStyle = _kTooltipTextStyle;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _backstop?.cancel();
    _routeMonitor?.cancel();
    _unregisterTip(widget.message, this);
    final shell = _shell;
    final entry = _entry;
    _shell = null;
    _entry = null;
    _showing = false;
    if (shell != null && shell.mounted) {
      shell.detachAndFadeOut();
    } else if (entry != null) {
      try {
        entry.remove();
      } catch (_) {}
    }
    super.dispose();
  }

  /// Экстренно снять пузырь (владелец умер/сменился, либо чужой экземпляр с
  /// той же подписью перехватил показ) — ВМЕСТЕ со всеми отложенными
  /// таймерами. Без отмены таймеров отложенный `_hide`/`_show` дёрнул бы уже
  /// снятый OverlayEntry, а состояние навсегда осталось бы «показывающим».
  void _forceHide() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _backstop?.cancel();
    _routeMonitor?.cancel();
    _showTimer = null;
    _hideTimer = null;
    _backstop = null;
    _reshowPending = false;
    _pointerDown = false;
    _showing = false;
    _shell = null;
    final e = _entry;
    _entry = null;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {}
    }
    _unregisterTip(widget.message, this);
  }

  // ── Жесты ──────────────────────────────────────────────────────────

  void _onDown() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _backstop?.cancel();
    _pointerDown = true;
    // Тултип показан — убираем ЕГО ЖЕ плавным фейдом (не мгновенно) и
    // показываем заново, когда он догорит: никаких «мёртвых» щелчков.
    final wasShowing = _showing;
    _reshowPending = wasShowing;
    if (wasShowing) {
      _showing = false;
      final shell = _shell;
      _shell = null;
      _entry = null;
      if (shell != null && shell.mounted) {
        shell.detachAndFadeOut();
      }
    }
    _showTimer = Timer(
      wasShowing
          ? _kFade
          : (widget.waitDuration ?? const Duration(milliseconds: 200)),
      _show,
    );
  }

  void _onUp() {
    _pointerDown = false;
    // Отпустил — даём дочитать showDuration, затем плавно прячем.
    if (_showing) {
      _hideTimer?.cancel();
      _hideTimer = Timer(widget.showDuration, _hide);
    }
    // Перепоявление после плавного гашения НЕ отменяем: иначе короткий
    // «нажал-отпустил» оставлял кнопку вообще без подсказки.
    if (!_reshowPending) _showTimer?.cancel();
  }

  void _onCancel() {
    _onUp();
  }

  // ── Показ / скрытие ───────────────────────────────────────────────

  void _show() {
    if (!mounted || widget.message.isEmpty) return;
    // Не показываем подсказку, если экран-владелец уже НЕ на вершине: при
    // переходе на другой экран отложенный таймер иначе «выстреливал» пузырём
    // поверх нового экрана (и так — на каждом переходе), а вернувшись, можно
    // было получить ещё и накопленные пузыри. Показываем только своё.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final anchor = _anchorKey.currentContext;
    final box = anchor?.findRenderObject();
    if (anchor == null || box is! RenderBox || !box.hasSize || !box.attached) {
      return;
    }
    final overlay = Overlay.of(context);
    final oBox = overlay.context.findRenderObject();
    if (oBox is! RenderBox || !oBox.hasSize) return;

    // Точная геометрия: пузырь строится ровно по измеренному тексту.
    _textStyle = DefaultTextStyle.of(
      context,
    ).style.merge(_kTooltipTextStyle).copyWith(decoration: TextDecoration.none);
    final size = _measure(oBox.size.width);
    _w = size.width;
    _unitH = size.height;
    final pos = box.localToGlobal(Offset.zero, ancestor: oBox);
    final gap = 7.0;
    final belowTop = pos.dy + box.size.height + gap;
    final aboveTop = pos.dy - _unitH - gap;
    _above = widget.preferredAbove && aboveTop >= 8.0;
    // Защита от RangeError: если пузырь высокий/широкий (длинный текст на
    // несколько строк) и не влазится в оверлей — привязываем его к ближайшей
    // границе вместо падения.
    final maxTop = (oBox.size.height - _unitH - 4.0).clamp(
      4.0,
      double.infinity,
    );
    final top = (_above ? aboveTop : belowTop).clamp(4.0, maxTop);
    final maxLeft = (oBox.size.width - _w - 6.0).clamp(6.0, double.infinity);
    final left = (pos.dx + box.size.width / 2 - _w / 2).clamp(6.0, maxLeft);

    _dropExisting(); // на случай остатков предыдущего показа
    _showing = true;
    _reshowPending = false;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TipShell(
        message: widget.message,
        top: top,
        left: left,
        width: _w,
        above: _above,
        textStyle: _textStyle,
        onReady: _attachShell,
        remove: () {
          entry.remove();
          _unregisterTip(widget.message, this);
        },
        onGone: () => _gone(entry),
      ),
    );
    // Перед вставкой гасим ЧУЖИЕ пузыри с той же подписью — иначе при
    // переходе между экранами дубль налезает и подсказка показывается дважды.
    _purgeForeignTips(widget.message, this);
    _entry = entry;
    overlay.insert(entry);
    // A route can be covered without disposing its button. In that case its
    // pointer-up and the usual hide timer may never arrive, so watch route
    // visibility while this overlay is alive and fade it as soon as it is
    // covered.
    _routeMonitor?.cancel();
    _routeMonitor = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final activeRoute = ModalRoute.of(context);
      if (activeRoute != null && !activeRoute.isCurrent) _hide();
    });
    // Абсолютная страховка от «залипания»: даже если up/cancel потерялись
    // (смена экрана, системное окно) — подсказка уйдёт сама.
    _backstop?.cancel();
    // A missing pointer-up (for example, opening another app while holding
    // the control) must never leave an overlay or its registry entry alive.
    // Keep this independent of pointer state and force-remove the entry if
    // the normal fade path did not finish.
    final backstopDelay = widget.showDuration + const Duration(seconds: 2);
    _backstop = Timer(
      backstopDelay < const Duration(seconds: 8)
          ? const Duration(seconds: 8)
          : backstopDelay,
      _forceHide,
    );
    // Палец уже отпущен (этот показ догонял чужое гашение) — живём ровно
    // showDuration, а не до страховочного таймера.
    if (!_pointerDown) {
      _hideTimer = Timer(widget.showDuration, _hide);
    }
  }

  void _hide() {
    if (!_showing) return;
    _routeMonitor?.cancel();
    _routeMonitor = null;
    _hideTimer?.cancel();
    _backstop?.cancel();
    final shell = _shell;
    if (shell != null && shell.mounted) {
      shell.fadeOut();
    } else {
      _dropExisting();
    }
  }

  /// Пузырь сам сообщил, что его больше нет в оверлее.
  /// Гасим связи только если речь о НАСТОЯЩЕМ показе: старый пузырь,
  /// доигрывающий фейд после повторного нажатия, не должен «уронить» новый.
  void _gone(OverlayEntry entry) {
    if (_entry == entry) {
      _entry = null;
      _shell = null;
      _showing = false;
    }
    _unregisterTip(widget.message, this);
    _backstop?.cancel();
    _routeMonitor?.cancel();
    _routeMonitor = null;
  }

  /// Пузырь снят с оверлея владельцем.
  void _dropExisting() {
    _backstop?.cancel();
    _routeMonitor?.cancel();
    _routeMonitor = null;
    _showing = false;
    _shell = null;
    final e = _entry;
    _entry = null;
    if (e != null) {
      try {
        e.remove();
      } catch (_) {}
    }
    _unregisterTip(widget.message, this);
  }

  void _attachShell(_TipShellState shell) {
    _shell = shell;
  }

  // ── Точная геометрия пузыря ────────────────────────────────────────

  Size _measure(double overlayW) {
    // Доступная ширина текста: от края оверлея отступаем левый/правый
    // clamp-запас пузыря (по 6) и его горизонтальные паддинги (по [_kPadX]).
    // Долгая подсказка переносится на 2-4 строки, а высота пузыря считается
    // РЕАЛЬНО по числу строк (TextPainter, maxLines: 4).
    // Шкалу шрифта берём из MediaQuery (TextScaler): без неё TextPainter
    // меряет на unit-scale, а реальный Text рисуется на системном масштабе
    // шрифта — пузырь выходит меньше текста и буквы «заезжают».
    final textScaler = MediaQuery.textScalerOf(context);
    // Доступная ширина текста (оверлей минус клин-запасы и паддинги).
    final maxTextW = (overlayW - 12 - 2 * _kPadX).clamp(80.0, 244.0);

    // 1) Естественная (однострочная) ширина подписи.
    final probe = TextPainter(
      text: TextSpan(text: widget.message, style: _textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: double.infinity);
    final natW = probe.width;
    probe.dispose();

    // 2) Сужаем текст только когда он реально длиннее доступной ширины —
    //    короткие подписи («Назад») остаются компактными, а не «раздуваются».
    final wrapped = natW > maxTextW;
    final T = wrapped ? maxTextW : natW;

    // 3) Замер И отрисовка на ОДНОЙ и той же ширине T → перенос строк и
    //    высота идентичны; пузырь обтекает текст, поэтому «заезжание» букв
    //    и полоса переполнения невозможны.
    final tp = TextPainter(
      text: TextSpan(text: widget.message, style: _textStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 4,
    )..layout(maxWidth: T);
    final textH = tp.height;
    // Дробная ширина текста округляется ВВЕРХ: иначе крайняя буква стоит
    // ровно на границе бокса и её последний пиксель срезается. Для
    // перенесённого текста берём всю доступную ширину — тогда перенос строк
    // при отрисовке совпадает с замеренным.
    final textW = (wrapped ? T : tp.width).ceilToDouble();
    tp.dispose();

    return Size(textW + 2 * _kPadX, textH + 2 * _kPadY + _kArrowH);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: _anchorKey,
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onDown(),
      onPointerUp: (_) => _onUp(),
      onPointerCancel: (_) => _onCancel(),
      child: widget.child,
    );
  }
}

/// Сам пузырь вместе с анимацией. Живёт в элементе Overlay, а не в дереве
/// [SmoothTooltip], поэтому переживает его удаление и может плавно доиграть
/// исчезание, когда экран уже сменился.
class _TipShell extends StatefulWidget {
  final String message;
  final double top;
  final double left;
  final double width;
  final bool above;
  final TextStyle textStyle;
  final void Function(_TipShellState state) onReady;

  /// Убирает наш [OverlayEntry] из оверлея.
  final VoidCallback remove;

  /// Наш пузырь больше не виден — сообщаем владельцу (только для активного
  /// показа; при [detachAndFadeOut] владельца уже нет).
  final VoidCallback onGone;

  const _TipShell({
    required this.message,
    required this.top,
    required this.left,
    required this.width,
    required this.above,
    required this.textStyle,
    required this.onReady,
    required this.remove,
    required this.onGone,
  });

  @override
  State<_TipShell> createState() => _TipShellState();
}

class _TipShellState extends State<_TipShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _removeTimer;
  bool _leaving = false;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _kFade);
    final curved = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _fade = curved;
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(curved);
    _ctrl.forward();
    widget.onReady(this);
  }

  @override
  void dispose() {
    _removeTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Обратный ход той же кривой; по завершении — [onDone].
  void _leave(void Function() onDone) {
    if (_leaving) return;
    _leaving = true;
    _removeTimer?.cancel();
    _ctrl.reverse().then((_) {
      if (mounted) _finish(onDone);
    });
    // Страховка: если анимацию прервали (оверлей перестроили) — убираемся сами.
    _removeTimer = Timer(_kFade + const Duration(milliseconds: 200), () {
      if (mounted) _finish(onDone);
    });
  }

  void _finish(void Function() onDone) {
    // Снятие элемента может не успеть смонтировать dispose до страховочного
    // таймера — иначе OverlayEntry.remove() сработал бы дважды.
    if (_removed) return;
    _removed = true;
    _removeTimer?.cancel();
    onDone();
  }

  /// Плавный уход с уведомлением владельца (он же снимает элемент).
  void fadeOut() => _leave(() {
    widget.remove();
    widget.onGone();
  });

  /// Вызывается, когда владелец (кнопка) умер или перестал следить за нами:
  /// доигрываем исчезание и снимаем себя с оверлея НИКОГО не уведомляя —
  /// иначе старый пузырь «уронил» бы новый показ.
  void detachAndFadeOut() => _leave(widget.remove);
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.top,
      left: widget.left,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: Transform.translate(
            // Лёгкий «подлёт» от кнопки: блок выезжает и плавно встаёт.
            offset: Offset(
              0,
              (widget.above ? 1.0 : -1.0) * (1.0 - _scale.value) * 7.0,
            ),
            child: ScaleTransition(
              scale: _scale,
              alignment: widget.above
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: _Bubble(
                message: widget.message,
                width: widget.width,
                above: widget.above,
                textStyle: widget.textStyle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Пузырь + стрелка одной фигурой.
class _Bubble extends StatelessWidget {
  final String message;
  final double width;
  final bool above;
  final TextStyle textStyle;

  const _Bubble({
    required this.message,
    required this.width,
    required this.above,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest;
    final fg = cs.onSurface;
    // Стрелка (6 px) и паддинг (6 px) сливаются в один отступ со стороны
    // хвостика, поэтому текст стоит ровно по центру «тела» пузыря.
    // Хвост при above смотрит ВНИЗ (пузырь над кнопкой), при !above — ВВЕРХ.
    final tailSide = _kArrowH + _kPadY;
    final bodySide = _kPadY;
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _BubblePainter(
          color: bg,
          above: above,
          dark: dark,
          accent: cs.primary,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _kPadX,
            above ? bodySide : tailSide,
            _kPadX,
            above ? tailSide : bodySide,
          ),
          // DefaultTextStyle ОБЯЗАТЕЛЕН: пузырь рисуется в OverlayEntry — выше
          // Material, где Flutter подставляет fallback-стиль (monospace +
          // жёлтое двойное подчёркивание). Задаём стиль явно, тем же объектом,
          // которым мерили ширину — иначе текст рисуется шире пузыря.
          child: ExcludeSemantics(
            excluding: true,
            child: DefaultTextStyle(
              style: textStyle.copyWith(color: fg),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.clip,
              child: Text(message),
            ),
          ),
        ),
      ),
    );
  }
}

/// Тело пузыря и стрелка-указатель — ОДИН path, одна заливка, одна тень.
///
/// Раньше стрелка рисовалась отдельным треугольником ПОД контейнером: у
/// полупрозрачного цвета поверхности overlap давал двойную альфу, а тень
/// контейнера просвечивала сквозь стрелку — указатель выглядел мутным и
/// темнее пузыря. Целая фигура этого не допускает.
class _BubblePainter extends CustomPainter {
  final Color color;
  final bool above;
  final bool dark;

  /// Цвет капель — фирменный акцент темы, тем же мазком, что на таблетке.
  final Color accent;

  const _BubblePainter({
    required this.color,
    required this.above,
    required this.dark,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bodyH = size.height - _kArrowH;
    final bodyTop = above ? 0.0 : _kArrowH;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, bodyTop, size.width, bodyH),
      Radius.circular(_kRadius),
    );
    final tailBaseY = above ? size.height - _kArrowH : _kArrowH;
    final tailTipY = above ? size.height : 0.0;
    final cx = size.width / 2;
    final path = Path()
      ..addRRect(body)
      ..moveTo(cx - _kArrowW / 2, tailBaseY)
      ..lineTo(cx + _kArrowW / 2, tailBaseY)
      ..lineTo(cx, tailTipY)
      ..close();

    // Тень — по контуру всей фигуры сразу (тело + хвост).
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? 0.35 : 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );

    // Стеклянный мотив пузыря: те же следы капель, что на капсуле разделов,
    // но «чуть-чуть» — редкая мелочь и низкая плотность. Иначе тултип
    // перетягивал бы внимание с текста.
    canvas
      ..save()
      ..clipPath(path);
    StainedGlassPainter(
      color: accent,
      alpha: dark ? 0.13 : 0.10,
      specks: 9,
    ).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BubblePainter old) =>
      old.color != color ||
      old.above != above ||
      old.dark != dark ||
      old.accent != accent;
}

/// Стандартная кнопка «Назад» со стрелкой + тултипом со стрелкой-указателем.
class BackButtonTooltip extends StatelessWidget {
  const BackButtonTooltip({super.key});

  @override
  Widget build(BuildContext context) {
    return SmoothTooltip(
      message: Translations.t('back', context, 'Назад'),
      preferredAbove: false,
      child: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
