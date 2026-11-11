import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/installer.dart';
import '../services/update_service.dart';
import '../utils/design_tokens.dart';
import '../utils/snackbar.dart';
import 'press_scale.dart';

/// Компактная таблетка «Обновления» рядом с версией в
/// Настройках.
///
/// По тапу: тихо проверяет GitHub-релиз; если версия новее — спрашивает
/// подтверждение, затем скачивает APK (показывая прогресс прямо в таблетке) и
/// запускает системную установку («предложить установить»). Если обновления
/// нет — тихо сообщает, что версия последняя.
class UpdatePill extends StatefulWidget {
  const UpdatePill({super.key});

  @override
  State<UpdatePill> createState() => _UpdatePillState();
}

class _UpdatePillState extends State<UpdatePill>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy) return;
    Haptics.light();
    setState(() => _busy = true);
    _spin.repeat();
    try {
      final info = await Installer.appInfo();
      if (!mounted) return;
      if (info == null) {
        _toast(
          Translations.t(
            'updateAndroidOnly',
            context,
            'Обновления доступны только в Android-сборке',
          ),
        );
        return;
      }
      final abi = await Installer.supportedAbi();
      final update = await UpdateService.instance.check(
        abi: abi,
        currentVersionCode: info.versionCode,
        currentVersionName: info.versionName,
      );
      if (!mounted) return;
      if (update == null) {
        pendingUpdate.value = null;
        final latestMsg = Translations.t(
          'updateLatest',
          context,
          'У вас последняя версия',
        );
        _toast('$latestMsg · v${info.versionName}');
        return;
      }
      pendingUpdate.value = update;
      if (!UpdateService.hasValidSha256(update.sha256)) {
        _toast(
          Translations.t(
            'updateHashMissing',
            context,
            '\u0423 \u0440\u0435\u043b\u0438\u0437\u0430 \u043d\u0435\u0442 \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u043d\u043e\u0433\u043e SHA-256. \u0423\u0441\u0442\u0430\u043d\u043e\u0432\u043a\u0430 \u043e\u0442\u043c\u0435\u043d\u0435\u043d\u0430.',
          ),
        );
        return;
      }

      // Спрашиваем разрешение ПЕРЕД загрузкой: пользователь просил, чтобы
      // приложение не ставило обновление само, а сначала предложило. Диалог
      // заменяет прежнюю «тихую» загрузку — согласие явное.
      final confirmed = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        // Барьер ПРОЗРАЧНЫЙ, а не чёрный: штатный барьер маршрута не участвует
        // в анимации и вспыхивает/гаснет мгновенно — фон «мигает» чёрным.
        // Затемнение рисует сам transitionBuilder той же кривой, что и окно
        // (как в локскрине и новогоднем баннере).
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, _) => _UpdateConfirmDialog(
          version: update.versionName,
          onConfirm: () => Navigator.pop(ctx, true),
          onCancel: () => Navigator.pop(ctx, false),
        ),
        transitionBuilder: (ctx, anim, _, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final theme = Theme.of(ctx);
          final dim = (theme.brightness == Brightness.dark
                  ? Colors.black
                  : theme.colorScheme.surface)
              .withValues(alpha: 0.30 * curved.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Затемнение едет ВМЕСТЕ с окном: проявляется и гаснет плавно,
              // без мгновенной вспышки барьера.
              IgnorePointer(child: ColoredBox(color: dim)),
              FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
                  child: child,
                ),
              ),
            ],
          );
        },
      );
      if (!mounted || confirmed != true) {
        pendingUpdate.value = null;
        return;
      }

      // Качаем после согласия.
      final path = await UpdateService.instance.download(update);
      if (!mounted) return;
      if (path == null) {
        _toast(
          Translations.t(
            'updateDownloadFailed',
            context,
            'Не удалось скачать обновление',
          ),
        );
        return;
      }

      // Android не даст тихой установки: сперва проверяем право источника.
      final can = await Installer.canInstall();
      if (!can) {
        await Installer.openInstallSettings();
        if (!mounted) return;
        _toast(
          Translations.t(
            'updateAllowSource',
            context,
            'Разрешите установку из этого источника и нажмите снова',
          ),
        );
        return;
      }

      final ok = await Installer.installApk(
        path,
        expectedSha256: update.sha256,
      );
      if (!mounted) return;
      if (!ok) {
        _toast(
          Translations.t(
            'updateInstallFailed',
            context,
            'Не удалось запустить установку',
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _toast(Translations.t('updateError', context, 'Ошибка обновления'));
    } finally {
      if (mounted) {
        _spin.stop();
        _spin.value = 0;
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: message,
      icon: Icons.system_update_alt,
      groupKey: 'update',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final badgeTextStyle =
        (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
          fontWeight: FontWeight.w800,
        );
    final recommendedMeasure = TextPainter(
      text: TextSpan(text: 'Recommended', style: badgeTextStyle),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    // +2 — на толщину градиентного кольца (padding 1 с каждой стороны),
    // чтобы содержимое не сжималось относительно прежнего размера.
    final badgeWidth = (recommendedMeasure.width + 18).ceilToDouble() + 2;
    final badgeHeight = (recommendedMeasure.height + 8).ceilToDouble() + 2;
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: pendingUpdate,
      builder: (context, update, _) {
        return GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          // Обводка-кольцо как у снекбара: тонкий градиентный край
          // (акцент → третичный) вместо плоской каймы — мягкий перелив по
          // периметру. Кольцо — внешний контейнер, фон — полупрозрачный
          // primaryContainer, сквозь который виден фон строки настроек.
          child: Container(
            height: badgeHeight,
            width: badgeWidth,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  cs.primary.withValues(alpha: dark ? 0.60 : 0.45),
                  cs.primary.withValues(alpha: dark ? 0.12 : 0.10),
                  cs.tertiary.withValues(alpha: dark ? 0.48 : 0.30),
                ],
                stops: const <double>[0, 0.55, 1],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                // Полупрозрачный фон, как у снекбара: сквозь таблетку виден
                // фон строки настроек, плашка «сидит» на нём, а не накрывает
                // его плотным прямоугольником.
                color: cs.primaryContainer.withValues(
                  alpha: dark ? 0.72 : 0.78,
                ),
                borderRadius: BorderRadius.circular(998),
              ),
              child: Row(
                children: [
                  SizedBox(
                    // Окно глифа чуть больше самого глифа: в прыжке у зайчика
                    // остаётся запас сверху, и он не «прищемляется» о край
                    // таблетки (это и читалось как рывок в верхней точке).
                    width: 15,
                    height: 15,
                    child: AnimatedBuilder(
                      animation: _spin,
                      builder: (context, _) => CustomPaint(
                        painter: _UpdateGlyphPainter(
                          progress: _busy ? _spin.value : 0,
                          color: cs.onPrimaryContainer,
                          hole: cs.primaryContainer,
                          running: _busy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Обновление',
                        maxLines: 1,
                        softWrap: false,
                        style: badgeTextStyle.copyWith(
                          fontSize: 10,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Значок таблетки: ЗАЙЧИК. В покое сидит, при обновлении — прыгает:
/// мягко поднимается и «садится» с приседанием (squash & stretch), поэтому
/// движение читается как прыжок, а не как вращение или полёт ракеты.
///
/// Глиф рисуется векторным шрифтом иконок ([Icons.cruelty_free]) — он чёткий
/// на любом размере (никакого «мыла» растрового холста), а прыжок — чистая
/// трансформация вокруг центра. Цикл замкнут (sin(π·p): 0→1→0), поэтому на
/// стыке 1→0 нет рывка.
class _UpdateGlyphPainter extends CustomPainter {
  const _UpdateGlyphPainter({
    required this.progress,
    required this.color,
    required this.hole,
    required this.running,
  });

  final double progress;
  final Color color;

  /// Цвет «окна» — фон таблетки. Оставлен для совместимости: у зайчика
  /// сквозных деталей нет, глиф залит целиком.
  final Color hole;
  final bool running;

  /// Доля цикла, которую занимает сам прыжок. Остаток зайчик стоит на земле:
  /// короткая пауза отделяет прыжки друг от друга, чтобы движение читалось
  /// как прыжок, а не как непрерывная «молотьба».
  static const double _hopSpan = 0.58;

  /// Кэш разложенного глифа. `TextPainter.layout()` — это шейпинг шрифта, и
  /// делать его КАЖДЫЙ кадр анимации (60–120 Гц) — лишняя работа: на слабых
  /// устройствах кадры проседали, и прыжок читался дёрганым. Держим последний
  /// разложенный глиф и переиспользуем, пока не сменились цвет или размер.
  static TextPainter? _cached;
  static Color? _cachedColor;
  static double _cachedSize = 0;

  static TextPainter _glyph(Color color, double fontSize) {
    final cached = _cached;
    if (cached != null && _cachedColor == color && _cachedSize == fontSize) {
      return cached;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.cruelty_free.codePoint),
        style: TextStyle(
          // Глиф заметно меньше окна: при прыжке у него остаётся запас, и он
          // не упирается в границы таблетки.
          fontSize: fontSize,
          fontFamily: Icons.cruelty_free.fontFamily,
          package: Icons.cruelty_free.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _cached = tp;
    _cachedColor = color;
    _cachedSize = fontSize;
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = running ? progress : 0.0;
    // Профиль прыжка: половина синуса — мягкий подъём и такое же мягкое
    // приземление (скорость нулевая на обоих концах). Сверху — `easeInOutSine`
    // (самая мягкая из easeInOut-кривых), поэтому разгон плавный, без
    // «ступеньки» в начале и рывка в конце.
    final hp = (p / _hopSpan).clamp(0.0, 1.0);
    final u = Curves.easeInOutSine.transform(hp);
    final hop = running ? math.sin(math.pi * u) : 0.0;
    // Деформация мягкая и симметричная: в полёте зайчик чуть вытягивается
    // вверх, у «земли» — чуть приседает. Прежнее сплющивание ниже единицы
    // выглядело как «зайчика прищемило»; теперь форма возвращается к кругу.
    final scaleY = 1 + hop * 0.05;
    final scaleX = 1 - hop * 0.03;
    // Прыжок ниже: высокий подскок в маленькой таблетке читался как рывок.
    final lift = hop * size.height * 0.12;

    final tp = _glyph(color, size.shortestSide * 0.84);
    canvas.save();
    // Подъём и приземление — по ОДНОЙ плавной кривой `hop` (уже easeInOutSine),
    // без отдельной «отбивки» у земли: вторая кривая давала рывок в нижней
    // точке. `translate` идёт по непрерывному hop, поэтому касание земли
    // такое же мягкое, как и отрыв.
    canvas.translate(size.width / 2, size.height / 2 - lift);
    canvas.scale(scaleX, scaleY);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UpdateGlyphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.hole != hole ||
      oldDelegate.running != running;
}

/// Окно подтверждения обновления.
///
/// Вместо системного [AlertDialog]: своя карточка со скруглением, мягкая
/// полупрозрачная обводка, текст подписи курсивом, а кнопки «отдать» при
/// нажатии ([PressScale]) и «подтвердить» — залитая акцентом с плавной
/// отдачей. Появление — всплытие с лёгким масштабом (см. [showGeneralDialog]).
class _UpdateConfirmDialog extends StatelessWidget {
  final String version;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _UpdateConfirmDialog({
    required this.version,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            // Полупрозрачная градиентная обводка: акцент → прозрачность, как
            // у «стеклянных» плашек приложения.
            padding: const EdgeInsets.all(1.2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  cs.primary.withValues(alpha: 0.55),
                  cs.primary.withValues(alpha: 0.08),
                  cs.tertiary.withValues(alpha: 0.40),
                ],
                stops: const <double>[0, 0.55, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Container(
              // Полупрозрачная подложка БЕЗ `BackdropFilter`: под анимацией
              // появления/ухода размытие пересобиралось каждый кадр и окно
              // «мигало» (та же грабля, что у снекбара). Прозрачность даёт
              // стеклянный тон.
              decoration: BoxDecoration(
                // «Стекло» той же семьи, что у снекбара, но чуть прозрачнее:
                // сквозь окно должно быть видно приложение, иначе полупрозрачный
                // фон читается как непрозрачный.
                color: cs.primaryContainer.withValues(
                  alpha: cs.brightness == Brightness.dark ? 0.58 : 0.64,
                ),
                borderRadius: BorderRadius.circular(Radii.xl - 1),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primary.withValues(alpha: 0.16),
                          ),
                          child: Icon(
                            Icons.system_update_alt_rounded,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            Translations.t(
                              'updateAvailable',
                              context,
                              'Доступно обновление',
                            ),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: Weights.bold,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      Translations.t(
                        'updateAvailableBody',
                        context,
                        'Установить v{v}?',
                      ).replaceAll('{v}', version),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.84),
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: PressScale(
                            pressedScale: 0.95,
                            child: TextButton(
                              onPressed: onCancel,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                              ),
                              child: Text(
                                Translations.t('cancel', context, 'Отмена'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: PressScale(
                            pressedScale: 0.95,
                            child: FilledButton(
                              onPressed: onConfirm,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                              ),
                              child: Text(
                                Translations.t(
                                  'install',
                                  context,
                                  'Установить',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
