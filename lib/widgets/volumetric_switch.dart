import 'package:flutter/material.dart';
import '../services/haptics.dart';

/// Переключатель-«стеклянная вмятина» — премиум-объём:
///
/// ТРЕК (дорожка)
///   * всегда слегка «вдавлен в экран»: внутренний тоннель сверху +
///     мягкий контакт снизу — в выключенном состоянии это утопленная
///     стеклянная колбаса, а не плоская подложка;
///   * во включённом: трек заливается фирменным градиентом (светлее у
///     верхнего края → чистый primary к низу) и подсвечен снаружи
///     мягким свечением primary — переключатель «горит», но спокойно.
///
/// ШАЙБА
///   * выпуклый стеклянный шарик: радиальный блик в левом верхнем углу,
///     лёгкое затемнение к нижнему краю (сфера), короткая контактная
///     тень под шариком;
///   * в выключенном — серое «ядро»-точка в центре (состояние видно даже
///     без цвета), во включённом — ядро наливается фирменным цветом;
///   * ход шайбы «тягучий» (500 мс, easeOutCubic) — не прыгает к краю,
///     а докатывается.
///
/// При переключении — короткий тактильный отклик. API прежний:
/// [VolumetricSwitch(value:, onChanged:, activeColor:, scale:)].
class VolumetricSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;

  /// Масштаб трека/шайбы. 1.0 — стандартный (54×32). В плотных списках
  /// уголка разработчика берём крупнее — переключатель «объёмнее» и по
  /// нему комфортнее попадать пальцем.
  final double scale;

  const VolumetricSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = activeColor ?? scheme.primary;
    final k = scale;

    // ── Цвета трека ─────────────────────────────────────────────────
    final trackOff = isDark
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.9)
        : scheme.surfaceContainerHighest;

    // Включённый трек: градиент «стекло»: светлей у верха → primary
    // внизу. На тёмной теме светлей берём из самого primary, чтобы
    // не выбеливать (белый лерп по тёмному контейнеру).
    final trackTop = isDark
        ? Color.lerp(active, Colors.black, 0.25)!
        : Color.lerp(Colors.white, active, 0.35)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null
          ? null
          : () {
              Haptics.select();
              onChanged!(!value);
            },
      child: AnimatedContainer(
        // Заливка/свечение трека — тягучее «разгорание» (500 мс): свет
        // наполняет вмятину, а не щёлкает.
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
        width: 54 * k,
        height: 32 * k,
        padding: EdgeInsets.all(3 * k),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16 * k),
          color: value ? active : trackOff,
          gradient: value
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [trackTop, active],
                )
              : null,
          boxShadow: [
            // Утопленность: тёмный «тоннель» сверху (отдельная тень с
            // отрицательным сдвигом) — трек читается вмазанным в экран,
            // а не лежащим на нём. Без `inset` (в этой версии Flutter
            // у BoxShadow его нет): эффект тот же — полоса затенения
            // у верхнего края.
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: value ? 0.22 : (isDark ? 0.35 : 0.18)),
              blurRadius: 3 * k,
              spreadRadius: 0.5 * k,
              offset: Offset(0, -1.5 * k),
            ),
            // Мягкое основание: в выключенном — короткий контакт,
            // трек выглядит наклеенным изнутри.
            if (!value)
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.10),
                blurRadius: 4 * k,
                spreadRadius: -1 * k,
                offset: Offset(0, 1.5 * k),
              ),
            // Свечение: во включённом трек «горит» — широкий цветной
            // ореол вокруг колбасы (не под ней, а по контуру).
            if (value)
              BoxShadow(
                color: active.withValues(alpha: 0.35),
                blurRadius: 14 * k,
                spreadRadius: -2 * k,
                offset: const Offset(0, 0),
              ),
          ],
        ),
        child: Stack(
          children: [
            // Днище-«дорожка» внутри трека: тонкая светлая полоса снизу —
            // читается как стеклянное дно вмятины (поверх обоих состояний).
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
                            Colors.white
                                .withValues(
                                    alpha: value ? 0.22 : (isDark ? 0.05 : 0.28)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Шайба-«шарик» с тягучим докатом.
            AnimatedAlign(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: RepaintBoundary(
                child: Container(
                  width: 26 * k,
                  height: 26 * k,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Сфера: блик в левом верхнем углу → почти белая
                    // к низу с лёгким серым (тень сферического шара).
                    gradient: RadialGradient(
                      center: const Alignment(-0.42, -0.46),
                      radius: 1.35,
                      colors: [
                        Colors.white,
                        Color.lerp(
                            Colors.white, isDark ? Color(0xFFB9BCC4) : Color(0xFFD9DAE0), 0.55)!,
                      ],
                    ),
                    // Контактная тень под шариком — шарик не «впарен
                    // в стену», а лежит в дорожке с зазором.
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.42 : 0.30),
                        blurRadius: 5 * k,
                        spreadRadius: -0.5 * k,
                        offset: Offset(0, 1.5 * k),
                      ),
                      // Тонкий световой ободок по верхней кромке шара —
                      // дополнительный блик стеклянной оболочки.
                      BoxShadow(
                        color: Colors.white.withValues(alpha: isDark ? 0.20 : 0.60),
                        blurRadius: 1 * k,
                        spreadRadius: -0.8 * k,
                        offset: Offset(0, -1 * k),
                      ),
                    ],
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      // Ядро-точка в центре шарика: серое в выключенном
                      // (состояние видно и без цвета), наливается
                      // фирменным с мягким свечением во включённом.
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      width: (value ? 10 : 8) * k,
                      height: (value ? 10 : 8) * k,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value
                            ? active
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.45)
                                : scheme.onSurfaceVariant
                                    .withValues(alpha: 0.55)),
                        boxShadow: value
                            ? [
                                BoxShadow(
                                  color: active.withValues(alpha: 0.6),
                                  blurRadius: 4 * k,
                                  spreadRadius: 0.5 * k,
                                ),
                              ]
                            : const [],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
