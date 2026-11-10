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
    duration: const Duration(milliseconds: 680),
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
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.42),
        transitionDuration: const Duration(milliseconds: 240),
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
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
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
    final badgeTextStyle =
        (theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
          fontWeight: FontWeight.w800,
        );
    final recommendedMeasure = TextPainter(
      text: TextSpan(text: 'Recommended', style: badgeTextStyle),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final badgeWidth = (recommendedMeasure.width + 18).ceilToDouble();
    final badgeHeight = (recommendedMeasure.height + 8).ceilToDouble();
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: pendingUpdate,
      builder: (context, update, _) {
        return GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: badgeHeight,
            width: badgeWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => CustomPaint(
                      painter: _UpdateGlyphPainter(
                        progress: _busy ? _spin.value : 0,
                        color: cs.onPrimaryContainer,
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
        );
      },
    );
  }
}

/// Значок таблетки: в покое — «искра обновления» (четырёхлучевая звезда с
/// малой спутницей), в работе — плавно вращающееся кольцо с растворяющимся
/// хвостом.
///
/// Звезда читается как «свежее, новое» и заметно отличается от системной
/// стрелки-в-лоток, но сохраняет размер и вес кольца, поэтому переход
/// «покой → работа» не двигает лэйаут таблетки.
class _UpdateGlyphPainter extends CustomPainter {
  const _UpdateGlyphPainter({
    required this.progress,
    required this.color,
    required this.running,
  });

  final double progress;
  final Color color;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1.4;

    if (running) {
      // Кольцо-комета: сплошная дуга в 250° и растворяющийся хвост. Угол
      // растёт линейно, поэтому вращение ровное, без рывка на стыке.
      final start = -math.pi / 2 + progress * math.pi * 2;
      const sweep = math.pi * 1.38;
      final steps = 26;
      for (var i = 0; i < steps; i++) {
        final t0 = i / steps;
        final t1 = (i + 1) / steps;
        final a0 = start + sweep * t0;
        final a1 = start + sweep * t1;
        final alpha = 0.25 + 0.75 * t0;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          a0,
          a1 - a0,
          false,
          Paint()
            ..color = color.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.9
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true,
        );
      }
      return;
    }

    // Покой: четырёхлучевая «искра» — две скрещённые дуги-линзы. Кончики
    // сведены в одну точку, середина «толще»: звезда мягкая, не колючая.
    void drawSpark(Offset c, double r, double w) {
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx + r * 0.28, c.dy - r * 0.28, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx + r * 0.28, c.dy + r * 0.28, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx - r * 0.28, c.dy + r * 0.28, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx - r * 0.28, c.dy - r * 0.28, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(path, p);
    }

    drawSpark(center.translate(-0.4, -0.4), radius * 0.92, 1.5);
    // Малая спутница снизу-справа — «ещё одна искра», живой акцент.
    drawSpark(
      center.translate(radius * 0.66, radius * 0.66),
      radius * 0.34,
      1.3,
    );
  }

  @override
  bool shouldRepaint(covariant _UpdateGlyphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
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
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.lg,
                Spacing.lg,
                Spacing.md,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.xl - 1),
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
                          color: cs.primaryContainer,
                        ),
                        child: Icon(
                          Icons.system_update_alt_rounded,
                          color: cs.onPrimaryContainer,
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
                              Translations.t('install', context, 'Установить'),
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
    );
  }
}
