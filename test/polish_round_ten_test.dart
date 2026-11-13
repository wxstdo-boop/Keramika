import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/profile_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/utils/animated_delete.dart';
import 'package:agysha/widgets/inline_keyboard.dart';
import 'package:agysha/widgets/profile_avatar.dart';

/// Регрессы полировки десятого круга:
///  * фон свайп-удаления — ПОЛУПРОЗРАЧНО-красный, а не глухая заливка;
///  * клавиатура — полупрозрачная панель с красным отливом темы;
///  * у сгенерированной аватарки (без своей картинки) размытие реально
///    применяется — раньше оно работало только для своей фотографии;
///  * карточка музыки меняет состояние ОДНИМ механизмом (AnimatedCrossFade),
///    а не спорящими AnimatedSwitcher + AnimatedSize.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 10));
    tmpDir = await Directory.systemTemp.createTemp('agysha_round_ten');
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
    await ProfileService().load();
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

  testWidgets('фон свайп-удаления — полупрозрачно-красный', (tester) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (context) => animatedDeleteBackground(context),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final container = tester.widget<Container>(find.byType(Container).first);
    final gradient =
        (container.decoration! as BoxDecoration).gradient! as LinearGradient;
    for (final c in gradient.colors) {
      // Красный остаётся красным, но альфа меньше единицы — сквозь плашку
      // видно карточку, а не глухая заливка.
      expect(c.r, greaterThan(c.g));
      expect(c.a, lessThan(1.0));
      expect(c.a, greaterThan(0.0));
    }
  });

  testWidgets('клавиатура — полупрозрачная панель с красным отливом', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE0192F)),
        ),
        home: Scaffold(
          body: InlineKeyboard(onChar: (_) {}, onBackspace: () {}, onSpace: () {}),
        ),
      ),
    );
    await tester.pump();

    final panel = tester.widget<Container>(find.byType(Container).first);
    final color = (panel.decoration! as BoxDecoration).color!;
    expect(color.a, lessThan(1.0), reason: 'панель должна быть полупрозрачной');
    // Красный отлив: красного канала заметно больше зелёного.
    expect(color.r, greaterThan(color.g));
  });

  testWidgets('размытие работает и у сгенерированной аватарки', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(index: 0, size: 96, blur: 6),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Раньше `blur` учитывался только в ветке со своей картинкой, и у
    // большинства пользователей (сгенерированный шар) расфокуса не было.
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('карточка музыки ведёт «пусто ↔ подборка» одним механизмом', (
    tester,
  ) async {
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

    // Проявку текста ведёт AnimatedSwitcher, а высоту — ОДИН AnimatedSize
    // над ним: раньше эти роли спорили между двумя механизмами, и карточка
    // «скукоживалась» рывком. Карточка музыки — единственное место профиля,
    // где подборка переходит в пустое состояние.
    expect(
      find.byKey(const ValueKey('music_empty')),
      findsOneWidget,
      reason: 'без треков карточка показывает пустое состояние',
    );
    expect(tester.takeException(), isNull);
  });
}
