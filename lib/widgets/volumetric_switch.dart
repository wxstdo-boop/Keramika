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
    // Свитчи живут внутри карточек (surfaceContainerLow). Тренок в ВЫКЛ
    // берёт средний surfaceContainer (между card и Highest) и слегка
    // «уплывает» в поверхность (alpha 0.5) — не «плавающая серая плитка»
    // (жалоба «не вписывается»), а вмятина в том же материале. Включённый
    // — фирменный градиент.
    final trackOff = isDark
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.55)
        : scheme.surfaceContainer.withValues(alpha: 0.6);

    // Включённый трек: градиент «стекло»: светлей у верха → primary
    // внизу. На тёмной теме светлей берём из самого primary, чтобы
    // не выбеливать (белый лерп по тёмному контейнеру).
    final trackTop = isDark
        ? Color.lerp(active, Colors.black, 0.25)!
        : Color.lerp(Colors.white, active, 0.35)!;

    // КРИТИЧНО: в ОБОИХ состояниях у трека есть реальный градиент
    // (Light/Dark в один и тот же набор точек). Раньше выключенный трек
    // имел `gradient: null` + сплошную `color`, а включённый — градиент:
    // AnimatedContainer НЕ может интерполировать `null` → `gradient`, и
    // фон трека СКАЧИЛ (заезжал) в первый же кадр переключения. Теперь
    // градиент всегда на месте и лерпится по цветам — фон «течёт».
    final offTop = isDark
        ? trackOff
        : Color.lerp(Colors.white, trackOff, 0.30)!;
    final offBottom = isDark
        ? Color.lerp(trackOff, Colors.black, 0.14)!
        : Color.lerp(trackOff, Colors.black, 0.05)!;
    final onTop = trackTop;
    final onBottom = active;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged == null
          ? null
          : () {
              Haptics.select();
              onChanged!(!value);
            },
      child: AnimatedContainer(
        // Заливка/свечение трека. ПЛАВНОСТЬ ДЕРЖИТСЯ НА ОДНОМ ДОЛЖНОСТИ:
        // трек, шайба и ядро должны ехать ОДНАКОВО (одна длительность +
        // одна кривая). Раньше трек шёл 500 мс easeInOutCubic, а ядро —
        // 420 мс easeOutCubic: фон и ядро доезжали в разное время — из-за
        // этого переключатель «неплавня/подтормаживал» (фон отстаёт от
        // шайбы). Теперь всё 280 мс easeOutCubic — коротко и без рывка.
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: 54 * k,
        height: 32 * k,
        padding: EdgeInsets.all(3 * k),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16 * k),
          // ВСЕГДА градиент (никогда `null`): AnimatedContainer плавно
          // лерпит цвет по цветам — фон трека течёт, а не скачет.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              value ? onTop : offTop,
              value ? onBottom : offBottom,
            ],
          ),
          // КРИТИЧНО: список теней ВСЕГДА из 3-х позиций в обоих состояниях.
          // Раньше «контакт» и «свечение» висели в different branch'ах
          // (if (!value) / if (value)), и при переключении длина списка
          // прыгала 2↔3 — AnimatedContainer НЕ умеет интерполировать
          // differently-shaped boxShadow list и СКАЧИЛ теньми (то самое
          // «фон неплавно/дёргано сменяется»). Теперь 3 всегда, различаются
          // только alpha — лерп идёт по каждому полю.
          // Свитчи живут в карточках: тени ВНЕШНЕГО трека (тоннель + контакт)
          // держим минимальными в ВЫКЛ — «уплывший в материал» трек, а не
          // «плавающий квадрат с тенью». При вкл контакт гаснет, остаётся
          // только фирменное свечение primary.
          boxShadow: [
            // 1) Утопленность: тёмный «тоннель» сверху — в ВКЛ (дорожка
            // стала «внутрь»), в ВЫКЛ почти не видна.
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: value ? 0.22 : (isDark ? 0.14 : 0.06)),
              blurRadius: 3 * k,
              spreadRadius: 0.5 * k,
              offset: Offset(0, -1.5 * k),
            ),
            // 2) Контактное основание: в ВЫКЛ едва заметное, в ВКЛ 0.
            BoxShadow(
              color: Colors.black.withValues(
                alpha: value ? 0.0 : (isDark ? 0.10 : 0.04),
              ),
              blurRadius: 4 * k,
              spreadRadius: -1 * k,
              offset: Offset(0, 1.5 * k),
            ),
            // 3) Свечение primary: 0 в ВЫКЛ, сильное в ВКЛ.
            BoxShadow(
              color: active.withValues(alpha: value ? 0.35 : 0.0),
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
              // ШАЙБА ЕДЕТ РОВНО ТАК ЖЕ, КАК ФОН: та же длительность (280)
              // и та же кривая (easeOutCubic). Раньше шайба шла 500 мс, а
              // фон 500 easeInOutCubic — два разных тайминга расходились,
              // и шайба «догоняла» свой край позже/раньше фона (дёрганье).
              // Теперь они синхронны.
              duration: const Duration(milliseconds: 280),
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
                    // Тёмная тема: шарик НЕ должен быть «лампочкой». Раньше
                    // ядро шло чистым белым (Colors.white) + белый ободок —
                    // на тёмном фоне это читалось «блестящим говном» (яркая
                    // точка-прожектор). Теперь в тёмной теме шарик — мягкий
                    // тёплый серо-белый, блик приглушён, ободка нет: шайба
                    // выглядит матовой, а не залитой светом.
                    gradient: RadialGradient(
                      center: const Alignment(-0.42, -0.46),
                      radius: 1.35,
                      colors: isDark
                          ? [
                              // Матовый светлый верх (не чистый белый),
                              // уходит в серую середину — без «лампы».
                              const Color(0xFFE8E8EC),
                              const Color(0xFFB9BCC4),
                            ]
                          : [
                              Colors.white,
                              const Color(0xFFD9DAE0),
                            ],
                    ),
                    // Контактная тень под шариком — шарик не «впарен
                    // в стену», а лежит в дорожке с зазором.
                    // В тёмной теме тень мягче (тёмный фон её и так
                    // читается), в светлой — заметнее.
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.28 : 0.30),
                        blurRadius: 5 * k,
                        spreadRadius: -0.5 * k,
                        offset: Offset(0, 1.5 * k),
                      ),
                      // Световой ободок только в СВЕТлой теме: в тёмной он
                      // и есть та самая «блестящая точка» — убираем.
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
                    child: AnimatedContainer(
                      // Ядро-точка в центре шарика: серое в выключенном
                      // (состояние видно и без цвета), наливается
                      // фирменным с мягким свечением во включённом.
                      // Та же длительность/кривая, что и у шайбы и фона
                      // (280 мс easeOutCubic) — все три слоя доезжают
                      // ОДНОВРЕМЕННО, без рассинхрона.
                      duration: const Duration(milliseconds: 280),
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
                        // Ядро-точка: в тёмной теме свечение слабее, чем в
                        // светлой — иначе яркая точка на тёмном фоне
                        // «блистает и отдаёт говном» (тот же прожектор,
                        // что и у шайбы). В светлой — мягкое фирменное.
                        boxShadow: [
                          if (value)
                            BoxShadow(
                              color: active.withValues(
                                alpha: isDark ? 0.32 : 0.6,
                              ),
                              blurRadius: 4 * k,
                              spreadRadius: 0.5 * k,
                            ),
                        ],
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
