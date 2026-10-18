import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/notification_service.dart';
import '../services/prefs.dart';
import '../widgets/alarm_health_card.dart';
import '../widgets/press_scale.dart';
import '../widgets/stagger_in.dart';

/// Одно приветствие: все критичные разрешения и живая проверка статуса.
class SetupPermissionsScreen extends StatefulWidget {
  const SetupPermissionsScreen({
    super.key,
    required this.notifications,
    this.allowSkip = true,
  });

  final NotificationService notifications;
  final bool allowSkip;

  @override
  State<SetupPermissionsScreen> createState() => _SetupPermissionsScreenState();
}

class _SetupPermissionsScreenState extends State<SetupPermissionsScreen> {
  Future<void> _finish({required bool dismissed}) async {
    Haptics.select();
    await globalPrefs.setBool('welcome_dismissed', dismissed);
    await globalPrefs.setBool('popup_warning_shown', true);
    await globalPrefs.setBool('permission_warning_dismissed', true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      StaggerIn(
                        index: 0,
                        child: Icon(
                          Icons.notifications_active_outlined,
                          size: 56,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      StaggerIn(
                        index: 1,
                        child: Text(
                          Translations.welcomeTitleOf(context),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      StaggerIn(
                        index: 2,
                        child: Text(
                          Translations.t('setupSubtitle', context),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      StaggerIn(
                        index: 3,
                        child: AlarmHealthCard(
                          notifications: widget.notifications,
                          embedded: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PressScale(
                  child: FilledButton(
                    onPressed: () => _finish(dismissed: true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(Translations.t('setupDone', context)),
                  ),
                ),
                if (widget.allowSkip) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _finish(dismissed: true),
                    child: Text(Translations.t('setupLater', context)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
