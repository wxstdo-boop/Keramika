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
import 'package:agysha/widgets/ada_avatars.dart';
import 'package:agysha/widgets/inline_keyboard.dart';
import 'package:agysha/widgets/music_pulse_ring.dart';
import 'package:agysha/widgets/press_splat.dart' show GlassFabTile;

/// Регресс-тест круга 13: жалобы на канты, «квадратное» свечение, серую
/// клавиатуру, тормозные переходы и щёлкающие очки.
///
/// Проверяем инварианты кода, каждый из которых закрывал конкретную жалобу:
///  * окно обновления — кант с четырьмя опорными точками (кромка не гаснет
///    в середине периметра);
///  * у кольца музыки ОТКЛЮЧЁН клип `Stack`: иначе размытое свечение
///    обрезалось по прямоугольнику и читалось «светящимся квадратом»;
///  * клавиатура берёт КРАСНЫЙ бренда, а не `primary` темы (на дефолтной
///    палитре primary сиреневый — панель серела);
///  * лист над другом — ОДИН маршрут на оба шага: второе затемнение не
///    складывается в «двойной тёмный фон» за окном очков;
///  * строки «Очки/Удалить» — `InkWell` со скруглением, а не `ListTile`
///    (чернильная волна `ListTile` заливала квадрат на всю ширину);
///  * очки рейтинга меняются барабаном `AnimatedCounter`, а не мгновенно.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 13));
    tmpDir = await Directory.systemTemp.createTemp('agysha_round_thirteen');
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
    // Профиль читается в настоящей async-зоне: внутри testWidgets
    // (fake-async) реальный файловый I/O виснет — см. AGENTS.md.
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

  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path не найден — тест не из корня',
    );
    return f.readAsStringSync();
  }

  test('кант окна обновления — красный бренда, как у клавиатуры', () {
    final src = read('lib/widgets/update_pill.dart');
    expect(
      RegExp(r'BrandColors\.red\.withValues').hasMatch(src),
      isTrue,
      reason: 'кромка должна быть алым бренда, а не градиентом primary→tertiary',
    );
    expect(
      src.contains('cs.tertiary.withValues(alpha: 0.55)'),
      isFalse,
      reason: 'сиреневый tertiary на дефолтной палитре выбивал окно из семьи',
    );
  });

  testWidgets('кольцо музыки не обрезает свечение по прямоугольнику', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MusicPulseRing(
              active: true,
              child: SizedBox(width: 64, height: 64),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final stack = tester.widget<Stack>(
      find.descendant(
        of: find.byType(MusicPulseRing),
        matching: find.byType(Stack),
      ).first,
    );
    expect(
      stack.clipBehavior,
      Clip.none,
      reason: '`Clip.hardEdge` резал блюр по краям — квадратное свечение',
    );
  });

  testWidgets('клавиатура красная на сиреневой теме по умолчанию', (
    tester,
  ) async {
    // Тема как в приложении по умолчанию: primary сиреневый. Раньше отлив
    // брался из него, и панель выходила серой.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF6750A4),
            surfaceContainer: Color(0xFFEDF5F7),
            surfaceContainerHighest: Color(0xFFDFEBEF),
          ),
        ),
        home: Scaffold(
          body: InlineKeyboard(
            onChar: (_) {},
            onBackspace: () {},
            onSpace: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final panel = tester.widget<Container>(find.byType(Container).first);
    final color = (panel.decoration! as BoxDecoration).color!;
    expect(color.a, lessThan(1.0), reason: 'панель должна быть полупрозрачной');
    expect(color.r, greaterThan(color.b), reason: 'отлив КРАСНЫЙ, не сиреневый');
    expect(color.r, greaterThan(color.g), reason: 'отлив КРАСНЫЙ, не сиреневый');
  });

  test('лист над другом — один маршрут, без второго затемнения', () {
    final src = read('lib/screens/profile_screen.dart');
    expect(src.contains('class _FriendSheet'), isTrue);
    expect(
      src.contains('_popAfterPress'),
      isFalse,
      reason: 'раздельные маршруты давали «двойной тёмный фон» и паузу',
    );
    final edit = src.indexOf('Future<void> _editFriend(');
    expect(edit, greaterThan(0));
    final body = src.substring(edit, edit + 900);
    expect(
      'showModalBottomSheet'.allMatches(body).length,
      1,
      reason: 'на оба шага — ОДИН маршрут: затемнение не складывается',
    );
    expect(
      body.contains('Future<void>.delayed'),
      isFalse,
      reason: 'пауза перед открытием очков читалась торможением',
    );
  });

  test('строка «Очки/Удалить» — InkWell со скруглением, не ListTile', () {
    final src = read('lib/screens/profile_screen.dart');
    final start = src.indexOf('Widget _actionTile(');
    final body = src.substring(start, start + 1400);
    expect(body.contains('InkWell('), isTrue);
    expect(
      body.contains('borderRadius: BorderRadius.circular'),
      isTrue,
      reason: 'без скругления подсветка читалась квадратом',
    );
    expect(
      body.contains('ListTile('),
      isFalse,
      reason: 'волна ListTile заливала прямоугольник на всю ширину',
    );
  });

  test('очки рейтинга меняются ПО БУКВАМ, как в поле очков', () {
    final src = read('lib/screens/profile_screen.dart');
    final row = src.indexOf('Widget _leaderRow(');
    expect(row, greaterThan(0));
    final body = src.substring(row, row + 2600);
    expect(
      body.contains('SmoothDigits('),
      isTrue,
      reason: 'число сменяется посимвольно (SmoothTyping), а не барабаном',
    );
    expect(
      body.contains('AnimatedCounter('),
      isFalse,
      reason: 'барабан читался грубым подменом — заменён плавной сменой цифр',
    );
    expect(body.contains("'\${f.score}'"), isFalse);
  });

  testWidgets('лист над другом перетекает в очки без второго затемнения', (
    tester,
  ) async {
    final svc = ProfileService();
    // Друзья создаются в реальной async-зоне: внутри fake-async запись файла
    // виснет (см. AGENTS.md).
    await tester.runAsync(() async {
      await svc.addFriend(name: 'Гончар', colorIndex: 1, score: 10);
    });

    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    // Кадры фиксированные, без `pumpAndSettle`: в профиле есть вечные
    // анимации (пульс музыки, барабан очков), и «оседание» не наступает.
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Гончар'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Очки'), findsOneWidget);

    // Оба шага — внутри ОДНОГО маршрута: до тапа на «Очки» его нет, после
    // тапа лист не закрывается, а перетекает в правку очков.
    expect(find.text('Очки рейтинга'), findsNothing);
    await tester.tap(find.text('Очки'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Очки рейтинга'), findsOneWidget);
    expect(
      find.text('Удалить'),
      findsNothing,
      reason: 'шаг «действия» сменился шагом «очки» в том же листе',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('плитка «+» и Ады — та же рецептура, что у главной таблетки', (
    tester,
  ) async {
    late ColorScheme cs;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE0192F),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              cs = Theme.of(context).colorScheme;
              return const Center(
                child: GlassFabTile(size: 56, child: SizedBox.shrink()),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final outer = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GlassFabTile),
            matching: find.byType(Container),
          )
          .first,
    );
    final shadows = (outer.decoration! as BoxDecoration).boxShadow!;
    expect(
      shadows.length,
      1,
      reason: 'одна мягкая тень, без primary-ореола и контактного следа',
    );
    expect(
      shadows.single.color,
      Colors.black.withValues(alpha: 0.10),
      reason: 'тень капсулы разделов, не фирменное свечение',
    );

    // Внутренняя поверхность — плоский тон темы, кромка `outlineVariant`:
    // то же, что у `_GlassCapsule`. Градиента и блика больше нет.
    final surface = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(GlassFabTile),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color != null);
    expect(surface.color, cs.surfaceContainerHighest);
    expect(surface.gradient, isNull, reason: 'плитка плоская, как таблетка');
    expect(
      (surface.border! as Border).top.color,
      cs.outlineVariant.withValues(alpha: 0.70),
    );
  });

  testWidgets('значок Ады на кнопке монхромный, в чате — цветной', (
    tester,
  ) async {
    late ColorScheme cs;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFE0192F),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              cs = Theme.of(context).colorScheme;
              return const Column(
                children: [
                  AdaAvatar(variantIndex: 0, size: 40, monochrome: true),
                  AdaAvatar(variantIndex: 0, size: 40),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final mono = find.byType(AdaAvatar).at(0);
    final color = find.byType(AdaAvatar).at(1);
    BoxDecoration decoOf(Finder f) =>
        tester
                .widget<Container>(
                  find
                      .descendant(of: f, matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;

    final monoGrad = decoOf(mono).gradient! as LinearGradient;
    expect(
      monoGrad.colors.toSet(),
      {cs.surfaceContainerLowest},
      reason: 'монхром — ровно площадка невыбранного значка таблетки',
    );
    final monoIcon = tester.widget<Icon>(
      find.descendant(of: mono, matching: find.byType(Icon)),
    );
    expect(monoIcon.color, cs.primary, reason: 'чернила глифа — как у иконок');

    // В цветном режиме градиент фирменный, значок белый — кнопка отличается.
    final colorGrad = decoOf(color).gradient! as LinearGradient;
    expect(colorGrad.colors.toSet().length, greaterThan(1));
    final colorIcon = tester.widget<Icon>(
      find.descendant(of: color, matching: find.byType(Icon)),
    );
    expect(colorIcon.color, isNot(cs.primary));

    // У монхрома блик погашен: внутри ровно один Container (медальон),
    // у цветного — медальон плюс стеклянный блик.
    expect(find.descendant(of: mono, matching: find.byType(Container)), findsOneWidget);
    expect(
      find.descendant(of: color, matching: find.byType(Container)),
      findsNWidgets(2),
    );
  });
}
