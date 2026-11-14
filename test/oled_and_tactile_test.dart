import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/l10n/translations.dart';
import 'package:agysha/main.dart';
import 'package:agysha/screens/add_reality_check_screen.dart';
import 'package:agysha/screens/add_timer_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/settings_service.dart';
import 'package:agysha/widgets/press_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    tmpDir = await Directory.systemTemp.createTemp('agysha_oled_test');
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

  group('OLED Black Theme & Tactile Feedback', () {
    test('SettingsService supports oled theme mode', () async {
      await SettingsService.saveThemeMode('oled');
      final loaded = await SettingsService.loadThemeMode();
      expect(loaded, 'oled');
    });

    test('Translations contains themeOled in all supported locales', () {
      final raw = Translations.rawData;
      expect(raw['en']?['themeOled'], 'Cyberpunk 2077');
      expect(raw['ru']?['themeOled'], 'Cyberpunk 2077');
      expect(raw['fr']?['themeOled'], 'Cyberpunk 2077');
    });

    testWidgets('AgyshaApp switches to OLED theme with pure black surface', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'en'));
      final state = tester.state<AgyshaAppState>(find.byType(AgyshaApp));

      state.setThemeMode('oled');
      await tester.pumpAndSettle();

      expect(state.themeKey, 'oled');
      expect(state.themeMode, ThemeMode.dark);

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final darkTheme = materialApp.darkTheme;
      expect(darkTheme, isNotNull);
      expect(darkTheme!.colorScheme.surface, const Color(0xFF000000));
      expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF000000));
    });

    testWidgets('AddRealityCheckScreen has PressScale on icon picker', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        LocaleProvider(
          locale: const Locale('en'),
          child: const MaterialApp(
            home: Scaffold(body: AddRealityCheckScreen()),
          ),
        ),
      );
      await tester.pump();

      // Find PressScale with pressedScale 0.92
      final pressScales = tester.widgetList<PressScale>(find.byType(PressScale));
      expect(
        pressScales.any((ps) => ps.pressedScale == 0.92),
        isTrue,
        reason: 'Icon picker circle should be wrapped in PressScale(pressedScale: 0.92)',
      );
    });

    testWidgets('AddTimerScreen has PressScale on duration picker button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        LocaleProvider(
          locale: const Locale('en'),
          child: const MaterialApp(
            home: Scaffold(body: AddTimerScreen()),
          ),
        ),
      );
      await tester.pump();

      // Find PressScale wrapping FilledButton.tonal
      final durationButton = find.byType(FilledButton);
      expect(durationButton, findsOneWidget);

      final parentPressScale = find.ancestor(
        of: durationButton,
        matching: find.byType(PressScale),
      );
      expect(parentPressScale, findsOneWidget);
    });
  });
}
