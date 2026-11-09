import 'dart:math' as math;

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
/// ЦЕЛЬ, а карточка догоняет её пружиной: мелкое дрожание гасится, осознанный
/// свайп проходит почти без задержки.
///
/// Почему ПРУЖИНА, а не прежний экспоненциальный догон: экспонента к цели
/// только ПРИБЛИЖАЕТСЯ, никогда её не достигая, поэтому в конце возврата
/// оставался «хвост» (заметное отставание). Его приходилось «приклеивать»
/// скачком к нулю — и это читалось как УДАР по финишу. Критически
/// задемпфированная пружина догоняет и останавливается САМА, без скачка: ход
/// остаётся непрерывным до самой остановки.
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

  /// Сглаженный прогресс: догоняет [_raw] пружиной и гасит
  /// высокочастотное дрожание пальца.
  final ValueNotifier<double> _smooth = ValueNotifier<double>(0);

  /// Отставание сглаженного от сырого (в долях ширины): на столько пикселей
  /// карточка «придерживается», компенсируя жёсткий сдвиг [Dismissible].
  final ValueNotifier<double> _lag = ValueNotifier<double>(0);

  /// Жёсткость пружины, 1/с². Критическое демпфирование c = 2·√k даёт ход
  /// без перелёта и без «хвоста»: пружина тормозит ровно на подходе к цели.
  /// k = 1200 → ω ≈ 34.6 рад/с: дрожание пальца (~30 Гц) гасится почти в 30
  /// раз, а осознанный свайп отстаёт всего на ~15 px (на 400 px ширины).
  static const double _stiffness = 1200.0;

  /// Скорость сглаженного значения (доли ширины в секунду) — состояние
  /// пружины между кадрами.
  double _velocity = 0;

  /// Время прошлого кадра пружины: шаг считается по РЕАЛЬНОМУ dt кадра,
  /// поэтому ход не зависит от частоты обновления экрана.
  Duration _lastElapsed = Duration.zero;

  /// Цель прошлого кадра — по её развороту ловим момент, когда палец пошёл
  /// назад, и гасим накопленный импульс пружины (см. [_tick]).
  double _lastTarget = 0;

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
  /// Полное удаление фиксируем СРАЗУ: карточка к тому моменту уже за кромкой,
  /// скачок невидим, а схлопывание строки не должно ждать пружину.
  void _wake() {
    if (_raw.value >= 0.999) {
      _smooth.value = 1;
      _lag.value = 0;
      _velocity = 0;
      _ticker.stop();
      return;
    }
    if (!_ticker.isActive) {
      _lastElapsed = Duration.zero;
      // Новый жест: цель прошлого кадра перечитываем, иначе на первом тике
      // «разворот» считался бы от значения ПРЕДЫДУЩЕГО свайпа.
      _lastTarget = _raw.value;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final target = _raw.value;
    final current = _smooth.value;
    var dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // Защита от нулевого/огромного шага (первый кадр, просадка, возврат из
    // фона): на таком шаге пружина «взрывается». Считаем по кадру 60 Гц.
    if (dt <= 0 || dt > 1 / 30) dt = 1 / 60;

    // Полунеявная схема Эйлера, чуть ПЕРЕдемпфированная (c = 2.1·√k): ход без
    // перелёта и без «хвоста».
    final c = 2.1 * math.sqrt(_stiffness);
    final targetDelta = target - _lastTarget;
    _lastTarget = target;
    // Разворот цели (палец пошёл назад) — гасим накопленный импульс, чтобы
    // пружина не пронесла его через разворот и не толкнула карточку наружу.
    if (targetDelta * _velocity < 0) _velocity = 0;
    final accel = (target - current) * _stiffness - _velocity * c;
    _velocity += accel * dt;
    var next = current + _velocity * dt;

    // ВОЗВРАТ (цель едет к нулю): сглаженное значение обязано только
    // убывать. Сразу после отпускания оно ещё отстаёт, и пружина норовила
    // «догнать» пик — толкала карточку наружу. Это и был откат-«кивок»,
    // читавшийся как удар по финишу. Держим ход монотонным вниз.
    if (targetDelta < 0 && next > current) {
      next = current;
      if (_velocity > 0) _velocity = 0;
    }

    _smooth.value = next;
    _lag.value = target - next;

    // Пружина остановилась сама — гасим тикер, чтобы не крутить кадры зря.
    if ((target - next).abs() < 0.0006 && _velocity.abs() < 0.01) {
      _smooth.value = target;
      _lag.value = 0;
      _velocity = 0;
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
          // 460мс: возврат карточки после отпускания идёт неспешно, а
          // пружина доводит его мягко, без удара на финише.
          movementDuration:
              widget.movementDuration ??
              const Duration(milliseconds: 460),
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
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.horizontalInset,
                ),
                // Фон удаления изолирован: при snap-back Dismissible
                // двигает слой, а не пересобирает градиент/текст каждый кадр.
                // Альфа запечена в цвета (opacity:), а не навешена слоем
                // Opacity — тому на каждый кадр нужен saveLayer.
                child: RepaintBoundary(
                  child: animatedDeleteBackground(
                    context,
                    borderRadius: widget.borderRadius,
                    opacity: opacity,
                  ),
                ),
              );
            },
          ),
          // Dismissible двигает карточку жёстко (1:1 за пальцем) — возвращаем
          // её назад на [_lag], чтобы визуально она ехала по сглаженному
          // прогрессу. Оба слоя (карточка и фон) читают один и тот же
          // сглаженный ход, поэтому расходятся только на разницу фаз, которую
          // гасит пружина.
          child: ValueListenableBuilder<double>(
            valueListenable: _lag,
            builder: (context, lag, child) => Transform.translate(
              offset: Offset(lag * width, 0),
              child: child,
            ),
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
