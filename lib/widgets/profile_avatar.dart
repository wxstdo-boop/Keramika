import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Вариант аватарки «Agysha-юзера»: красный тон со «стеклянным» блеском.
///
/// Индекс варианта — то, что хранит профиль ([ProfileService.avatarIndex]) и
/// что видит друг в рейтинге. Список детерминированный: один и тот же индекс
/// всегда даёт одну и ту же аватарку, поэтому друзья не «перекрашиваются»
/// между запусками.
class ProfileAvatarVariant {
  final List<Color> colors;
  final IconData icon;

  const ProfileAvatarVariant(this.colors, this.icon);
}

/// Варианты аватарки: спокойная гамма красных — от светлого к глубокому.
/// Порядок стабилен, индекс переживает перезапуск.
final List<ProfileAvatarVariant> profileAvatarVariants = _build();

/// Значки вариантов: у каждого индекса свой — аватарка узнаваема без цвета.
/// Набор «человечный» и небанальный (природа, еда, спорт, музыка, космос) —
/// 48 разных глифов на 48 вариантов, повторов нет.
const List<IconData> _avatarIcons = [
  Icons.local_fire_department,
  Icons.water_drop,
  Icons.auto_awesome,
  Icons.eco,
  Icons.wb_sunny,
  Icons.favorite,
  Icons.nightlight,
  Icons.cruelty_free,
  Icons.star,
  Icons.bolt,
  Icons.diamond,
  Icons.spa,
  Icons.pets,
  Icons.cake,
  Icons.icecream,
  Icons.coffee,
  Icons.local_florist,
  Icons.emoji_nature,
  Icons.park,
  Icons.forest,
  Icons.waves,
  Icons.cloud,
  Icons.umbrella,
  Icons.beach_access,
  Icons.terrain,
  Icons.volcano,
  Icons.ac_unit,
  Icons.grain,
  Icons.thunderstorm,
  Icons.air,
  Icons.bubble_chart,
  Icons.palette,
  Icons.brush,
  Icons.colorize,
  Icons.music_note,
  Icons.headphones,
  Icons.videogame_asset,
  Icons.sports_esports,
  Icons.sports_basketball,
  Icons.sports_soccer,
  Icons.rocket_launch,
  Icons.sailing,
  Icons.hiking,
  Icons.snowboarding,
  Icons.downhill_skiing,
  Icons.kayaking,
  Icons.nights_stay,
  Icons.egg_alt,
];

List<ProfileAvatarVariant> _build() {
  final out = <ProfileAvatarVariant>[];
  for (var i = 0; i < 48; i++) {
    // Красный с лёгким сдвигом оттенка и светлоты: варианты различаются, но
    // остаются ОДНИМ тоном — «монотонные красные», без пестроты.
    final hue = (352.0 + (i % 5) * 4.0) % 360.0;
    final light = 0.46 + 0.05 * ((i ~/ 5) % 3);
    final sat = 0.58 + 0.06 * (i % 2);
    final color = HSLColor.fromAHSL(1, hue, sat, light).toColor();
    out.add(
      ProfileAvatarVariant([color], _avatarIcons[i % _avatarIcons.length]),
    );
  }
  return out;
}

/// Цвета аватарки по индексу (с защитой от выхода за границы списка).
List<Color> profileAvatarColors(int index) {
  final i = index % profileAvatarVariants.length;
  return profileAvatarVariants[i].colors;
}

IconData profileAvatarIcon(int index) {
  final i = index % profileAvatarVariants.length;
  return profileAvatarVariants[i].icon;
}

/// Круглая аватарка: либо своя картинка из галереи ([imagePath]), либо
/// сгенерированный «стеклянный» шар — красный градиент с блестящими пятнами и
/// чистой обводкой, как у кружков привычек.
///
/// Смена варианта — мягкий кросс-фейд с лёгким «проявлением» (без разрывов и
/// разрезов): картинка меняется плавно и цельно.
///
/// [parallax] сдвигает содержимое внутри круга: при прокрутке экрана аватарка
/// «плывёт» — своя фотография панорамируется в круглом окне, а у
/// сгенерированного шара мягко уезжают значок и блики. Обводка при этом
/// стоит на месте, поэтому круг не «дышит» размером.
///
/// [blur] — мягкое расфокусирование СОДЕРЖИМОГО внутри круга (не всей
/// аватарки): при уходе под верхнюю полку своя фотография расплывается
/// плавно, оставаясь ровным кругом — без «разрезов» по краю.
class ProfileAvatar extends StatelessWidget {
  /// Максимальная сигма расфокуса (полный уход авы под полку). Кросс-фейд
  /// считает долю именно от неё, поэтому значение одно на всех.
  static const double _maxBlurSigma = 12;

