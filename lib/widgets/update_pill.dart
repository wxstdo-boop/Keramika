import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/installer.dart';
import '../services/update_service.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import '../utils/snackbar.dart';
import 'agysha_bunny.dart';
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
    // Один полный цикл «дыхания» значка. Медленно и вечно: значок живёт, а
    // не дёргается — покой читается спокойным.
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    // Вечный цикл, а НЕ только на время загрузки: таблетка сама приглашает
    // тапнуть, поэтому значок живёт всегда. Уважаем «убрать анимации» —
    // тогда значок стоит.
    if (!MotionPrefs.shouldReduceMotion) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy) return;
    Haptics.light();
    setState(() => _busy = true);
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
        // Затемнение — ОДНИМ барьером маршрута с мягкой альфой. Раньше барьер
        // был прозрачным, а затемнение рисовал transitionBuilder: два слоя
        // складывались, и на входе/выходе окно «вспыхивало» (та самая
        // жалоба на мигание). Теперь слой ровно один и он же плавно гаснет.
        barrierColor: Colors.black.withValues(alpha: 0.42),
        // Длиннее прежнего: окно читается как мягкое всплытие, без рывка.
        transitionDuration: const Duration(milliseconds: 360),
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
          // Только окно: фон затемняет барьер маршрута, поэтому второго
          // затемняющего слоя нет — окно не «вспыхивает» на переходе.
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              // Ход масштаба меньше (0.96): крупное окно при большом разлёте
              // читалось «выпрыгивающим». Теперь это лёгкое всплытие.
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
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
        // Вечный цикл НЕ трогаем: значок «дышит» и до, и после тапа.
        // Сброс `_spin.value` здесь останавливал бы контроллер (сеттер
        // `value` зовёт `stop()`), поэтому фазу не сбрасываем — на
        // непрерывном «дыхании» это не видно.
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
                    // Окно глифа с запасом: в «дыхании» значку есть куда
                    // подняться, и он не «прищемляется» о край таблетки.
                    width: 18,
                    height: 18,
                    // САМОЕ ВАЖНОЕ для плавности: глиф рисуется один раз в
                    // постоянный слой (`RepaintBoundary`), а «дыхание» — это
                    // `Transform` над готовым слоем. GPU просто переносит
                    // закэшированную растровую картинку, БЕЗ повторной
                    // растеризации глифа каждый кадр.
                    child: AnimatedBuilder(
                      animation: _spin,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, _bobLift(_spin.value)),
                        child: Transform.scale(
                          scale: _bobScale(_spin.value),
                          child: child,
                        ),
                      ),
                      child: RepaintBoundary(
                        // Значок Agysha — свой зайчик вместо системной
                        // «стрелки обновления»: чужеродная иконка в мелком
                        // размере сливалась в пятно.
                        child: AgyshaBunny(size: 18, color: cs.onPrimaryContainer),
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

/// Вертикальный подъём значка для доли цикла [t] (0…1).
///
/// «Дыхание» — ОДНА гладкая функция 0 → 1 → 0 на всём цикле: в начале и в
/// конце цикла значение и его производная равны нулю, поэтому вечный цикл
/// замкнут БЕЗ рывка на стыке. Ровно один «вдох» за цикл (косинус), а не
/// два — движение читается спокойным покачиванием.
double _bobLift(double t) {
  // (1 − cos 2πt)/2: 0 в t=0, 1 в t=0.5, 0 в t=1. Производная = π·sin(2πt)
  // тоже нулевая на обоих концах — стык цикла бесшовный. Знак минус — значок
  // ВСПЛЫВАЕТ в середине цикла; амплитуда в пиксель с небольшим: глиф живёт
  // внутри узкой таблетки и не должен задевать её край.
  return -(1 - math.cos(t * 2 * math.pi)) / 2 * 1.5;
}

/// Лёгкое «дыхание» размера: тот же ход, что у подъёма, но чуть отстаёт по
/// фазе — значок не «пружинит» одной частотой, а мягко набухает в верхней
/// точке. Оба конца цикла замкнуты (cos), поэтому стык не щёлкает.
double _bobScale(double t) {
  return 1 + 0.055 * ((1 - math.cos(t * 2 * math.pi)) / 2);
}

/// Окно подтверждения обновления.
///
/// Вместо системного [AlertDialog]: своя карточка со скруглением, кант в
/// красном бренда (полупрозрачный, как у клавиатуры), текст подписи курсивом,
/// а кнопки «отдать» при нажатии ([PressScale]) и «подтвердить» — залитая
/// акцентом с плавной отдачей. Значок в медальоне — свой зайчик Agysha
/// ([AgyshaBunny]), который «дышит» вечным циклом.
class _UpdateConfirmDialog extends StatefulWidget {
  final String version;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _UpdateConfirmDialog({
    required this.version,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_UpdateConfirmDialog> createState() => _UpdateConfirmDialogState();
}

class _UpdateConfirmDialogState extends State<_UpdateConfirmDialog>
    with SingleTickerProviderStateMixin {
  /// Вечное «дыхание» зайчика в медальоне: тот же замкнутый косинус, что и у
  /// значка таблетки, — цикл бесшовный на стыке.
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (!MotionPrefs.shouldReduceMotion) _bob.repeat();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

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
            // Кант — ПОЛУПРОЗРАЧНЫЙ КРАСНЫЙ бренда, как у клавиатуры: раньше
            // кромка шла градиентом primary→tertiary (на дефолтной палитре
            // сиреневым) и окно выбивалось из «кровавой» семьи. Теперь один
            // алый тон с мягкой альфой — то же «стекло», что у панели ввода.
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.red.withValues(alpha: 0.55),
                  BrandColors.red.withValues(alpha: 0.22),
                  BrandColors.red.withValues(alpha: 0.46),
                ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
              boxShadow: [
                // Близкая мягкая «опора» + дальняя рассеянная: окно читается
                // приподнятым, но не «висит в вакууме».
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.22),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              // Радиус внутренней подложки на толщину канта меньше внешнего,
              // иначе кант «съедается» и кромка читается неровной.
              borderRadius: BorderRadius.circular(Radii.xl - 1.4),
              // БЕЗ `BackdropFilter`: под анимацией появления/ухода размытие
              // пересобирается каждый кадр, и окно заметно МЕРЦАЕТ — ровно
              // та жалоба, что пришла на прошлый круг. Стекло делаем
              // полупрозрачной подложкой: тот же вид, но без пересборки
              // фильтра, поэтому всплытие идёт ровно.
              child: Container(
                decoration: BoxDecoration(
                  // Полупрозрачная подложка с красным отливом — ровно как у
                  // клавиатуры (`InlineKeyboard`): сквозь окно просвечивает
                  // фон, а алый тон привязывает его к семье «стеклянных»
                  // плашек.
                  color: Color.alphaBlend(
                    BrandColors.red.withValues(alpha: 0.24),
                    cs.surfaceContainerHigh.withValues(alpha: 0.90),
                  ),
                  borderRadius: BorderRadius.circular(Radii.xl - 1.4),
                  border: Border.all(
                    color: BrandColors.red.withValues(alpha: 0.30),
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
                            color: BrandColors.red.withValues(alpha: 0.16),
                          ),
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _bob,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(0, _bobLift(_bob.value)),
                                child: Transform.scale(
                                  scale: _bobScale(_bob.value),
                                  child: child,
                                ),
                              ),
                              child: RepaintBoundary(
                                child: AgyshaBunny(size: 22, color: cs.primary),
                              ),
                            ),
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
                      ).replaceAll('{v}', widget.version),
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
                              onPressed: widget.onCancel,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                // Капсула: та же форма, что у кнопок профиля и
                                // настроек — окно не выбивается из языка.
                                shape: const StadiumBorder(),
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
                              onPressed: widget.onConfirm,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: const StadiumBorder(),
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
