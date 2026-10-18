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
/// По тапу: тихо проверяет GitHub-релиз; если версия новее — БЕЗ диалогов
/// скачивает APK (показывая прогресс прямо в таблетке) и сразу показывает
/// системную установку («предложить установить»). Если обновления нет — тихо
/// сообщает, что версия последняя.
class UpdatePill extends StatefulWidget {
  const UpdatePill({super.key});

  @override
  State<UpdatePill> createState() => _UpdatePillState();
}

class _UpdatePillState extends State<UpdatePill>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _squirrel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void dispose() {
    _squirrel.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_busy) return;
    Haptics.light();
    setState(() => _busy = true);
    _squirrel.repeat();
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

      // Молча качаем — без подтверждений и лишних диалогов.
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
        _squirrel.stop();
        _squirrel.value = 0;
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
                    animation: _squirrel,
                    builder: (context, _) => CustomPaint(
                      painter: _RunningSquirrelPainter(
                        phase: _busy ? _squirrel.value : 0,
                        color: cs.onPrimaryContainer,
                        detailColor: cs.primaryContainer,
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

/// Tiny custom-drawn runner: tail swishes and feet cycle without changing the
/// pill's layout, so its label stays perfectly still while an update runs.
class _RunningSquirrelPainter extends CustomPainter {
  const _RunningSquirrelPainter({
    required this.phase,
    required this.color,
    required this.detailColor,
    required this.running,
  });

  final double phase;
  final Color color;
  final Color detailColor;
  final bool running;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 24, size.height / 24);
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stridePhase = phase * math.pi * 2;
    final bounce = running ? math.sin(stridePhase) * 0.45 : 0.0;
    final tailSway = running ? math.sin(stridePhase - 0.45) * 0.8 : 0.0;
    canvas.translate(0, -bounce);

    // Curled plume tail, behind the body.
    final tail = Path()
      ..moveTo(7.8, 15.8)
      ..cubicTo(2.8, 16.4, 2.5 + tailSway, 11.7, 5.4, 9.2)
      ..cubicTo(8.4, 6.4, 12.3, 8.0, 11.2, 10.6)
      ..cubicTo(10.6, 12.0, 8.5, 11.4, 8.8, 10.3)
      ..cubicTo(9.0, 9.6, 10.1, 9.6, 10.4, 10.1)
      ..cubicTo(10.8, 7.7, 7.6, 7.0, 5.6, 9.5)
      ..cubicTo(3.3, 12.4, 4.8, 15.0, 8.1, 14.4)
      ..close();
    canvas.drawPath(tail, paint);
    canvas.drawPath(
      Path()
        ..moveTo(5.0, 14.2)
        ..cubicTo(3.8, 11.5, 6.4, 8.2, 9.1, 8.7)
        ..cubicTo(10.6, 8.9, 11.1, 10.1, 10.1, 10.9),
      Paint()
        ..color = detailColor.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round,
    );

    // Feet alternate while running; their fixed bounds prevent layout jitter.
    final stride = running ? math.sin(stridePhase) * 1.8 : 0.0;
    final legs = Path()
      ..moveTo(13.1, 15.8)
      ..quadraticBezierTo(13.0 + stride * 0.45, 18.0, 11.8 + stride, 20.1)
      ..moveTo(17.0, 15.7)
      ..quadraticBezierTo(17.2 - stride * 0.45, 17.8, 19.2 - stride, 19.4);
    canvas.drawPath(
      legs,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.drawLine(
      Offset(11.8 + stride, 20.1),
      Offset(13.6 + stride, 20.1),
      Paint()
        ..color = color
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(19.2 - stride, 19.4),
      Offset(21.0 - stride, 19.4),
      Paint()
        ..color = color
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawOval(const Rect.fromLTWH(8.2, 10.1, 11.4, 7.2), paint);
    canvas.drawOval(
      const Rect.fromLTWH(13.0, 12.0, 5.4, 4.2),
      Paint()..color = detailColor.withValues(alpha: 0.55),
    );
    canvas.drawOval(const Rect.fromLTWH(14.1, 5.6, 7.0, 7.1), paint);
    canvas.drawPath(
      Path()
        ..moveTo(15.0, 6.2)
        ..lineTo(15.0, 2.8)
        ..quadraticBezierTo(17.6, 3.2, 17.2, 6.0)
        ..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(18.4, 5.9)
        ..lineTo(20.2, 3.6)
        ..quadraticBezierTo(21.5, 5.0, 20.6, 6.7)
        ..close(),
      paint,
    );
    canvas.drawOval(
      const Rect.fromLTWH(18.8, 8.0, 1.0, 1.0),
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(const Offset(19.3, 8.5), 0.34, Paint()..color = color);
    canvas.drawCircle(const Offset(21.5, 10.1), 0.85, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RunningSquirrelPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.detailColor != detailColor ||
      oldDelegate.running != running;
}
