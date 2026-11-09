import 'package:flutter/material.dart';
import '../services/haptics.dart';

/// Переключатель-«стеклянная вмятина» — премиум-объём и плавный ход.
///
/// ОДИН источник движения: трек, шайба и галочка считаются от одного
/// [AnimationController] и одной кривой, поэтому все слои доезжают
/// ОДНОВРЕМЕННО — раньше трек/шайба/ядро шли разными таймингами и
/// переключатель читался «дёрганым».
///
/// ТРЕК
///   * выключен — спокойная «вмятина» в тон темы (не серая плитка);
///   * включён — фирменный градиент с мягким свечением primary.
///   * градиент и тени лерпятся по одному параметру t — фон «течёт», не скачет.
///
/// ШАЙБА
///   * выпуклый белый шарик с мягкой контактной тенью, без «ядра»-точки;
///   * во включённом проступает галочка фирменным цветом.
///   * ход тягучий (easeInOutCubic) — докатывается, а не прыгает к краю.
///
/// При переключении — короткий тактильный отклик. API прежний:
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
  /// поднято до 1.12: переключатель «объёмнее» и по нему комфортнее попадать
  /// пальцем (жалоба «переключатели мелкие»). В плотных списках уголка
  /// разработчика передают ещё крупнее.
  final double scale;

  const VolumetricSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.semanticLabel,
    this.scale = 1.12,
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

    // Выключенный трек — в тон темы: подмешиваем primaryContainer, чтобы
    // дорожка читалась как часть поверхности, а не «плавающая серая плитка».
    final trackOff = isDark
        ? Color.lerp(
            scheme.surfaceContainerHighest,
            scheme.primaryContainer,
            0.40,
          )!
        : Color.lerp(scheme.surfaceContainerHigh, scheme.primaryContainer, 0.30)!;
    final offTop = isDark ? trackOff : Color.lerp(Colors.white, trackOff, 0.30)!;
    final offBottom = isDark
        ? Color.lerp(trackOff, Colors.black, 0.14)!
        : Color.lerp(trackOff, Colors.black, 0.05)!;

    // Включённый трек: градиент «стекло» — светлей у верха → primary внизу.
    final onTop = isDark
        ? Color.lerp(active, Colors.black, 0.25)!
        : Color.lerp(Colors.white, active, 0.35)!;
    final onBottom = active;

    return Semantics(
      container: true,
      toggled: widget.value,
      enabled: widget.onChanged != null,
      label: widget.semanticLabel,
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
              // Утопленность сверху: всегда, но глубже в выключенном.
              final topShadow = Color.lerp(
                Colors.black.withValues(alpha: isDark ? 0.35 : 0.18),
                Colors.black.withValues(alpha: 0.22),
                t,
              )!;
              // Свечение primary: 0 в выключенном → сильное во включённом.
              final glow = active.withValues(alpha: 0.35 * t);

              return Container(
                width: 54 * k,
                height: 32 * k,
                padding: EdgeInsets.all(3 * k),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16 * k),
                  // Градиент ВСЕГДА на месте, цвета лерпятся — фон «течёт».
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(offTop, onTop, t)!,
                      Color.lerp(offBottom, onBottom, t)!,
                    ],
                  ),
                  // Список теней ВСЕГДА из двух позиций — длина не прыгает,
                  // AnimatedBuilder лерпит только alpha/blur.
                  boxShadow: [
                    BoxShadow(
                      color: topShadow,
                      blurRadius: 3 * k,
                      spreadRadius: 0.5 * k,
                      offset: Offset(0, -1.5 * k),
                    ),
                    BoxShadow(
                      color: glow,
                      blurRadius: 14 * k,
                      spreadRadius: -2 * k,
                      offset: Offset.zero,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Днище-«дорожка»: тонкая светлая полоса снизу читается
                    // как стеклянное дно вмятины.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: 0.16,
                            widthFactor: 0.72,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6 * k),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.white.withValues(
                                      alpha: isDark
                                          ? 0.05 + 0.17 * t
                                          : 0.28 - 0.06 * t,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Шайба-«шарик»: белая сфера с контактной тенью и
                    // проступающей галочкой. Ход считается от той же t —
                    // шайба едет ровно как фон.
                    Align(
                      alignment: Alignment.lerp(
                        Alignment.centerLeft,
                        Alignment.centerRight,
                        t,
                      )!,
                      child: Container(
                        width: 26 * k,
                        height: 26 * k,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: const Alignment(-0.42, -0.46),
                            radius: 1.35,
                            colors: isDark
                                ? const [Color(0xFFE8E8EC), Color(0xFFB9BCC4)]
                                : const [Colors.white, Color(0xFFD9DAE0)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.28 : 0.30,
                              ),
                              blurRadius: 5 * k,
                              spreadRadius: -0.5 * k,
                              offset: Offset(0, 1.5 * k),
                            ),
                            // Световой ободок только в светлой теме: в тёмной
                            // он читался «блестящей точкой».
                            if (!isDark)
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.60),
                                blurRadius: 1 * k,
                                spreadRadius: -0.8 * k,
                                offset: Offset(0, -1 * k),
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
