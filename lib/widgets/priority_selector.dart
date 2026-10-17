import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import 'press_scale.dart';

/// Цвет приоритета — тот же язык, что у таблетки приоритета в списке задач.
Color priorityColor(int p, ThemeData theme) => switch (p) {
  2 => Colors.red.shade400,
  1 => Colors.orange.shade500,
  _ => Colors.green.shade500,
};

/// Иконка приоритета: маркер совпадает с иконкой в карточке задачи.
IconData priorityIcon(int p) => switch (p) {
  2 => Icons.warning_amber_rounded,
  1 => Icons.hourglass_empty_rounded,
  _ => Icons.push_pin_rounded,
};

/// Выбор приоритета: нейтральная дорожка + «жирная» цветная таблетка, которая
/// ПЛАВНО СКОЛЬЗИТ к выбранному уровню (AnimatedAlign).
///
/// Можно и просто тапнуть по уровню, и ЗАЖАТЬ дорожку и вести палец по всем
/// трём — таблетка едет под пальцем, уровень переключается на границе третей,
/// а на отпускании таблетка мягко доезжает до выбранного уровня.
///
/// Важно: сама таблетка — это ОДИН плоский DecoratedBox со сплошным цветом
/// (никакого градиента, никаких TweenAnimationBuilder'ов, пересобирающих
/// подписи каждый кадр). Именно их наложение на части GPU (Adreno) мелькало
/// серыми квадратами вместо текста и иконок при переключении.
/// Подписи и значки живут отдельным слоем, их цвет переключается мгновенно —
/// без «проездов через серый».
class PrioritySelector extends StatefulWidget {
  const PrioritySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  static const double _kHeight = 52;
  static const double _kInset = 3;

  @override
  State<PrioritySelector> createState() => _PrioritySelectorState();
}

