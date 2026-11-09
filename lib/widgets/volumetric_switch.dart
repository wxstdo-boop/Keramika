import 'package:flutter/material.dart';
import '../services/haptics.dart';

/// Переключатель-«камень в желобке»: крупный, объёмный, с плавным ходом.
///
/// ОДИН источник движения: трек, шайба и галочка считаются от одного
/// [AnimationController] и одной кривой, поэтому все слои доезжают
/// ОДНОВРЕМЕННО и ход читается цельным, а не «дёрганым».
///
/// ТРЕК
///   * выключен — ровный нейтральный желобок в тон поверхности;
///   * включён — сплошной фирменный цвет с мягким свечением.
///   * цвет и тени лерпятся по одному параметру t — фон «течёт», не скачет.
///
/// ШАЙБА
///   * плотный белый круг с мягкой контактной тенью (без радужных градиентов
///     и световых полос — они читались как «грязь» на маленьком размере);
///   * во включённом проступает галочка фирменным цветом;
///   * при нажатии мягко «сплющивается» в овал — тактильный отклик;
///   * ход тягучий (easeInOutCubic) — докатывается, а не прыгает к краю.
///
/// При переключении — короткий тактильный отклик. API:
/// [VolumetricSwitch(value:, onChanged:, activeColor:, scale:)].
class VolumetricSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  /// Подпись для TalkBack. Если не задана — переключатель озвучивается как
  /// «переключатель, вкл/выкл» без названия; для важных настроек (вибрация,
  /// «убрать анимации») её стоит задавать.
  final String? semanticLabel;

  /// Масштаб трека/шайбы. 1.0 — базовый (54×32). Значение по умолчанию
  /// поднято до 1.15: переключатель «объёмнее» и по нему комфортнее попадать
  /// пальцем. В плотных списках уголка разработчика передают ещё крупнее.
  final double scale;

  const VolumetricSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.semanticLabel,
    this.scale = 1.15,
  });

  @override
  State<VolumetricSwitch> createState() => _VolumetricSwitchState();
}

class _VolumetricSwitchState extends State<VolumetricSwitch>
    with SingleTickerProviderStateMixin {
  /// 0 — выключен, 1 — включён. Стартует уже в нужном положении, поэтому
  /// при появлении в списке переключатель не «доезжает» из нуля.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.value ? 1 : 0,
  );

  /// Мягкая двусторонняя кривая: нулевая скорость на обоих концах — ход
  /// начинается и заканчивается спокойно, без «щелчка» на финише.
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOutCubic,
  );

  /// Палец на переключателе: шайба «сплющивается» в овал — тактильный
  /// отклик, как у системных переключателей.
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  void didUpdateWidget(covariant VolumetricSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      widget.value ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.activeColor ?? scheme.primary;
    final k = widget.scale;

    // Выключенный желобок: нейтральная поверхность чуть темнее фона — читается
    // как «пусто», а не как цветная каша. В тёмной теме чуть светлее фона.
    final trackOff = isDark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerHigh;

    // Шайба: при нажатии чуть шире и ниже — «сплющилась» под пальцем.
    final thumbW = 26 * k * (_pressed ? 1.14 : 1.0);
    final thumbH = 26 * k * (_pressed ? 0.90 : 1.0);

    return Semantics(
      container: true,
      toggled: widget.value,
      enabled: widget.onChanged != null,
      label: widget.semanticLabel,
      child: Listener(
        // Отклик нажатия: шайба «сплющивается». Listener не перехватывает
        // тап — действие остаётся у GestureDetector ниже.
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onChanged == null
              ? null
              : () {
                  Haptics.select();
                  widget.onChanged!(!widget.value);
                },
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final t = _t.value;
                return Container(
                  width: 54 * k,
                  height: 32 * k,
                  padding: EdgeInsets.all(3 * k),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16 * k),
                    // Цвет лерпится от нейтрального к фирменному по одному
                    // параметру t — фон «течёт» вместе с шайбой, не скачет.
                    color: Color.lerp(trackOff, active, t),
                    boxShadow: [
                      // Лёгкая внутренняя тень сверху — желобок «утоплен».
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (isDark ? 0.30 : 0.14) * (1.0 - t) + 0.16 * t,
                        ),
                        blurRadius: 3 * k,
                        spreadRadius: 0.4 * k,
                        offset: Offset(0, -1.4 * k),
                      ),
                      // Мягкое свечение фирменного цвета — только во включённом.
                      BoxShadow(
                        color: active.withValues(alpha: 0.32 * t),
                        blurRadius: 13 * k,
                        spreadRadius: -2 * k,
                        offset: Offset.zero,
                      ),
                    ],
                  ),
                  child: Align(
                    alignment: Alignment.lerp(
                      Alignment.centerLeft,
                      Alignment.centerRight,
                      t,
                    )!,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: thumbW,
                      height: thumbH,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Плотный белый круг: в тёмной теме — чуть приглушён,
                        // чтобы не слепить на тёмном треке.
                        color: isDark
                            ? const Color(0xFFF2F3F5)
                            : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.34 : 0.28,
                            ),
                            blurRadius: 5 * k,
                            spreadRadius: -0.5 * k,
                            offset: Offset(0, 1.6 * k),
                          ),
                        ],
                      ),
                      child: Center(
                        // Галочка проступает вместе с ходом (Opacity от t):
                        // состояние видно и без цвета, но не мелькает.
                        child: Opacity(
                          opacity: t,
                          child: Icon(
                            Icons.check_rounded,
                            size: 16 * k,
                            color: active,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