  final int index;
  final double size;
  final bool showIcon;

  /// Своя аватарка из галереи. Пока путь задан — показывается она, а не
  /// сгенерированный вариант.
  final String? imagePath;

  /// Вертикальный сдвиг содержимого внутри круга, px (для параллакса).
  final double parallax;

  /// Радиус расфокуса содержимого, px. 0 — чётко.
  final double blur;

  /// Живой источник прокрутки: если задан, аватарка сама слушает его и
  /// перестраивает ТОЛЬКО свой слой (сдвиг + расфокус), а не пересобирается
  /// родителем на каждом кадре прокрутки. Раньше `AnimatedBuilder` стоял ВНЕ
  /// виджета, и каждый кадр пересобирал всю аватарку целиком — на слабом
  /// телефоне прокрутка профиля «лагала».
  final Listenable? motion;

  /// Прогресс 0…1 для [motion] (например, `offset / 140`). Вызывается на
  /// каждом кадре только внутри слоя аватарки.
  final double Function()? motionOf;

  const ProfileAvatar({
    super.key,
    required this.index,
    this.size = 44,
    this.showIcon = true,
    this.imagePath,
    this.parallax = 0,
    this.blur = 0,
    this.motion,
    this.motionOf,
  });

  /// Итоговый радиус расфокуса. Источник — [motionOf] (сглаженная кривая
  /// прокрутки) либо статический [blur].
  double get _sigma {
    if (motion != null && motionOf != null) {
      // Пентак: нулевая скорость и УСКОРЕНИЕ на обоих концах хода.
      // `easeInOut` (квадратичная) всё равно «выстреливала» в первый кадр
      // прокрутки — расфокус появлялся скачком и читался «неплавно». Пятая
      // степень сглаживает старт и финиш вдвое лучше: размытие «наползает»
      // и так же мягко уходит, без видимых стыков.
      final t0 = motionOf!().clamp(0.0, 1.0);
      final t = t0 * t0 * t0 * (t0 * (t0 * 6 - 15) + 10);
      return t * _maxBlurSigma;
    }
    return blur;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduceMotion;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 340),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [...previous, ?current],
      ),
      // Смена авы — мягкая проявка с лёгким «дыханием» масштаба: круг
      // появляется плавно, а не щёлкает. Кольцо своей аватарки едет ВНУТРИ
      // этого перехода — появляется и убирается вместе с картинкой.
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.92,
            end: 1,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      child: _inner(context, hasImage),
    );
  }

  /// Содержимое круга. В режиме [motion] обёрнуто в [AnimatedBuilder], который
  /// перестраивает только слой аватарки: остальное дерево (карточка, имя)
  /// прокруткой не трогается.
  Widget _inner(BuildContext context, bool hasImage) {
    final key = ValueKey(hasImage ? 'img:$imagePath' : 'v:$index');
    if (motion == null) {
      return KeyedSubtree(
        key: key,
        child: SizedBox(
          width: size,
          height: size,
          child: hasImage ? _imageAvatar(context) : _generatedAvatar(context),
        ),
      );
    }
    // Ключ — на ПРЯМОМ ребёнке `AnimatedSwitcher`: раньше он лежал на
    // `SizedBox` ВНУТРИ `AnimatedBuilder`, а сам `AnimatedBuilder` ключа не
    // имел. Переключатель видел «тот же виджет» и просто обновлял его —
    // смена аватарки происходила МГНОВЕННО, без анимации. Содержимое при
    // этом строится ВНУТРИ билдера: иначе `sigma` (растущий от прокрутки)
    // замерзал на значении последней пересборки родителя и расфокуса при
    // прокрутке не было вовсе.
    return AnimatedBuilder(
      key: key,
      animation: motion!,
      builder: (context, _) => SizedBox(
        width: size,
        height: size,
        child: hasImage ? _imageAvatar(context) : _generatedAvatar(context),
      ),
    );
  }

  /// Своя картинка из галереи: круглый кроп с тонкой полупрозрачной
  /// обводкой — она появляется вместе с картинкой (кросс-фейд) и мягко
  /// уходит, когда возвращаешься на стандартную аватарку.
  ///
  /// Размытие — ВНУТРИ клипа, вокруг самой картинки: расфокус не выходит за
  /// круг, поэтому его край остаётся ровным по всему периметру (раньше фильтр
  /// стоял СНАРУЖИ клипа и размывал сам овал — сверху, где клип совпадал с
  /// тенью карточки, кант «плыл» и читался неровным). Слои упорядочены от
  /// дешёвого к дорогому: слой размытия кэшируется, а параллакс — только
  /// сдвиг готового слоя.
  ///
  /// Сигма размытия КВАНТУЕТСЯ: непрерывное значение пересобирало фильтр
  /// каждый кадр прокрутки, и размытие «лагало». На ступенях пересборки нет.
  /// Слой картинки с расфокусом.
  ///
  /// Анимированное размытие — КРОСС-ФЕЙД двух готовых слоёв: резкого и
  /// заранее размытого на постоянную сигму. `ImageFiltered` пересобирает
  /// фильтр при каждом новом значении сигмы, а прокрутка меняет её каждый
  /// кадр — именно это и «тормозило». Теперь сигма у слоя НЕ меняется (фильтр
  /// кэширован), а каждый кадр меняется только `Opacity` — дешёвая операция
  /// поверх готового растра. Статический [blur] (без прокрутки) рисуется
  /// напрямую: там сигма постоянна и пересборки нет.
  Widget _blurLayer(Widget content, double sigma, {required bool animated}) {
    if (sigma <= 0.2 || MotionPrefs.shouldReduceMotion) return content;
    if (!animated) {
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: content,
      );
    }
    // НАСТОЯЩИЙ кросс-фейд: резкий слой ГАСНЕТ, размытый ПРОЯВЛЯЕТСЯ. Раньше
    // размытая копия просто ложилась ПОВЕРХ резкой — резкая картинка никуда
    // не девалась и «съедала» расфокус, поэтому размытие читалось слабым,
    // будто его почти нет.
    // Оба слоя — под `RepaintBoundary`: сигма размытия ПОСТОЯННА, поэтому
    // при прокрутке перерисовывается только прозрачность, а растры слоёв
    // берутся из кэша. Без этого размытый слой растеризовался каждый кадр,
    // и профиль «подлагивал».
    final amount = (sigma / _maxBlurSigma).clamp(0.0, 1.0);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: 1 - amount,
          child: RepaintBoundary(child: content),
        ),
        Opacity(
          opacity: amount,
          child: RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: _maxBlurSigma,
                sigmaY: _maxBlurSigma,
              ),
              child: content,
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageAvatar(BuildContext context) {
    final file = File(imagePath!);
    final sigma = _sigma <= 0.2 ? 0.0 : _sigma;
    final image = Image.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _generatedAvatar(null),
      // Файл декодируется асинхронно: пока кадр не готов, показываем
      // сгенерированную аватарку — иначе на входе в профиль на месте
      // своей авы был «пустой» круг и картинка «появлялась не сразу».
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded || frame != null) return child;
        return _generatedAvatar(null);
      },
    );
    // Раньше содержимое круга ещё и СДВИГАЛОСЬ по вертикали при прокрутке
    // (параллакс). Сдвиг уводил картинку за край окна и сверху открывалась
    // пустая полоса — «залысина». Параллакс убран: при прокрутке аватарка
    // стоит на месте и только плавно расплывается.
    final clipped = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: _blurLayer(image, sigma, animated: motion != null),
      ),
    );
    // Кольцо рисуется ПОВЕРХ картинки ВСЕГДА. Раньше оно было фоном
    // `DecoratedBox` и оказывалось ЗА клипом — то есть появлялось только
    // вместе с размытием, когда рисовалось отдельным верхним слоем.
    //
    // На тёмной теме белое кольцо 0.82 бьёт по глазам: приглушаем до 0.38 и
    // уводим к тону поверхности — край остаётся виден, но больше не слепит.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ring = SizedBox(
      key: const ValueKey('avatar_ring'),
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: dark ? 0.38 : 0.82),
            width: (size * 0.031).clamp(1.6, 3.0),
          ),
        ),
      ),
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [clipped, ring],
    );
  }

  /// Кэш «шара» по (индекс, размер, тема). Основа шара — `RadialGradient`,
  /// а `createShader` для него пересобирается на КАЖДОЙ сборке `BoxDecoration`.
  /// При прокрутке `_inner` перестраивает слой каждый кадр, то есть без кэша
  /// шейдер собирался бы 60 раз в секунду — это и «тормозило» экран профиля.
  /// Геометрия и цвета от кадра не зависят, поэтому держим готовую декорацию.
  static final Map<String, BoxDecoration> _ballCache =
      <String, BoxDecoration>{};

  static BoxDecoration _ballDecoration(int index, double size, bool dark) {
    final key = '$index|$size|${dark ? 1 : 0}';
    final cached = _ballCache[key];
    if (cached != null) return cached;
    final color = profileAvatarColors(index).first;
    final deco = BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 1.1,
        colors: [
          Color.lerp(color, Colors.white, 0.55)!.withValues(alpha: 0.72),
          color.withValues(alpha: 0.34),
          color.withValues(alpha: 0.20),
        ],
        stops: const [0.0, 0.5, 1.0],
      ),
      border: Border.all(
        // На тёмной теме обводка шара тоже мягче — плотный кант светился
        // вокруг круга.
        color: color.withValues(alpha: dark ? 0.46 : 0.70),
        width: 2,
      ),
    );
    if (_ballCache.length > 240) _ballCache.clear();
    _ballCache[key] = deco;
    return deco;
  }

  Widget _generatedAvatar(BuildContext? context) {
    final dark = context == null
        ? false
        : Theme.of(context).brightness == Brightness.dark;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Основа: мягкий градиент — светлое «стеклянное» пятно сверху-слева,
        // к плотному красному внизу. Ровная обводка как у кружков привычек.
        Positioned.fill(
          child: DecoratedBox(decoration: _ballDecoration(index, size, dark)),
        ),
        Positioned.fill(
          // Расфокус содержимого шара — ТЕМ ЖЕ конвейером, что у своей
          // фотографии. Раньше у сгенерированной авы (а это у большинства
          // пользователей) размытие не применялось вовсе: `blur`/`motion`
          // учитывались только в ветке с картинкой, поэтому при прокрутке
          // шар лишь чуть сдвигался, а расфокуса не было — «размытие
          // незаметное».
          child: RepaintBoundary(
            child: _blurLayer(
              Stack(
                clipBehavior: Clip.none,
                children: [
                  if (showIcon)
                    Center(
                      child: Icon(
                        profileAvatarIcon(index),
                        size: size * 0.44,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  // Блестящие пятна: яркий «зайчик» и вторичный, слабее —
                  // аватарка читается как объёмный стеклянный шарик.
                  Positioned(
                    left: size * 0.22,
                    top: size * 0.18,
                    child: _gloss(size * 0.20, 0.60),
                  ),
                  Positioned(
                    left: size * 0.42,
                    top: size * 0.33,
                    child: _gloss(size * 0.09, 0.40),
                  ),
                ],
              ),
              // Размываем шар ТОЛЬКО когда он и есть аватарка. Внутри
              // ветки своей картинки `_generatedAvatar` играет роль
              // заглушки на время декода кадра — там расфокус не нужен
              // (и добавил бы второй `ImageFiltered` поверх настоящего).
              // Квантование до целых — только для СТАТИЧного [blur]: там
              // `ImageFiltered` пересобирает фильтр при каждом новом значении
              // сигмы. В режиме [motion] кросс-фейд идёт по ПОСТОЯННОЙ
              // сигме (фильтр кэширован, меняется только прозрачность
              // слоёв), поэтому передаём полную дробную сигму — иначе
              // расфокус шёл ступенями и читался «неплавно».
              imagePath == null && _sigma > 0.2
                  ? (motion != null ? _sigma : _sigma.roundToDouble())
                  : 0.0,
              animated: motion != null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _gloss(double diameter, double alpha) => Container(
    width: diameter,
    height: diameter,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}
