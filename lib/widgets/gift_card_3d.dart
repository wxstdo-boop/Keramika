import 'package:flutter/material.dart';

import '../models/profile_gift.dart';
import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';

/// Интерактивная 3D-карточка коллекционного подарка/артефакта в профиле.
///
/// Поддерживает:
/// - Тактильный 3D-тилт (наклон по оси X и Y при касании и свайпе)
/// - Голографический фольгированный перелив (specular foil shine)
/// - Градиент редкости (Common, Rare, Epic, Legendary)
/// - Серийный номер артефакта (#0042)
/// - Осмотр в детальном диалоге с историей и баффами
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
      builder: (ctx) => _GiftDetailsSheet(gift: widget.gift),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rarity = widget.gift.rarity;

    return AnimatedBuilder(
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
            child: child,
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
                    const Color(0xFF1E1E2E),
                    const Color(0xFF13131F),
                  ]
                : [
                    Colors.white,
                    const Color(0xFFF1F5F9),
                  ],
          ),
          border: Border.all(
            color: rarity.color.withValues(alpha: dark ? 0.60 : 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: rarity.color.withValues(alpha: dark ? 0.25 : 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Stack(
            children: [
              // Голографический фольгированный блик (Holo shine)
              Positioned.fill(
                child: CustomPaint(
                  painter: _HoloFoilPainter(
                    tilt: _tilt,
                    rarityColor: rarity.color,
                  ),
                ),
              ),
              // Содержимое карточки
              Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Верхний ряд: Редкость и Серийник
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
                              color: rarity.color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(Radii.xs),
                              border: Border.all(
                                color: rarity.color.withValues(alpha: 0.40),
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
                        Text(
                          '#${widget.gift.serialNumber.toString().padLeft(4, '0')}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
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
                              rarity.color.withValues(alpha: 0.35),
                              rarity.color.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Icon(
                          widget.gift.icon,
                          size: 38,
                          color: rarity.color,
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
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Метка избранного талисмана
              if (widget.gift.isFavorite)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Colors.amber.shade400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Художественный шейдер голографического блика (фольги)
class _HoloFoilPainter extends CustomPainter {
  final Offset tilt;
  final Color rarityColor;

  _HoloFoilPainter({
    required this.tilt,
    required this.rarityColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shiftX = tilt.dx * 0.45;
    final shiftY = tilt.dy * 0.45;

    final gradient = LinearGradient(
      begin: Alignment(-1.0 + shiftX, -1.0 + shiftY),
      end: Alignment(1.0 + shiftX, 1.0 + shiftY),
      colors: [
        Colors.white.withValues(alpha: 0.0),
        rarityColor.withValues(alpha: 0.12),
        Colors.white.withValues(alpha: 0.28),
        rarityColor.withValues(alpha: 0.12),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
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

/// Модальный лист детального осмотра артефакта
class _GiftDetailsSheet extends StatefulWidget {
  final ProfileGift gift;

  const _GiftDetailsSheet({required this.gift});

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
        color: dark ? const Color(0xFF161622) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Верхняя полоска драга
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Огромная 3D иконка артефакта
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    rarity.color.withValues(alpha: 0.40),
                    rarity.color.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Icon(
                widget.gift.icon,
                size: 56,
                color: rarity.color,
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.gift.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        widget.gift.buffText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Кнопка «Сделать главным талисманом»
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _fav ? Colors.amber.shade700 : theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      await Haptics.select();
                      await ProfileService().toggleGiftFavorite(widget.gift.id);
                      if (mounted) {
                        setState(() => _fav = !_fav);
                      }
                    },
                    icon: Icon(_fav ? Icons.star_rounded : Icons.star_outline_rounded),
                    label: Text(
                      _fav ? 'Главный талисман' : 'Выбрать талисманом',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}
