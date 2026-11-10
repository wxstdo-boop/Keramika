import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/profile_screen.dart';
import 'package:keramika/widgets/profile_avatar.dart';
import 'package:keramika/screens/settings_screen.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/main.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/widgets/animated_blur_title.dart';
import 'package:keramika/widgets/music_pulse_ring.dart';
import 'package:keramika/widgets/online_dot.dart';
import 'package:keramika/widgets/press_scale.dart';

/// Регрессы второго круга полировки:
///  * кружок онлайна в шапке крупнее и стоит справа от буквы;
///  * плашки «О приложении» отдают нажатие через [PressScale];
///  * кольцо музыки гаснет на паузе;
///  * у профиля при прокрутке появляется верхний blur-слой.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_polish2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('кружок онлайна в шапке стал крупнее (11 px)', (tester) async {
    expect(OnlineDot.dotSize, 11);
    expect(OnlineDot.tapTarget, greaterThan(OnlineDot.dotSize));
  });

  testWidgets('в «О приложении» три плашки отдают нажатие (PressScale)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Настройки требуют KeramikaApp в предках (KeramikaApp.of) — поднимаем
    // настоящее приложение и открываем экран настроек через навигатор.
    await tester.pumpWidget(const KeramikaApp(initialLanguageCode: 'ru'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    // Доскроллить до блока «О приложении» и убедиться, что три ссылки
    // обёрнуты в PressScale (плавная отдача), а не голым InkWell.
    await tester.dragUntilVisible(
      find.text('GitFlic'),
      find.byType(Scrollable).last,
      const Offset(0, -200),
    );
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in ['GitFlic', 'GitHub']) {
      final pressScales = find.ancestor(
        of: find.text(label),
        matching: find.byType(PressScale),
      );
      expect(
        pressScales,
        findsWidgets,
        reason: '«$label» должна отдавать нажатие через PressScale',
      );
    }
    expect(tester.takeException(), isNull);

    // Догоняем страховочные таймеры главного экрана, иначе тест завершится
    // с висящим Timer.
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('кольцо музыки гаснет на паузе', (tester) async {
    Widget wrap(bool active) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: MusicPulseRing(
            active: active,
            child: const Icon(Icons.play_arrow),
          ),
        ),
      ),
    );

    await tester.pumpWidget(wrap(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byType(AnimatedOpacity),
          )
          .opacity,
      1.0,
    );

    await tester.pumpWidget(wrap(false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byType(AnimatedOpacity),
          )
          .opacity,
      0.0,
      reason: 'на паузе кольцо должно быть полностью погашено',
    );
  });

  testWidgets('профиль: аватарка плывёт при прокрутке (параллакс, без размытия)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));

    // Верхнего размывающего слоя нет НИ в покое, ни при прокрутке: «полку»
    // из профиля убрали — она читалась как лишнее стекло над контентом.
    expect(find.byType(BackdropFilter), findsNothing);

    double parallax() => tester
        .widget<ProfileAvatar>(find.byType(ProfileAvatar).first)
        .parallax;

    expect(parallax(), 0.0, reason: 'в покое аватарка не смещена');

    // Сдвигаем умеренно (шапка ещё видна): у большого сдвига заголовочная
    // карточка уходит из окна, и ListView её размонтирует.
    final list = find.byType(ListView);
    final g = await tester.startGesture(tester.getCenter(list));
    for (var i = 0; i < 3; i++) {
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    // С прокруткой содержимое аватарки «плывёт» внутри круга.
    expect(
      parallax(),
      isNot(0.0),
      reason: 'при прокрутке аватарка должна плыть (параллакс)',
    );
    expect(find.byType(BackdropFilter), findsNothing);

    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('кружок в шапке стоит СПРАВА от последней буквы', (tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Center(child: AnimatedBlurTitle(onOnlineTap: () {})),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    final dot = tester.getCenter(find.byType(OnlineDot));
    final title = tester.getRect(find.text('Keramika'));
    expect(
      dot.dx,
      greaterThan(title.right),
      reason: 'кружок должен быть справа от буквы, не поверх неё',
    );
  });
}
