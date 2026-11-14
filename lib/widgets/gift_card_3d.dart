import 'package:flutter/material.dart';

import '../models/profile_gift.dart';
import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import 'press_scale.dart';

/// Интерактивная 3D-карточка коллекционного NFT-артефакта в стиле Cyberpunk / Telegram Gifts.
///
/// Особенности:
/// - Тактильный 3D-тилт по матрице перспективной глубины
/// - Кроваво-голографический перелив (specular blood-holo foil shine)
/// - Четкое разделение серийного номера и кровавой звездочки талисмана (без наездов)
/// - Плавное открытие детального окна с отдачей кнопок при нажатии
class GiftCard3D extends StatefulWidget {
  final ProfileGift gift;
  final double width;
  final double height;
  final VoidCallback? onFavoriteToggled;

  const GiftCard3D({
    super.key,
    required this.gift,
    this.width = 160,
    this.height = 210,
    this.onFavoriteToggled,
  });

  @override
  State<GiftCard3D> createState() => _GiftCard3DState();
}

class _GiftCard3DState extends State<GiftCard3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _resetController;
  late Animation<Offset> _tiltAnimation;

  Offset _tilt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _tiltAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resetController,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (MotionPrefs.shouldReduceMotion) return;
    _resetController.stop();
    setState(() {
      final dx = (details.localPosition.dx / widget.width - 0.5) * 2.0;
      final dy = (details.localPosition.dy / widget.height - 0.5) * 2.0;
      _tilt = Offset(
        dx.clamp(-1.0, 1.0),
        dy.clamp(-1.0, 1.0),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (MotionPrefs.shouldReduceMotion) return;
    _tiltAnimation = Tween<Offset>(
      begin: _tilt,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _resetController,
      curve: Curves.easeOutBack,
    ));
    _resetController.forward(from: 0).then((_) {
      if (mounted) setState(() => _tilt = Offset.zero);
    });
  }

  void _openDetails(BuildContext context) {
    Haptics.select();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 340),
        reverseCurve: Curves.easeInCubic,
        reverseDuration: const Duration(milliseconds: 240),
      ),
      builder: (ctx) => _GiftDetailsSheet(
        gift: widget.gift,
        onFavoriteToggled: widget.onFavoriteToggled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rarity = widget.gift.rarity;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _resetController,
        builder: (context, child) {
          final currentTilt = _resetController.isAnimating
              ? _tiltAnimation.value
              : _tilt;

          final tiltX = -currentTilt.dy * 0.28;
          final tiltY = currentTilt.dx * 0.28;

          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..rotateX(tiltX)
            ..rotateY(tiltY);

          return GestureDetector(
            onTap: () => _openDetails(context),
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: () => _onPanEnd(DragEndDetails()),
            child: Transform(
              transform: transform,
              alignment: FractionalOffset.center,
              child: PressScale(
                pressedScale: 0.94,
                duration: const Duration(milliseconds: 160),
                releaseDuration: const Duration(milliseconds: 260),
                child: child!,
              ),
            ),
          );
        },
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      const Color(0xFF141420),
                      const Color(0xFF0A0A12),
                    ]
                  : [
                      Colors.white,
                      const Color(0xFFF0F4F8),
                    ],
            ),
            border: Border.all(
              color: widget.gift.isFavorite
                  ? BrandColors.red.withValues(alpha: 0.70)
                  : rarity.color.withValues(alpha: dark ? 0.60 : 0.45),
              width: widget.gift.isFavorite ? 1.8 : 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.gift.isFavorite
                    ? BrandColors.red.withValues(alpha: dark ? 0.35 : 0.22)
                    : rarity.color.withValues(alpha: dark ? 0.25 : 0.16),
                blurRadius: widget.gift.isFavorite ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Stack(
              children: [
                // Голографический фольгированный блик
                Positioned.fill(
                  child: CustomPaint(
                    painter: _HoloFoilPainter(
                      tilt: _tilt,
                      rarityColor: widget.gift.isFavorite
                          ? BrandColors.red
                          : rarity.color,
                    ),
                  ),
                ),
                // Содержимое карточки
                Padding(
                  padding: const EdgeInsets.all(Spacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Верхний ряд: Редкость и Серийник (плюс звездочка без наезда)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: rarity.color.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(Radii.xs),
                                border: Border.all(
                                  color: rarity.color.withValues(alpha: 0.45),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                rarity.labelRu.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: rarity.color,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Номер и кровавая звездочка рядом
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.gift.isFavorite) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: BrandColors.red,
                                ),
                                const SizedBox(width: 2),
                              ],
                              Text(
                                '#${widget.gift.serialNumber.toString().padLeft(4, '0')}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  color: widget.gift.isFavorite
                                      ? BrandColors.red
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.60),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Центральная иконка артефакта с аурой
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                (widget.gift.isFavorite
                                        ? BrandColors.red
                                        : rarity.color)
                                    .withValues(alpha: 0.35),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Icon(
                            widget.gift.icon,
                            size: 38,
                            color: widget.gift.isFavorite
                                ? BrandColors.red
                                : rarity.color,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Название артефакта
                      Text(
                        widget.gift.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Бафф/эффект
                      Text(
                        widget.gift.buffText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.gift.isFavorite
                              ? BrandColors.red
                              : theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Художественный шейдер голографического блика (фольги) с мягким спекулярным переливом
class _HoloFoilPainter extends CustomPainter {
  final Offset tilt;
  final Color rarityColor;

  _HoloFoilPainter({
    required this.tilt,
    required this.rarityColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * (0.5 + tilt.dx * 0.40);
    final cy = size.height * (0.45 + tilt.dy * 0.40);

    final gradient = RadialGradient(
      center: Alignment(
        (cx / size.width - 0.5) * 2.0,
        (cy / size.height - 0.5) * 2.0,
      ),
      radius: 0.95,
      colors: [
        Colors.white.withValues(alpha: 0.20),
        rarityColor.withValues(alpha: 0.14),
        BrandColors.red.withValues(alpha: 0.09),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.65, 1.0],
    );

    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..blendMode = BlendMode.screen;

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _HoloFoilPainter oldDelegate) {
    return oldDelegate.tilt != tilt || oldDelegate.rarityColor != rarityColor;
  }
}

/// Модальный лист детального осмотра артефакта в стиле киберпанк
class _GiftDetailsSheet extends StatefulWidget {
  final ProfileGift gift;
  final VoidCallback? onFavoriteToggled;

  const _GiftDetailsSheet({
    required this.gift,
    this.onFavoriteToggled,
  });

  @override
  State<_GiftDetailsSheet> createState() => _GiftDetailsSheetState();
}

class _GiftDetailsSheetState extends State<_GiftDetailsSheet> {
  late bool _fav;

  @override
  void initState() {
    super.initState();
    _fav = widget.gift.isFavorite;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rarity = widget.gift.rarity;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF12121C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: _fav
              ? BrandColors.red.withValues(alpha: 0.50)
              : rarity.color.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Верхняя полоска драга
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Огромная иконка артефакта с неоновой аурой
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (_fav ? BrandColors.red : rarity.color).withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Icon(
                widget.gift.icon,
                size: 56,
                color: _fav ? BrandColors.red : rarity.color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.gift.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: rarity.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: rarity.color.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    rarity.labelRu,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: rarity.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Артефакт #${widget.gift.serialNumber.toString().padLeft(4, '0')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: _fav ? BrandColors.red : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Описание / лор
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (_fav ? BrandColors.red : rarity.color).withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.gift.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: _fav ? BrandColors.red : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.gift.buffText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _fav ? BrandColors.red : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Кнопка «Сделать главным талисманом» с ультра-плавной сменой цвета и размера
            Row(
              children: [
                Expanded(
                  child: PressScale(
                    pressedScale: 0.94,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await Haptics.select();
                        await ProfileService().toggleGiftFavorite(widget.gift.id);
                        if (mounted) {
                          setState(() => _fav = !_fav);
                        }
                        widget.onFavoriteToggled?.call();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        decoration: BoxDecoration(
                          color: _fav ? BrandColors.red : theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: (_fav ? BrandColors.red : theme.colorScheme.primary)
                                  .withValues(alpha: 0.40),
                              blurRadius: _fav ? 14 : 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOutCubic,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  child: Icon(
                                    _fav ? Icons.star_rounded : Icons.star_outline_rounded,
                                    key: ValueKey(_fav),
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: Text(
                                    _fav ? 'Главный талисман' : 'Выбрать талисманом',
                                    key: ValueKey(_fav),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                PressScale(
                  pressedScale: 0.92,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(14),
                    ),
                    onPressed: () {
                      Haptics.light();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
