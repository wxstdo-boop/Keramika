import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../overlay/overlay_bridge.dart';
import '../utils/android_settings.dart';
import 'alarm_scheduler.dart';
import 'notification_service.dart';

/// Живой снимок системных разрешений, без которых будильник ненадёжен.
class AlarmHealthSnapshot {
  const AlarmHealthSnapshot({
    required this.notifications,
    required this.exactAlarm,
    required this.batteryUnrestricted,
    required this.fullScreen,
    required this.overlay,
  });

  final bool notifications;
  final bool exactAlarm;
  final bool batteryUnrestricted;
  final bool fullScreen;
  final bool overlay;

  /// То, без чего звонок может не вылезти вовремя.
  bool get alarmsReady =>
      notifications && exactAlarm && batteryUnrestricted && fullScreen;

  bool get allGranted => alarmsReady && overlay;
}

class AlarmHealth {
  AlarmHealth._();

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<AlarmHealthSnapshot> probe(NotificationService notifications) async {
    if (!_android) {
      return const AlarmHealthSnapshot(
        notifications: true,
        exactAlarm: true,
        batteryUnrestricted: true,
        fullScreen: true,
        overlay: true,
      );
    }
    final results = await Future.wait<bool>([
      notifications.areNotificationsEnabled(),
      AlarmScheduler.canScheduleExactAlarms(),
      AlarmScheduler.isIgnoringBatteryOptimizations(),
      canUseFullScreenIntent(),
      adaOverlayPermission(),
    ]);
    return AlarmHealthSnapshot(
      notifications: results[0],
      exactAlarm: results[1],
      batteryUnrestricted: results[2],
      fullScreen: results[3],
      overlay: results[4],
    );
  }
}
