import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Вариант аватарки «керамика-юзера»: красный тон со «стеклянным» блеском.
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
/// Смена — плавный «РАЗРЫВ»: аватарка расходится по горизонтальному шву на две
/// половины и снова сходится, без размытия (saveLayer на слабом GPU дорог и
/// читался как «мыло»). Эффект собран на клипах и сдвигах — дёшево и чётко.
class ProfileAvatar extends StatelessWidget {
  final int index;
  final double size;
  final bool showIcon;

  /// Своя аватарка из галереи. Пока путь задан — показывается она, а не
  /// сгенерированный вариант.
  final String? imagePath;

  const ProfileAvatar({
    super.key,
    required this.index,
    this.size = 44,
    this.showIcon = true,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduceMotion;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 460),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) =>
          _AvatarTear(progress: anim.value, size: size, child: child),
      child: SizedBox(
        key: ValueKey(hasImage ? 'img:$imagePath' : 'v:$index'),
        width: size,
        height: size,
        child: hasImage ? _imageAvatar() : _generatedAvatar(context),
      ),
    );
  }

  /// Своя картинка из галереи: круглый кроп с той же обводкой, что у
  /// сгенерированных вариантов, — аватарка не выбивается из ряда.
  Widget _imageAvatar() {
    final file = File(imagePath!);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.70), width: 2),
      ),
      child: ClipOval(
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _generatedAvatar(null),
        ),
      ),
    );
  }

  Widget _generatedAvatar(BuildContext? context) {
    final color = profileAvatarColors(index).first;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Основа: мягкий градиент — светлое «стеклянное» пятно сверху-слева,
        // к плотному красному внизу. Ровная обводка как у кружков привычек.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
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
                color: color.withValues(alpha: 0.70),
                width: 2,
              ),
            ),
          ),
        ),
        if (showIcon)
          Center(
            child: Icon(
              profileAvatarIcon(index),
              size: size * 0.44,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        // Блестящие пятна: яркий «зайчик» и вторичный, слабее — аватарка
        // читается как объёмный стеклянный шарик.
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

/// «Разрыв» аватарки при смене: две половины (верх/низ) расходятся по
/// горизонтальному шву и снова сходятся. [progress] 1 — целый кадр, 0 —
/// максимально разведённый. Без blur и saveLayer: только ClipRect + сдвиг,
/// поэтому на бюджетнике эффект остаётся чётким и дешёвым.
class _AvatarTear extends StatelessWidget {
  final double progress;
  final double size;
  final Widget child;

  const _AvatarTear({
    required this.progress,
    required this.size,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    // Максимальный развод половин — заметный, но не «распад».
    final tear = (1 - t) * size * 0.34;
    // Яркий шов в момент расхождения: тонкая линия по месту разрыва.
    final seam = math.sin(math.pi * t) * 0.55;
    return Opacity(
      // Лёгкая проявка поверх разрыва — смена читается мягче.
      opacity: 0.55 + 0.45 * t,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 0.5,
              child: Transform.translate(
                offset: Offset(-tear * 0.5, -tear * 0.35),
                child: SizedBox(width: size, height: size, child: child),
              ),
            ),
          ),
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 0.5,
              child: Transform.translate(
                offset: Offset(tear * 0.5, tear * 0.35),
                child: SizedBox(width: size, height: size, child: child),
              ),
            ),
          ),
          if (seam > 0.01)
            Positioned(
              top: size / 2 - 1,
              left: size * 0.12,
              right: size * 0.12,
              child: Container(
                height: 1.4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: seam),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: seam * 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