class _PrioritySelectorState extends State<PrioritySelector>
    with TickerProviderStateMixin {
  /// Положение таблетки в единицах Alignment (-1..1). Ведётся ПРУЖИНОЙ, а во
  /// время перетаскивания — сглаженным «догоном» за пальцем. Так новый тап
  /// лишь меняет цель: при быстрых тапах по двум уровням таблетка не
  /// «заедает» и не прыгает, а мягко доворачивает с уже набранной скоростью.
  late final AnimationController _pill = AnimationController.unbounded(
    vsync: this,
    value: (widget.value - 1).toDouble(),
  );

  /// Куда тянет палец (в единицах Alignment, с «резинкой» за краями).
  double? _dragTarget;

  bool get _dragging => _dragTarget != null;

  /// Сглаживающий догон за пальцем. Палец дрожит на несколько десятых
  /// пикселя, а на экране это читается как дёрганье таблетки: вести её
  /// 1:1 за сырыми координатами — значит повторять весь шум тача. Здесь
  /// позиция догоняет цель экспоненциально (одинаково на любом fps).
  late final Ticker _follow = createTicker(_tickFollow);
  Duration _lastTick = Duration.zero;

  /// Насколько «резинка» пускает таблетку за край дорожки — только на время
  /// перетаскивания, на отпускании пружина возвращает её на место.
  static const double _overshoot = 0.11;

  /// Пружина таблетки: близко к критическому демпфированию — мягкая «отдача»
  /// без заметного отскока.
  static final SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 2 * math.sqrt(320) * 0.9,
  );

  @override
  void dispose() {
    _follow.dispose();
    _pill.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PrioritySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пока палец на дорожке, позицию ведёт он — пружину не запускаем.
    if (widget.value != oldWidget.value && !_dragging) {
      _springTo((widget.value - 1).toDouble());
    }
  }

  void _springTo(double target) {
    _pill.animateWith(
      SpringSimulation(_spring, _pill.value, target, _pill.velocity),
    );
  }

  /// «Резинка»: до края — 1:1, за краем — всё туже. Таблетка чуть заезжает
  /// за границу дорожки (это и просили «для красоты»), но не улетает.
  static double _rubber(double v) {
    if (v > 1) {
      return 1 + _overshoot * (1 - math.exp(-(v - 1) * 1.6));
    }
    if (v < -1) {
      return -1 - _overshoot * (1 - math.exp((-v - 1) * 1.6));
    }
    return v;
  }

  /// Палец на дорожке: таблетка плавно догоняет его, а уровень меняется, как
  /// только палец переходит в соседнюю треть.
  void _track(double x, double width) {
    if (width <= 0) return;
    final frac = (x / width).clamp(0.0, 1.0);
    final p = (frac * 3).floor().clamp(0, 2);
    // Центр k-й трети — это frac = (k + 0.5) / 3; переводим в Alignment.
    final pos = _rubber(3 * frac - 1.5);
    if (_dragTarget == null) {
      // Палец только коснулся: пружина уступает, догон стартует с нуля.
      _pill.stop();
      _lastTick = Duration.zero;
      if (!_follow.isActive) _follow.start();
      // Подписи перестают «вдавливаться», пока палец ведёт таблетку.
      setState(() {});
    }
    _dragTarget = pos;
    if (p != widget.value) {
      Haptics.select();
      widget.onChanged(p);
    }
  }

  void _tickFollow(Duration elapsed) {
    final target = _dragTarget;
    if (target == null) {
      _follow.stop();
      return;
    }
    // dt в секундах; первый кадр считаем за один кадр 60 Гц.
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;
    // Экспоненциальное сглаживание: скорость догона не зависит от fps.
    final k = 1 - math.exp(-dt * 30);
    var next = _pill.value + (target - _pill.value) * k;
    if ((target - next).abs() < 0.0015) next = target;
    _pill.value = next;
  }

  void _endDrag() {
    if (!mounted) return;
    _dragTarget = null;
    if (_follow.isActive) _follow.stop();
    // Мягкая «отдача»: таблетка плавно доезжает до выбранного уровня —
    // в том числе возвращается из «заезда» за край.
    _springTo((widget.value - 1).toDouble());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final activeColor = priorityColor(widget.value, theme);

    return SizedBox(
      width: double.infinity,
      height: PrioritySelector._kHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Драг начинается от точки касания (а не от порога в 18 px):
            // «зажал и повёл» отзывается сразу.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (d) => _track(d.localPosition.dx, w),
            onHorizontalDragUpdate: (d) => _track(d.localPosition.dx, w),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
            child: Stack(
              // Подписи стоят строго по центру дорожки (раньше Stack без
              // alignment прижимал неклипованных детей к верху — текст
              // «заезжал»).
              alignment: Alignment.center,
              // Таблетке разрешено чуть выезжать за дорожку на перетаскивании
              // (см. _rubber): это «резинка», а не обрезка по краю.
              clipBehavior: Clip.none,
              children: [
                // Дорожка-капсула: мягкий тонированный фон без обводок и теней.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(
                        alpha: isDark ? 0.06 : 0.05,
                      ),
                      borderRadius: BorderRadius.circular(
                        PrioritySelector._kHeight / 2,
                      ),
                    ),
                  ),
                ),
                // Скользящая «жирная» таблетка: сплошной цвет приоритета,
                // скругление — ровно половина высоты. Позицию ведёт пружина
                // (см. _pill): плавно и без заеданий при частых тапах.
                AnimatedBuilder(
                  animation: _pill,
                  builder: (context, child) => Align(
                    // -1 / 0 / +1 — левый / центральный / правый сегмент.
                    alignment: Alignment(_pill.value, 0),
                    child: child,
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 1 / 3,
                    heightFactor: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(PrioritySelector._kInset),
                      child: AnimatedContainer(
                        key: const ValueKey<String>('priority_pill'),
                        // Цвет таблетки перетекает мягко (360 мс), а не
                        // переключается рывком — при смене приоритета видно
                        // плавное «переливание» красный↔жёлтый↔зелёный.
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeInOutCubic,
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(
                            (PrioritySelector._kHeight -
                                    PrioritySelector._kInset * 2) /
                                2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Подписи — поверх таблетки, всегда видимы и читаемы.
                Row(
                  children: [
                    for (var p = 0; p < 3; p++)
                      Expanded(
                        child: _PriorityOption(
                          priority: p,
                          selected: widget.value == p,
                          // Во время перетаскивания «вдавливание» пальца
                          // передано таблетке — подписи не остаются
                          // прижатыми.
                          pressed: !_dragging,
                          theme: theme,
                          onTap: () {
                            if (widget.value == p) return;
                            Haptics.select();
                            widget.onChanged(p);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({
    required this.priority,
    required this.selected,
    required this.pressed,
    required this.theme,
    required this.onTap,
  });

  final int priority;
  final bool selected;
  final bool pressed;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final label = switch (priority) {
      2 => Translations.t('priorityHigh', context),
      1 => Translations.t('priorityMedium', context),
      _ => Translations.t('priorityLow', context),
    };
    // Поверх «жирной» цветной таблетки текст всегда белый; вне её —
    // нейтральный onSurfaceVariant. Переход мягкий (360 мс): при смене
    // приоритета текст и значок «перетекают» в новый цвет, а не мигают.
    final fg = selected ? Colors.white : cs.onSurfaceVariant;
    final style = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      height: 1.4,
      letterSpacing: 0.2,
      fontWeight: FontWeight.w800,
      color: fg,
    );

    return PressScale(
      enabled: pressed,
      pressedScale: 0.96,
      duration: const Duration(milliseconds: 220),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Плавная смена цвета значка: TweenAnimationBuilder сам
              // «доезжает» от прошлого цвета к новому.
              TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: fg),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeInOutCubic,
                builder: (context, color, _) =>
                    Icon(priorityIcon(priority), size: 16, color: color ?? fg),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeInOutCubic,
                  style: style,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
