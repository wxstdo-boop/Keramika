import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Вариант аватарки «керамика-юзера»: монотонный красный тон + значок.
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

/// Круглая аватарка: монотонная полупрозрачная красная заливка и обводка —
/// та же «чистая» рамка, что у кружков привычек (без свечения и градиентов,
/// которые ловили блик и спорили с содержимым карточки).
///
/// Смена варианта — плавный кросс-фейд с лёгким «проявлением», а не подмена
/// кадром: аватарка меняется на глазах, и резкий щелчок читался бы дёшево.
class ProfileAvatar extends StatelessWidget {
  final int index;
  final double size;
  final bool showIcon;

  const ProfileAvatar({
    super.key,
    required this.index,
    this.size = 44,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = profileAvatarColors(index).first;
    final reduce = MotionPrefs.shouldReduceMotion;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(index),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Монотонная полупрозрачная заливка: ровный красный без «отсветов».
          color: color.withValues(alpha: 0.30),
          // Обводка как у кружков привычек: тонкое чистое кольцо.
          border: Border.all(color: color.withValues(alpha: 0.65), width: 2),
        ),
        alignment: Alignment.center,
        child: showIcon
            ? Icon(
                profileAvatarIcon(index),
                size: size * 0.46,
                color: color.withValues(alpha: 0.95),
              )
            : null,
      ),
    );
  }
}
