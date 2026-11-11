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
        // Чуть длиннее прежнего: появление читается как мягкое «всплытие», а
        // не как рывок.
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (ctx, _, _) => _UpdateConfirmDialog(
          version: update.versionName,
          onConfirm: () => Navigator.pop(ctx, true),
          onCancel: () => Navigator.pop(ctx, false),
        ),
        transitionBuilder: (ctx, anim, _, child) {
          final curved = CurvedAnimation(
            parent: anim,
            // Мягкая остановка входа: окно «выплывает» и плавно встаёт на
            // место, без рывка в конце. Выход — короткий easeIn: окно уходит
            // собранно, не задерживая пользователя.
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
                  // Ход масштаба меньше (0.96): крупное окно при большом
                  // разлёте читалось «выпрыгивающим». Теперь это лёгкое
                  // всплытие, а не скачок размера.
                  scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
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
                // Ровно тот же вид, что у бейджа «Recommended» в Настройках:
                // одна альфа на два бейджа. Пользователь просил привести
                // таблетку обновления к этому виду — раньше она была заметно
                // прозрачнее и читалась «другой» плашкой.
                color: cs.primaryContainer.withValues(
                  alpha: dark ? 0.72 : 0.78,
                ),
                borderRadius: BorderRadius.circular(998),
              ),
              child: Row(
                children: [
                  SizedBox(
                    // Окно глифа с запасом: в прыжке зайчику есть куда уехать
                    // вверх, и он не «прищемляется» о край таблетки.
                    width: 18,
                    height: 18,
                    // САМОЕ ВАЖНОЕ для плавности: глиф рисуется один раз в
                    // постоянный слой (`RepaintBoundary`), а прыжок — это
                    // `Transform.translate` над готовым слоем. GPU просто
                    // переносит закэшированную растровую картинку, БЕЗ
                    // повторной растеризации глифа каждый кадр. Раньше painter
                    // слушал контроллер напрямую (`super(repaint:)`) и
                    // перерисовывал значок на КАЖДОМ кадре в новой дробной
                    // позиции — мелкий глиф мерцал и «дёргался»; в покое
                    // (не busy) слоя вообще не трогаем.
                    child: AnimatedBuilder(
                      animation: _spin,
                      // Округляем смещение до целых пикселей: дробный сдвиг
                      // заставляет растеризатор пересэмплировать кэшированный
                      // слой каждый кадр — именно это и «мылило» и дёргало
                      // мелкий глиф. Целый пиксель — чистый перенос.
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, -_hopLift(_spin.value).roundToDouble()),
                        child: child,
                      ),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          isComplex: true,
                          willChange: false,
                          painter: _RabbitGlyphPainter(
                            color: cs.onPrimaryContainer,
                          ),
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

/// Вертикальный подъём зайчика для доли цикла [t] (0…1).
///
/// Прыжок — ОДНА функция: 0 → 1 → 0. Скорость в нижних точках нулевая
/// (потолок в `sin(π·h)` и множителе `h·(1-h)`), в верхней — тоже, поэтому
/// отрыв и касание земли мягкие, без отскока. Остаток цикла зайчик стоит:
/// короткая пауза отделяет прыжки, чтобы движение читалось как прыжок, а не
/// как «молотьба».
double _hopLift(double t) {
  const hopSpan = 0.5;
  const amplitude = 4.0;
  // Чистая полуволна синуса: ровно 0 → 1 → 0 с нулевой скоростью на обоих
  // концах. Прежняя формула перемножала `h·(1-h)` и `sin(π·h)` — двойной
  // «горб» давал неровный разгон и читался дёрганым.
  final h = (t / hopSpan).clamp(0.0, 1.0);
  return math.sin(math.pi * h) * amplitude;
}

/// Значок таблетки: ЗАЙЧИК. В покое сидит, при обновлении — подпрыгивает и
/// мягко садится обратно.
///
/// Глиф рисуется векторным шрифтом иконок ([Icons.cruelty_free]) — он чёткий
/// на любом размере. Painter НЕ анимируется: он рисует значок один раз в
/// постоянный слой, а прыжок — это `Transform.translate` над готовым слоем
/// (см. `UpdatePill`), поэтому кадры прыжка не растеризуют глиф заново.
class _RabbitGlyphPainter extends CustomPainter {
  _RabbitGlyphPainter({required this.color});

  final Color color;

  /// Кэш разложенного глифа: `TextPainter.layout()` — шейпинг шрифта, и делать
  /// его каждый кадр незачем. Держим последний разложенный глиф и
  /// переиспользуем, пока не сменились цвет или размер.
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
    final tp = _glyph(color, size.shortestSide * 0.84);
    // Глиф прижат к НИЗУ окна: вверх он уезжает прыжком, и запас сверху
    // остаётся свободным. Рисуем ровно один раз — слой кэшируется.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RabbitGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xl - 1),
              // БЕЗ `BackdropFilter`: под анимацией появления/ухода размытие
              // пересобирается каждый кадр, и окно заметно МЕРЦАЕТ — ровно
              // та жалоба, что пришла на прошлый круг. Стекло делаем
              // полупрозрачной подложкой: тот же вид, но без пересборки
              // фильтра, поэтому всплытие идёт ровно.
              child: Container(
                  decoration: BoxDecoration(
                    // Полупрозрачно: сквозь окно виден фон, но текст остаётся
                    // читаемым — стекло без мерцания.
                    color: cs.surfaceContainerHigh.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(Radii.xl - 1),
                    border: Border.all(
                      color: cs.onSurface.withValues(alpha: 0.14),
                    ),
                  ),
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
                          color: cs.onSurfaceVariant,
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
                                    borderRadius: BorderRadius.circular(
                                      Radii.md,
                                    ),
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
                                    borderRadius: BorderRadius.circular(
                                      Radii.md,
                                    ),
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
