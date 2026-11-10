import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/installer.dart';
import '../services/update_service.dart';
import '../utils/snackbar.dart';

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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            Translations.t('updateAvailable', ctx, 'Доступно обновление'),
          ),
          content: Text(
            Translations.t(
              'updateAvailableBody',
              ctx,
              'Установить v{v}?',
            ).replaceAll('{v}', update.versionName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(Translations.t('cancel', ctx, 'Отмена')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(Translations.t('install', ctx, 'Установить')),
            ),
          ],
        ),
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

/// Значок таблетки: в покое — аккуратная «стрелка в лоток» (установка),
/// в работе — плавно вращающееся кольцо с «хвостом-кометой».
///
/// Раньше здесь бежала нарисованная белка: у неё дёргались лапы и хвост, и
/// на 13 px это читалось мельтешением, а не движением. Кольцо вращается
/// непрерывно и равноускоренно — «идёт проверка/загрузка» понятно без текста
/// и не мельтешит. Дуга рисуется теми же штрихами со скруглёнными концами,
/// что и стрелка, поэтому переход «покой → работа» не меняет ни размер, ни
/// вес значка: таблетка не «дёргает» лэйаут.
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
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

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

    // Покой: стрелка вниз в «лоток» — узнаваемый знак установки/загрузки.
    final r = math.min(size.width, size.height) / 2;
    canvas.drawLine(
      Offset(center.dx, center.dy - r * 0.62),
      Offset(center.dx, center.dy + r * 0.12),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - r * 0.36, center.dy - r * 0.16)
        ..lineTo(center.dx, center.dy + r * 0.16)
        ..lineTo(center.dx + r * 0.36, center.dy - r * 0.16),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(center.dx - r * 0.6, center.dy + r * 0.62)
        ..lineTo(center.dx + r * 0.6, center.dy + r * 0.62),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _UpdateGlyphPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.running != running;
}
