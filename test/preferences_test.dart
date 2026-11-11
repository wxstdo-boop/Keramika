import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/services/haptics.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/services/sounds.dart';
import 'package:agysha/utils/motion_prefs.dart';

/// Виджет с вечным декоративным циклом — минимальная обёртка вокруг
/// [MotionAwareRepeat], чтобы проверить остановку по тумблеру.
class _Looping extends StatefulWidget {
  const _Looping();

  @override
  State<_Looping> createState() => _LoopingState();
}

class _LoopingState extends State<_Looping>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController ctrl = ambientRepeat(
    AnimationController(vsync: this, duration: const Duration(seconds: 2)),
  );

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  late Directory tmpDir;
  late List<String> hapticCalls;
  late List<String> soundCalls;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_prefs');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
    hapticCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.wetcorp.agysha/haptics'),
          (call) async {
            hapticCalls.add(call.method);
            return null;
          },
        );
    // [SystemSound] шлёт метод `SystemSound.play` на канал `flutter/platform`,
    // который использует JSON-кодек. Перехватываем на бинарном уровне и
    // раскодируем вызов его же кодеком — `setMockMethodCallHandler` тут не
    // годится (он ждёт Standard-кодек и «портит» сообщение).
    soundCalls = <String>[];
    final platformChannel = SystemChannels.platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(platformChannel.name, (message) async {
          final call = platformChannel.codec.decodeMethodCall(message);
          if (call.method == 'SystemSound.play') {
            soundCalls.add(call.arguments as String);
          }
          return platformChannel.codec.encodeSuccessEnvelope(null);
        });
    // Возвращаем флаги к значениям по умолчанию между тестами.
    Haptics.enabled = true;
    Sounds.enabled = false;
    MotionPrefs.enabled.value = false;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.wetcorp.agysha/haptics'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(SystemChannels.platform.name, null);
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('настройки вибрации и «убрать анимации» переживают перезапуск', () async {
    await SettingsService.saveHaptics(false);
    await SettingsService.saveReduceMotion(true);

    // «Перезапуск»: перечитываем то, что записано на диск.
    expect(await SettingsService.loadHaptics(), isFalse);
    expect(await SettingsService.loadReduceMotion(), isTrue);
  });

  test('по умолчанию вибрация включена, анимации не убраны', () async {
    expect(await SettingsService.loadHaptics(), isTrue);
    expect(await SettingsService.loadReduceMotion(), isFalse);
  });

  test('выключенная вибрация гасит отклик, включённая — бьёт', () async {
    Haptics.enabled = false;
    await Haptics.light();
    expect(hapticCalls, isEmpty);

    Haptics.enabled = true;
    await Haptics.select();
    expect(hapticCalls, ['select']);
  });

  test('настройка звуков переживает перезапуск, по умолчанию выключена', () async {
    expect(await SettingsService.loadSounds(), isFalse);
    await SettingsService.saveSounds(true);
    expect(await SettingsService.loadSounds(), isTrue);
  });

  test('выключенные звуки молчат, включённые — играют', () async {
    Sounds.enabled = false;
    await Sounds.success();
    expect(soundCalls, isEmpty);

    Sounds.enabled = true;
    await Sounds.click();
    expect(soundCalls, ['SystemSoundType.click']);
  });

  test('shouldReduceMotion следует за тумблером', () {
    MotionPrefs.enabled.value = false;
    expect(MotionPrefs.shouldReduceMotion, isFalse);
    MotionPrefs.enabled.value = true;
    expect(MotionPrefs.shouldReduceMotion, isTrue);
  });

  testWidgets('вечный цикл не стартует, когда движение убрано', (tester) async {
    MotionPrefs.enabled.value = true;
    await tester.pumpWidget(const MaterialApp(home: _Looping()));
    final state = tester.state<_LoopingState>(find.byType(_Looping));
    expect(state.ctrl.isAnimating, isFalse);
  });

  testWidgets('тумблер останавливает и снова запускает вечный цикл', (
    tester,
  ) async {
    MotionPrefs.enabled.value = false;
    await tester.pumpWidget(const MaterialApp(home: _Looping()));
    final state = tester.state<_LoopingState>(find.byType(_Looping));
    expect(state.ctrl.isAnimating, isTrue);

    MotionPrefs.enabled.value = true;
    await tester.pump();
    expect(state.ctrl.isAnimating, isFalse);

    MotionPrefs.enabled.value = false;
    await tester.pump();
    expect(state.ctrl.isAnimating, isTrue);
  });
}
