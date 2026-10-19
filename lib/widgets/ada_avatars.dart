import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/json_file.dart';
import '../services/prefs.dart';

/// Вариант аватарки Ады: градиент + значок. Общий для основного чата и
/// мини-окошка — оба движка генерируют ОДИНАКОВЫЙ список, поэтому индекс
/// варианта (индекс в [adaVariants]) означает одну и ту же аватарку везде.
class AdaVariant {
  final List<Color> colors;
  final IconData icon;

  /// Приблизительный оттенок (0-360): при смене аватарки избегаем вариантов
  /// с близким оттенком, чтобы аватарка не «дублировалась» похожими
  /// градиентами подряд.
  final double hue;
  const AdaVariant(this.colors, this.icon, {this.hue = 0});
}

/// Все варианты Ады: 6 авторских + 114 сгенерированных = 120 уникальных
/// градиентов. Индекс выбранного сохраняется в prefs ('ada_avatar_variant')
/// и переживает перезапуск; тап по аватарке/имени меняет его. Генерация
/// детерминированная — порядок стабилен между запусками и движками.
final List<AdaVariant> adaVariants = _buildAdaVariants();

List<AdaVariant> _buildAdaVariants() {
  const specials = <AdaVariant>[
    AdaVariant(
      [Color(0xFFFF9EC6), Color(0xFFB06AB3), Color(0xFF7C4DFF)],
      Icons.favorite,
      hue: 335,
    ),
    AdaVariant(
      [Color(0xFFFFB199), Color(0xFFFF6B9D), Color(0xFFE63946)],
      Icons.local_florist,
      hue: 350,
    ),
    AdaVariant(
      [Color(0xFF9BE8FF), Color(0xFF7C4DFF), Color(0xFF2E3192)],
      Icons.auto_awesome,
      hue: 268,
    ),
    AdaVariant(
      [Color(0xFF8BF0C8), Color(0xFF2BB3A0), Color(0xFF0F6E6E)],
      Icons.wb_sunny,
      hue: 168,
    ),
    AdaVariant(
      [Color(0xFFFFD166), Color(0xFFFF8C42), Color(0xFFD62828)],
      Icons.star,
      hue: 36,
    ),
    AdaVariant(
      [Color(0xFFC9B8FF), Color(0xFF8E7CFF), Color(0xFF4A3F9E)],
      Icons.psychology,
      hue: 255,
    ),
  ];
  // Набор значков: повторяется через каждые 24 варианта, но hue каждый раз
  // другой (шаг 47° по цветовому кругу) — комбинации не повторяются.
  const icons = <IconData>[
    Icons.favorite,
    Icons.local_florist,
    Icons.auto_awesome,
    Icons.wb_sunny,
    Icons.star,
    Icons.psychology,
    Icons.bolt,
    Icons.flare,
    Icons.water_drop,
    Icons.eco,
    Icons.rocket_launch,
    Icons.diamond,
    Icons.energy_savings_leaf,
    Icons.nights_stay,
    Icons.face_retouching_natural,
    Icons.celebration,
    Icons.shield_moon,
    Icons.spa,
    Icons.forest,
    Icons.emoji_emotions,
    Icons.light_mode,
    Icons.wb_twilight,
    Icons.air,
    Icons.blur_on,
    Icons.whatshot,
    Icons.mood,
    Icons.emoji_nature,
    Icons.self_improvement,
    Icons.waving_hand,
    Icons.sentiment_very_satisfied,
    Icons.volcano,
    Icons.flutter_dash,
    Icons.nightlight,
    Icons.brightness_5,
    Icons.waves,
    Icons.local_fire_department,
    Icons.eco,
    Icons.psychology_alt,
    Icons.heart_broken,
    Icons.emoji_objects,
  ];
  final generated = <AdaVariant>[];
  for (var i = 0; i < 114; i++) {
    final hue = (i * 47) % 360;
    final band = i ~/ 24;
    final sat = (0.52 + 0.30 * (band % 3)).clamp(0.0, 1.0);
    final light = (0.46 + 0.16 * ((band ~/ 3) % 3)).clamp(0.0, 1.0);
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), sat, light).toColor();
    final c2 = HSLColor.fromAHSL(
      1,
      ((hue + 36) % 360).toDouble(),
      sat,
      (light - 0.10).clamp(0.0, 1.0),
    ).toColor();
    final c3 = HSLColor.fromAHSL(
      1,
      ((hue + 72) % 360).toDouble(),
      sat,
      (light - 0.20).clamp(0.0, 1.0),
    ).toColor();
    generated.add(
      AdaVariant([c1, c2, c3], icons[i % icons.length], hue: hue.toDouble()),
    );
  }
  return [...specials, ...generated];
}

