import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../main.dart' show preDecodedLogo;

class SplashScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const SplashScreen({super.key, this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    // Очень плавное появление: мягкое проявление + лёгкий рост масштаба.
    // БЕЗ смещения-«прыжка» сверху — аватарка не дёргается ни при первом
    // запуске, ни после PIN (на слабых телефонах slide сверху выглядел
    // как резкий скачок из-за просадок кадров).
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.85, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );
    _controller.forward();
    // Заранее прогреваем кэш логотипа: первый кадр после сплэша
    // не «мигает» и не показывает пустое место. PrcacheImage сам
    // отработает, когда у него будет MediaQuery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/keramika.png'), context);
    });
    // Анимация идёт 2 секунды; переходим на главную сразу после её
    // окончания (раньше лишняя секунда «мёртвой паузы» ощущалась как
    // тормоз входа — фоновые загрузки сервисов к этому моменту уже
    // завершены).
    _splashTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) widget.onDone?.call();
    });
    // Разрешения больше не запрашиваем автоматически.
    // Пользователь сам включает их в настройках приложения.
    // Это предотвращает:
    //  — вылет в системные настройки точных будильников при первом запуске
    //  — "двойной запуск" при возврате из системных настроек
    //  — включённые уведомления без ведома пользователя
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Цвет обводки логотипа — primary выбранной темы (rose/peach/grok/...).
    final accent = theme.colorScheme.primary;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [Colors.grey[900]!, Colors.black87]
                : [Colors.white, Colors.grey[100]!],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Логотип крупным планом, без «коробки» и без обрезки
                          // (contain) — текст внутри картинки читается чётко.
                          // Вокруг — красивая полупрозрачная обводка в цвет
                          // ВЫБРАННОЙ темы (primary из ColorScheme): rose → розовая,
                          // peach → персиковая, grok → её акцент и т.д. Смотрится
                          // дорого и на светлом, и на тёмном фоне.
                          // Заранее прогреваем кэш, чтобы логотип не «мигал»
                          // и не появлялся не сразу на слабых телефонах вроде
                          // Redmi Note 12 — первый кадр сразу рисуется с ним.
                          // Логотип крупным планом, с прогретым кэшем
                          // из initState сразу выезжает на первый кадр.
                          // RepaintBoundary кэширует отрисованную аватарку
                          // текстурой: во время slide/fade-анимации (1800мс)
                          // движется готовый растр, а не перефильтровывается
                          // большая картинка каждый кадр — на слабых
                          // телефонах аватарка не «дёргается».
                          RepaintBoundary(
                            child: Container(
                              width: 258,
                              height: 258,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                // «Скруглый» (squircle) — круглее квадрата, но
                                // НЕ круг: нижняя подпись на логотипе не
                                // обрезается кружком и остаётся читаемой.
                                borderRadius: BorderRadius.circular(72),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(
                                      alpha: isDark ? 0.10 : 0.92,
                                    ),
                                    accent.withValues(
                                      alpha: isDark ? 0.20 : 0.12,
                                    ),
                                  ],
                                ),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.62),
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.28),
                                    blurRadius: 30,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.28 : 0.08,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 9),
                                  ),
                                ],
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(62),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(58),
                                  // Логотип уже декодирован в main() до первого
                                  // кадра — RawImage рисует его мгновенно, без
                                  // «мигания» и подгрузки на слабых телефонах.
                                  child: preDecodedLogo != null
                                      ? RawImage(
                                          image: preDecodedLogo,
                                          width: 238,
                                          height: 238,
                                          fit: BoxFit.contain,
                                          filterQuality: FilterQuality.high,
                                        )
                                      : Image.asset(
                                          'assets/keramika.png',
                                          width: 238,
                                          height: 238,
                                          cacheWidth: 1024,
                                          cacheHeight: 1024,
                                          filterQuality: FilterQuality.high,
                                          isAntiAlias: true,
                                          fit: BoxFit.contain,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Оригинал сплэша: сначала название «Keramika»
                          // (тёмно-серое/светло-серое), потом розовое «FOSS 1.2».
                          // Именно так показывала прошлая версия — пользователь
                          // привык к этому порядку и просил вернуть.
                          Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Keramika ',
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFFEEEEEE)
                                        : const Color(0xFF424242),
                                  ),
                                ),
                                TextSpan(
                                  text: 'FOSS $appVersion',
                                  // Маленькая жирность для читаемости на
                                  // светлом фоне, плюс лёгкая тень в тёмной
                                  // теме, чтобы подпись «не сливалась».
                                  style: const TextStyle(
                                    color: Color(0xFFF06292),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Text(
                    'by Wetidom',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      // Читаемая подпись: заметнее, чем был бледный grey[400].
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                      letterSpacing: 3,
                    ),
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
