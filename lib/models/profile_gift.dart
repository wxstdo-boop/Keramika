import 'package:flutter/material.dart';

import '../utils/icon_map.dart';

/// Редкость коллекционного артефакта/подарка.
enum GiftRarity {
  common,
  rare,
  epic,
  legendary;

  String get labelRu {
    switch (this) {
      case GiftRarity.common:
        return 'Обычный';
      case GiftRarity.rare:
        return 'Редкий';
      case GiftRarity.epic:
        return 'Эпический';
      case GiftRarity.legendary:
        return 'Легендарный';
    }
  }

  String get labelEn {
    switch (this) {
      case GiftRarity.common:
        return 'Common';
      case GiftRarity.rare:
        return 'Rare';
      case GiftRarity.epic:
        return 'Epic';
      case GiftRarity.legendary:
        return 'Legendary';
    }
  }

  Color get color {
    switch (this) {
      case GiftRarity.common:
        return const Color(0xFF94A3B8);
      case GiftRarity.rare:
        return const Color(0xFF818CF8);
      case GiftRarity.epic:
        return const Color(0xFFF472B6);
      case GiftRarity.legendary:
        return const Color(0xFFFBBF24);
    }
  }

  List<Color> get gradient {
    switch (this) {
      case GiftRarity.common:
        return const [Color(0xFF64748B), Color(0xFF94A3B8)];
      case GiftRarity.rare:
        return const [Color(0xFF6366F1), Color(0xFFA855F7)];
      case GiftRarity.epic:
        return const [Color(0xFFEC4899), Color(0xFFF43F5E)];
      case GiftRarity.legendary:
        return const [Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF8B5CF6)];
    }
  }
}

/// Коллекционный артефакт/подарок в профиле (в стиле NFT-подарков Telegram и трофеев Steam).
class ProfileGift {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final GiftRarity rarity;
  final int serialNumber;
  final int unlockedAt;
  final String buffText;
  final bool isFavorite;

  const ProfileGift({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.rarity,
    required this.serialNumber,
    required this.unlockedAt,
    required this.buffText,
    this.isFavorite = false,
  });

  ProfileGift copyWith({
    String? title,
    String? description,
    IconData? icon,
    GiftRarity? rarity,
    int? serialNumber,
    int? unlockedAt,
    String? buffText,
    bool? isFavorite,
  }) => ProfileGift(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    rarity: rarity ?? this.rarity,
    serialNumber: serialNumber ?? this.serialNumber,
    unlockedAt: unlockedAt ?? this.unlockedAt,
    buffText: buffText ?? this.buffText,
    isFavorite: isFavorite ?? this.isFavorite,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'iconCode': icon.codePoint,
    'iconFamily': icon.fontFamily,
    'rarity': rarity.index,
    'serial': serialNumber,
    'at': unlockedAt,
    'buff': buffText,
    'fav': isFavorite,
  };

  factory ProfileGift.fromJson(Map<String, dynamic> j) {
    final codePoint = (j['iconCode'] as num?)?.toInt() ?? Icons.star.codePoint;
    final rarityIdx = (j['rarity'] as num?)?.toInt() ?? 0;
    return ProfileGift(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      icon: iconDataForCodePoint(codePoint),
      rarity: GiftRarity.values[rarityIdx.clamp(0, GiftRarity.values.length - 1)],
      serialNumber: (j['serial'] as num?)?.toInt() ?? 1,
      unlockedAt: (j['at'] as num?)?.toInt() ?? 0,
      buffText: (j['buff'] ?? '').toString(),
      isFavorite: j['fav'] == true,
    );
  }

  /// Начальная витрина редких артефактов Agysha
  static List<ProfileGift> initialShowcase() => [
    ProfileGift(
      id: 'chrono_crystal',
      title: 'Хроно-кристалл',
      description: 'Квантовый накопитель, концентрирующий фазы глубокого сна в чистую энергию бодрости.',
      icon: Icons.diamond_outlined,
      rarity: GiftRarity.legendary,
      serialNumber: 7,
      unlockedAt: DateTime.now().millisecondsSinceEpoch - 86400000 * 5,
      buffText: '+15% к утренней бодрости',
      isFavorite: true,
    ),
    ProfileGift(
      id: 'cyber_sakura',
      title: 'Кибер-сакура',
      description: 'Лепестки из фотонного оптоволокна, пульсирующие мягким неоновым светом.',
      icon: Icons.spa_outlined,
      rarity: GiftRarity.epic,
      serialNumber: 128,
      unlockedAt: DateTime.now().millisecondsSinceEpoch - 86400000 * 3,
      buffText: '+10% к душевной гармонии',
    ),
    ProfileGift(
      id: 'neon_lotus',
      title: 'Неоновый лотос',
      description: 'Символ цифрового дзена, раскрывающийся только при идеальном режиме дня.',
      icon: Icons.local_florist_outlined,
      rarity: GiftRarity.epic,
      serialNumber: 256,
      unlockedAt: DateTime.now().millisecondsSinceEpoch - 86400000 * 2,
      buffText: '+8% к концентрации внимания',
    ),
    ProfileGift(
      id: 'golden_bell',
      title: 'Золотой будильник',
      description: 'Кованый хронометр высшей пробы, синхронизированный с космическими биоритмами.',
      icon: Icons.alarm_on_rounded,
      rarity: GiftRarity.rare,
      serialNumber: 777,
      unlockedAt: DateTime.now().millisecondsSinceEpoch - 86400000,
      buffText: '+5% к пунктуальности',
    ),
    ProfileGift(
      id: 'ada_neural_shard',
      title: 'Нейрочип Ады',
      description: 'Кристаллический чип памяти с зашифрованными алгоритмами интуиции.',
      icon: Icons.memory_rounded,
      rarity: GiftRarity.legendary,
      serialNumber: 42,
      unlockedAt: DateTime.now().millisecondsSinceEpoch - 86400000 * 7,
      buffText: '+20% к осознанности снов',
      isFavorite: true,
    ),
    ProfileGift(
      id: 'samurai_visor',
      title: 'Маска Самурая',
      description: 'Защитный визор ночных стражей Найт-Сити, блокирующий прокрастинацию.',
      icon: Icons.security_rounded,
      rarity: GiftRarity.rare,
      serialNumber: 1337,
      unlockedAt: DateTime.now().millisecondsSinceEpoch - 3600000 * 4,
      buffText: '+7% к несгибаемой воле',
    ),
  ];
}
