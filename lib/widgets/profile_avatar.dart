import 'package:flutter/material.dart';

/// Вариант аватарки «керамика-юзера»: тройной градиент + значок.
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

/// Авторские варианты аватарки: тёплая керамика, глазурь, обжиг. Порядок
/// стабилен — индекс переживает перезапуск.
final List<ProfileAvatarVariant> profileAvatarVariants = _build();

List<ProfileAvatarVariant> _build() {
  const seed = <ProfileAvatarVariant>[
    ProfileAvatarVariant(
      [Color(0xFFFFB199), Color(0xFFFF7B54), Color(0xFFC1440E)],
      Icons.local_fire_department,
    ),
    ProfileAvatarVariant(
      [Color(0xFF9BE8FF), Color(0xFF3FA7D6), Color(0xFF1B4965)],
      Icons.water_drop,
    ),
    ProfileAvatarVariant(
      [Color(0xFFC9B8FF), Color(0xFF8E7CFF), Color(0xFF4A3F9E)],
      Icons.auto_awesome,
    ),
    ProfileAvatarVariant(
      [Color(0xFF8BF0C8), Color(0xFF2BB3A0), Color(0xFF0F6E6E)],
      Icons.eco,
    ),
    ProfileAvatarVariant(
      [Color(0xFFFFD166), Color(0xFFFF8C42), Color(0xFFD62828)],
      Icons.wb_sunny,
    ),
    ProfileAvatarVariant(
      [Color(0xFFFF9EC6), Color(0xFFB06AB3), Color(0xFF7C4DFF)],
      Icons.favorite,
    ),
    ProfileAvatarVariant(
      [Color(0xFFB8C4FF), Color(0xFF5C6BC0), Color(0xFF283593)],
      Icons.nightlight,
    ),
    ProfileAvatarVariant(
      [Color(0xFFE6C9A8), Color(0xFFB08968), Color(0xFF7F5539)],
      Icons.cruelty_free,
    ),
  ];
  const icons = <IconData>[
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
  final generated = <ProfileAvatarVariant>[];
  for (var i = 0; i < 40; i++) {
    final hue = (i * 53 + 18) % 360;
    final sat = (0.55 + 0.22 * (i % 3)).clamp(0.0, 1.0);
    final light = (0.50 + 0.12 * ((i ~/ 3) % 3)).clamp(0.0, 1.0);
    Color band(double dHue, double dLight) => HSLColor.fromAHSL(
      1,
      (hue + dHue) % 360,
      sat,
      (light + dLight).clamp(0.05, 0.95),
    ).toColor();
    generated.add(
      ProfileAvatarVariant(
        [band(-26, 0.14), band(0, 0.0), band(26, -0.16)],
        icons[i % icons.length],
      ),
    );
  }
  return [...seed, ...generated];
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

/// Круглая аватарка с градиентом и значком. [glow] добавляет мягкое свечение
/// — им пользуется шапка профиля, чтобы аватарка читалась как «живая».
class ProfileAvatar extends StatelessWidget {
  final int index;
  final double size;
  final bool glow;
  final bool showIcon;

  const ProfileAvatar({
    super.key,
    required this.index,
    this.size = 44,
    this.glow = false,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = profileAvatarColors(index);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.45),
                  blurRadius: size * 0.42,
                  spreadRadius: size * 0.04,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: showIcon
          ? Icon(
              profileAvatarIcon(index),
              size: size * 0.5,
              color: Colors.white.withValues(alpha: 0.92),
            )
          : null,
    );
  }
}
