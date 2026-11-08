import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../utils/animated_delete.dart';

/// Свайп-удаление влево с красным фоном, который плавно проявляется по ходу
/// жеста. Обёртка над [Dismissible]: вся логика (порог, подтверждение,
/// удаление, схлопывание строки) остаётся за ним, но визуальный ход карточки
/// идёт по СГЛАЖЕННОМУ значению, а не жёстко 1:1 за пальцем.
///
/// Зачем сглаживание: у [Dismissible] смещение жёстко равно пройденному
/// пальцем пути, поэтому мелкое дрожание пальца (рука не стоит на месте)
/// раскачивало карточку на те же пиксели — «дико дергает». Здесь палец задаёт
/// ЦЕЛЬ, а карточка догоняет её логарифмически (низкочастотный фильтр): мелкое
/// дрожание гасится, осознанный свайп проходит почти без задержки.
class SwipeToDelete extends StatefulWidget {
  final Key dismissKey;
  final Widget child;
  final DismissDirectionCallback? onDismissed;
  final ConfirmDismissCallback? confirmDismiss;
  final Duration? movementDuration;
  final double borderRadius;

  /// Горизонтальный отступ карточки: фон удаления рисуется в тех же
  /// границах, чтобы красная плашка не «заезжала» за боковые края.
  final double horizontalInset;

  const SwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onDismissed,
    this.confirmDismiss,
    this.movementDuration,
    this.borderRadius = 20,
    this.horizontalInset = 0,
  });

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete>
    with SingleTickerProviderStateMixin {
  /// Сырой прогресс [Dismissible] (0..1) — жёстко следует за пальцем.
  final ValueNotifier<double> _raw = ValueNotifier<double>(0);

  /// Сглаженный прогресс: догоняет [_raw] логарифмически и гасит
  /// высокочастотное дрожание пальца.
  final ValueNotifier<double> _smooth = ValueNotifier<double>(0);

  /// Отставание сглаженного от сырого (в долях ширины): на столько пикселей
  /// карточка «придерживается», компенсируя жёсткий сдвиг [Dismissible].
  final ValueNotifier<double> _lag = ValueNotifier<double>(0);

  /// Доля, которую сглаженное значение проходит к цели за кадр (~60 Гц).
  /// Меньше — мягче и «тяжелее», но с большей задержкой за пальцем.
  static const double _follow = 0.34;

  late final Ticker _ticker = createTicker(_tick);

  @override
  void initState() {
    super.initState();
    _raw.addListener(_wake);
  }

  @override
  void dispose() {
    _raw.removeListener(_wake);
    _ticker.dispose();
    _raw.dispose();
    _smooth.dispose();
    _lag.dispose();
    super.dispose();
  }

  /// Новый сдвиг (палец или анимация [Dismissible]) — будим догоняющий тикер.
  /// Крайние точки фиксируем СРАЗУ: иначе на удалении карточка на один кадр
  /// «задержалась» бы в слоте, пока схлопывание строки уже началось.
  void _wake() {
    final target = _raw.value;
    if (target >= 0.999) {
      _smooth.value = 1;
      _lag.value = 0;
      _ticker.stop();
      return;
    }
    if (target <= 0.001) {
      _smooth.value = 0;
      _lag.value = 0;
      _ticker.stop();
      return;
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final target = _raw.value;
    final current = _smooth.value;
    final next = current + (target - current) * _follow;
    _smooth.value = next;
    _lag.value = target - next;
    if ((target - next).abs() < 0.0004) {
      _smooth.value = target;
      _lag.value = 0;
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Dismissible(
          key: widget.dismissKey,
          // 320мс вместо 200: возврат карточки после отпускания плавнее,
          // не «отщёлкивает» резко (линейная анимация Dismissible).
          movementDuration:
              widget.movementDuration ??
              const Duration(milliseconds: 320),
          // Сжатие высоты строки при удалении тоже плавное — карточка
          // «схлопывается» мягко, а не исчезает рывком.
          resizeDuration: const Duration(milliseconds: 340),
          direction: DismissDirection.endToStart,
          confirmDismiss: widget.confirmDismiss,
          onDismissed: widget.onDismissed,
          onUpdate: (d) => _raw.value = d.progress,
          background: ValueListenableBuilder<double>(
            valueListenable: _smooth,
            builder: (context, p, _) {
              // Фон виден, только когда карточку реально тянут: 20 % —
              // заметный, но осознанный жест. Прогресс СГЛАЖЕННЫЙ — красная
              // плашка открывается ровно на столько, на сколько визуально
              // уехала карточка (без дрожания по каждому микросдвигу).
              final opacity = ((p - 0.20) / 0.80).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                // Фон удаления изолирован: при snap-back Dismissible
                // двигает слой, а не пересобирает градиент/текст каждый кадр.
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.horizontalInset,
                  ),
                  child: RepaintBoundary(
                    child: animatedDeleteBackground(
                      context,
                      borderRadius: widget.borderRadius,
                    ),
                  ),
                ),
              );
            },
          ),
          // Dismissible двигает карточку жёстко (1:1 за пальцем) — возвращаем
          // её назад на [_lag], чтобы визуально она ехала по сглаженному
          // прогрессу. Оба слоя (карточка и фон) читают один и тот же
          // сглаженный ход, поэтому расходятся только на разницу фаз, которую
          // гасит фильтр.
          child: ValueListenableBuilder<double>(
            valueListenable: _lag,
            builder: (context, lag, child) =>
                Transform.translate(offset: Offset(lag * width, 0), child: child),
            // RepaintBoundary кэширует карточку текстурой: при скролле и
            // свайпе список двигает готовую картинку, а не перерисовывает
            // содержимое каждой карточки каждый кадр (важно для слабых
            // устройств).
            child: RepaintBoundary(child: widget.child),
          ),
        );
      },
    );
  }
}

