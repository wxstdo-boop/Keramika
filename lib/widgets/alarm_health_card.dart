import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../overlay/overlay_bridge.dart';
import '../services/alarm_health.dart';
import '../services/haptics.dart';
import '../services/notification_service.dart';
import '../utils/android_settings.dart';
import 'press_scale.dart';

/// Жирная карточка системных разрешений: статус сразу, тап открывает выдачу.
class AlarmHealthCard extends StatefulWidget {
  const AlarmHealthCard({
    super.key,
    required this.notifications,
    this.embedded = false,
  });

  final NotificationService notifications;

  /// true — без внешних отступов карточки (внутри мастера приветствия).
  final bool embedded;

  @override
  State<AlarmHealthCard> createState() => _AlarmHealthCardState();
}

class _AlarmHealthCardState extends State<AlarmHealthCard>
    with WidgetsBindingObserver {
  AlarmHealthSnapshot? _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.notifications.resetNotificationStatusCache();
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final snapshot = await AlarmHealth.probe(widget.notifications);
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  Future<void> _open(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.select();
    try {
      await action();
    } finally {
      widget.notifications.resetNotificationStatusCache();
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final snapshot = _snapshot;
    final ready = snapshot?.alarmsReady ?? false;
    final borderColor = ready ? cs.primary : cs.error;
    final card = Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready
                      ? Icons.verified_outlined
                      : Icons.notification_important_outlined,
                  color: borderColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Translations.t('alarmHealthTitle', context),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Translations.t(
                ready ? 'setupAllOk' : 'setupNeedAction',
                context,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            _row(
              context,
              icon: Icons.notifications_active_outlined,
              title: Translations.t('permNotifications', context),
              granted: snapshot?.notifications,
              onTap: () => _open(() async {
                final ok = await widget.notifications
                    .ensureNotificationPermission();
                if (!ok) await openNotificationSettingsAndroid();
              }),
            ),
            _row(
              context,
              icon: Icons.alarm_on_outlined,
              title: Translations.t('permExactAlarm', context),
              granted: snapshot?.exactAlarm,
              onTap: () => _open(openExactAlarmSettings),
            ),
            _row(
              context,
              icon: Icons.battery_saver_outlined,
              title: Translations.t('permBattery', context),
              granted: snapshot?.batteryUnrestricted,
              onTap: () => _open(openAppSettingsAndroid),
            ),
            _row(
              context,
              icon: Icons.fullscreen_outlined,
              title: Translations.t('permFullScreen', context),
              granted: snapshot?.fullScreen,
              onTap: () => _open(openFullScreenNotifSettings),
            ),
            _row(
              context,
              icon: Icons.power_settings_new_outlined,
              title: Translations.t('autostart', context),
              granted: null,
              onTap: () => _open(openAutostartSettings),
            ),
            _row(
              context,
              icon: Icons.picture_in_picture_alt_outlined,
              title: Translations.t('permOverlay', context),
              granted: snapshot?.overlay,
              onTap: () => _open(() async {
                final ok = await requestAdaOverlayPermission();
                if (!ok) await openOverlaySettings();
              }),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return card;
    return Padding(padding: EdgeInsets.zero, child: card);
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool? granted,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = granted == null
        ? Translations.t('permOpen', context)
        : Translations.t(granted ? 'permGranted' : 'permMissing', context);
    final color = granted == null
        ? cs.primary
        : granted
        ? const Color(0xFF2E7D32)
        : cs.error;
    return PressScale(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          status,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