/// Тональная «монохромная» гамма аватарки Ады из текущей темы. Общая для
/// основного чата и мини-окошка, чтобы они выглядели одинаково и менялись
/// вместе с темой.
List<Color> themeAdaColors(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return <Color>[
    cs.primary,
    Color.lerp(cs.primary, cs.tertiary, 0.55)!,
    cs.tertiary,
  ];
}

/// Сохранённый индекс варианта (переживает перезапуск; общий для движков).
int savedAdaAvatarIndex() => (globalPrefs.getInt('ada_avatar_variant') ?? 0)
    .clamp(0, adaVariants.length - 1);

/// Живой индекс значка Ады: ВСЕ аватарки (шапка, пузыри сообщений,
/// плавающее мини-окошко) следят за ним и меняются мгновенно и плавно,
/// где бы их ни нажали. Общий для обоих движков.
final ValueNotifier<int> adaAvatarVariant = ValueNotifier<int>(
  savedAdaAvatarIndex(),
);

/// Сохраняет выбранный индекс (общий для движков) и уведомляет аватарки.
void setAdaAvatarVariant(int index) {
  final v = index.clamp(0, adaVariants.length - 1);
  adaAvatarVariant.value = v;
  try {
    globalPrefs.setInt('ada_avatar_variant', v);
  } catch (_) {}
}

/// Синхронизация между ДВУМЯ движками (главный чат ↔ мини-окошко):
/// shared_preferences кэширует значение в памяти каждого движка, поэтому
/// пишем состояние в ФАЙЛ (JsonFile читает с диска) — другой движок увидит
/// изменение опросом, без хрупкого канала сообщений.
Future<void> writeAdaSyncState({
  int? avatar,
  String? model,
  int? historyRev,
}) async {
  try {
    final raw = await JsonFile.read('ada_sync_state');
    final map = (raw != null && raw.isNotEmpty)
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : <String, dynamic>{};
    if (avatar != null) map['avatar'] = avatar;
    if (model != null && model.isNotEmpty) map['model'] = model;
    if (historyRev != null) map['historyRev'] = historyRev;
    map['ts'] = DateTime.now().millisecondsSinceEpoch;
    await JsonFile.writeWithSnapshot('ada_sync_state', jsonEncode(map), raw);
  } catch (_) {}
}

/// Читает синхронизированное состояние ({'avatar': int?, 'model': String?}).
Future<Map<String, dynamic>> readAdaSyncState() async {
  try {
    final raw = await JsonFile.read('ada_sync_state');
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return <String, dynamic>{};
  }
}

/// Аватарка Ады — градиентный кружок с бликом.
/// [variantIndex] — индекс в [adaVariants]; -1 — следит за живым
/// [adaAvatarVariant] и меняется плавно сам.
class AdaAvatar extends StatelessWidget {
  final double size;
  final int variantIndex;
  const AdaAvatar({super.key, this.size = 34, this.variantIndex = -1});

  @override
  Widget build(BuildContext context) {
    if (variantIndex >= 0 && variantIndex < adaVariants.length) {
      // Статичный индекс: родитель сам анимирует смену (AnimatedSwitcher
      // в мини-окошке).
      return _core(context, adaVariants[variantIndex]);
    }
    // Живой режим: следит за [adaAvatarVariant] и плавно меняется сам —
    // везде, где аватарка может смениться (шапка, пузыри сообщений,
    // подсказки), без дополнительных обёрток.
    return ValueListenableBuilder<int>(
      valueListenable: adaAvatarVariant,
      builder: (context, idx, _) => AnimatedSwitcher(
        // Чуть дольше и с мягкой пружинкой: смена аватарки читается как
        // «живой» поворот значка, а не резкий щелчок.
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.72,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey('ada_av_$idx'),
          child: _core(context, adaVariants[idx]),
        ),
      ),
    );
  }

  Widget _core(BuildContext context, AdaVariant v) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    // Монохромная тональная гамма из ТЕКУЩЕЙ темы: аватарка автоматически
    // подстраивается под смену темы (primary → secondary → tertiary),
    // а не остаётся ярким цветным кружком в любой теме.
    final ramp = themeAdaColors(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ramp,
        ),
        // Тонкое адаптивное кольцо: полупрозрачная, почти чёрная обводка
        // как у снекбаров — только тоньше и чище. Аватарка аккуратно «садится»
        // в любую тему, не торча цветным кружком.
        border: Border.all(
          color: Colors.black.withValues(alpha: dark ? 0.22 : 0.26),
          width: 1.0,
        ),
        // Без тени: в мини-окошке blur-тень обрезается прямоугольной
        // границей окна и выглядит как «квадрат» за круглой аватаркой.
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Блик сверху — «стеклянный» объём.
          Positioned(
            top: size * 0.06,
            left: size * 0.16,
            child: Container(
              width: size * 0.42,
              height: size * 0.24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.30 : 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Значок Ады.
          Icon(
            v.icon,
            size: size * 0.42,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ],
      ),
    );
  }
}
