import 'package:flutter/material.dart';

/// Единый источник правды для геометрии, движения и типографики.
///
/// Зачем: до появления этого файла по `lib/` было разбросано 26 разных
/// радиусов, 64 длительности и десяток кривых — «на глаз» это читается как
/// собранное из кусков. Здесь сведены к коротким шкалам, от которых
/// считается весь интерфейс.
///
/// Правило: новое значение берём из шкалы. Если нужного шага нет — сначала
/// спрашиваем, не подходит ли соседний, и только потом добавляем новый
/// токен осознанно, а не «ещё один магический радиус».
abstract final class Radii {
  Radii._();

  /// Мелкие элементы: чипы, значки, вложенные плашки.
  static const double xs = 8;

  /// Строки списков, небольшие карточки-строки.
  static const double sm = 12;

  /// Поля ввода, кнопки, компактные карточки.
  static const double md = 16;

  /// Обычные карточки настроек и разделов.
  static const double lg = 20;

  /// Крупные карточки, диалоги.
  static const double xl = 28;

  /// Капсула: полностью скруглённая кромка.
  static const double pill = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  /// Верхнее скругление листов (bottom sheet).
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Шкала отступов, шаг 4. Держит ритм интерфейса.
abstract final class Spacing {
  Spacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: lg,
  );
  static const EdgeInsets tileAll = EdgeInsets.all(md);
}

/// Длительности анимаций, шаг задан смыслом, а не линейкой.
abstract final class Motion {
  Motion._();

  /// Мгновенная реакция: нажатие, подсветка.
  static const Duration fast = Duration(milliseconds: 150);

  /// Обычный переход: появление, fade, смена состояния.
  static const Duration normal = Duration(milliseconds: 240);

  /// Заметный переход: страницы, листы, крупные блоки.
  static const Duration slow = Duration(milliseconds: 320);

  /// Медленный декоративный цикл (дыхание свечения).
  static const Duration ambient = Duration(milliseconds: 2600);

  /// Плавное «докатывание»: шайба переключателя, перелёт таблетки.
  static const Duration glide = Duration(milliseconds: 500);

  /// Кривая входа/выхода элементов: разгон в начале, мягкая остановка.
  static const Curve standard = Curves.easeOutCubic;

  /// Кривая двусторонних переходов: нулевая скорость на обоих концах.
  static const Curve emphasized = Curves.easeInOutCubic;

  /// Кривая «с отскоком» для появления карточек и наград.
  static const Curve overshoot = Curves.easeOutBack;
}

/// Шкала начертаний текста. Держит иерархию: чем важнее — тем жирнее.
///
/// До введения токена по проекту гуляли w300…w900 без системы: соседние по
/// смыслу заголовки набирались то w600, то w800, и экран выглядел «неровным».
abstract final class Weights {
  Weights._();

  /// Подписи, вспомогательный текст.
  static const FontWeight regular = FontWeight.w400;

  /// Мелкие подписи, где нужен минимальный акцент.
  static const FontWeight medium = FontWeight.w500;

  /// Полужирный: заголовки строк, кнопки.
  static const FontWeight semibold = FontWeight.w600;

  /// Жирный: заголовки разделов.
  static const FontWeight bold = FontWeight.w700;

  /// Самый сильный акцент: крупные числа, экранные заголовки.
  static const FontWeight heavy = FontWeight.w800;
}
