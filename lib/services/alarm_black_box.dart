import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:path_provider/path_provider.dart';

/// Dart-половинка «чёрного ящика» будильников: тот же файл, что пишет
/// нативный `AlarmLog` — `/sdcard/Android/data/<pkg>/files/alarm_fire_log.txt`,
/// читается без root:
/// `adb exec-out "cat '/sdcard/Android/data/com.wetidom.keramika/files/alarm_fire_log.txt'"`
///
/// Зачем: нативная часть честно пишет «ALARM FIRED», когда приёмник запустился.
/// Но «будильник не сработал» — это чаще всего отсутствие строки, а отсутствие
/// строки ничем не докажешь: непонятно, кто виноват — Dart не поставил,
/// система убрала, или приёмник не запустился. Здесь пишутся решения Dart-
/// стороны (поставил/не смог/пропустил), и картина становится полной.
class AlarmBlackBox {
  static bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> log(String msg) async {
    if (!_enabled) return;
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${now.year}-${two(now.month)}-${two(now.day)} '
          '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
      final f = File('${dir.path}${Platform.pathSeparator}alarm_fire_log.txt');
      await f.writeAsString(
        '$stamp $msg\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Журнал не должен влиять на работу будильников.
    }
  }
}
