import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/installer.dart';
import '../services/update_service.dart';
import '../utils/snackbar.dart';

/// Полупрозрачная таблетка «Проверить обновления» рядом с версией в
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

class _UpdatePillState extends State<UpdatePill> {
  bool _busy = false;

  /// Текущая фаза: «Проверка…», «Скачивание NN%», «Установка…». null — покой.
  String? _phase;

  Future<void> _onTap() async {
    if (_busy) return;
    Haptics.light();
    setState(() {
      _busy = true;
      _phase = Translations.t('updateChecking', context, 'Проверка…');
    });
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

      // Молча качаем — без подтверждений и лишних диалогов.
      setState(
        () => _phase = Translations.t('updateDownloading', context, 'Скачивание…'),
      );
      final path = await UpdateService.instance.download(
        update,
        onProgress: (p) {
          if (!mounted) return;
          setState(
            () => _phase =
                '${Translations.t('updateDownloading', context, 'Скачивание')} '
                '${(p * 100).round()}%',
          );
        },
      );
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

      setState(
        () => _phase = Translations.t('updateInstalling', context, 'Установка…'),
      );
      final ok = await Installer.installApk(path, expectedSha256: update.sha256);
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
      _toast(
        Translations.t('updateError', context, 'Ошибка обновления'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _phase = null;
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
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: pendingUpdate,
      builder: (context, update, _) {
        final label =
            _phase ??
            (update != null
                ? '${Translations.t('updateTo', context, 'Обновить до')} '
                    'v${update.versionName}'
                : Translations.t(
                    'checkUpdates',
                    context,
                    'Проверить обновления',
                  ));
        return GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              // Полупрозрачная подложка + тонкая грань: таблетка не «кричит».
              color: cs.primary.withValues(alpha: _busy ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.28),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  )
                else
                  Icon(Icons.system_update_alt, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
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
