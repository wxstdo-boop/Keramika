import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/profile_gift.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/widgets/audio_spectrum_ring.dart';
import 'package:agysha/widgets/gift_card_3d.dart';
import 'package:agysha/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    tmpDir = await Directory.systemTemp.createTemp('agysha_gift_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmpDir.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.wetcorp.agysha/haptics'),
      (call) async => null,
    );
    await ProfileService().load();
  });

  tearDown(() async {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Profile Gifts, Audio Spectrum & Zen Clicker', () {
    test('ProfileService manages prestigeTitle and zenKarma', () async {
      final service = ProfileService();
      expect(service.prestigeTitle, 'Cyberpunk 2077 Legend');
      expect(service.zenKarma, 0);

      await service.incrementZenKarma(5);
      expect(service.zenKarma, 5);

      await service.setPrestigeTitle('Night City Legend');
      expect(service.prestigeTitle, 'Night City Legend');
    });

    test('ProfileService loads initial showcase and toggles favorite', () async {
      final service = ProfileService();
      expect(service.gifts.isNotEmpty, isTrue);

      final firstGift = service.gifts.first;
      final initialFav = firstGift.isFavorite;

      await service.toggleGiftFavorite(firstGift.id);
      expect(service.gifts.first.isFavorite, !initialFav);
    });

    testWidgets('GiftCard3D renders rarity, serial and title', (tester) async {
      final testGift = ProfileGift(
        id: 'test_artifact',
        title: 'Тестовый артефакт',
        description: 'Описание тестового артефакта',
        icon: Icons.star_rounded,
        rarity: GiftRarity.legendary,
        serialNumber: 42,
        unlockedAt: 123456789,
        buffText: '+10% к бодрости',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GiftCard3D(gift: testGift),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Тестовый артефакт'), findsOneWidget);
      expect(find.text('#0042'), findsOneWidget);
      expect(find.text('ЛЕГЕНДАРНЫЙ'), findsOneWidget);
      expect(find.text('+10% к бодрости'), findsOneWidget);
    });

    testWidgets('AudioSpectrumRing renders around child without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AudioSpectrumRing(
                radius: 48,
                child: Container(width: 96, height: 96, color: Colors.blue),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AudioSpectrumRing), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ProfileScreen renders header with spectrum, zen and gifts shelf', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const LocaleProvider(
          locale: Locale('ru'),
          child: MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AudioSpectrumRing), findsOneWidget);
      expect(find.textContaining('Дзен:'), findsOneWidget);
      expect(find.text('Коллекция артефактов'), findsOneWidget);
      expect(find.byType(GiftCard3D), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
