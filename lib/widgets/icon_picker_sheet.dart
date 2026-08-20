import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../utils/icon_map.dart';

class IconPickerSheet extends StatelessWidget {
  final int selectedCodePoint;
  const IconPickerSheet({super.key, required this.selectedCodePoint});

  static Future<int?> show(BuildContext context, int currentCodePoint) {
    return showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Та же пружинная шторка, что у мини-чата Ады.
      sheetAnimationStyle: AnimationStyle(
        curve: Curves.easeOutBack,
        duration: const Duration(milliseconds: 380),
        reverseCurve: Curves.easeInCubic,
        reverseDuration: const Duration(milliseconds: 240),
      ),
      // Закрываем фокус и НЕ вызываем requestFocus после выбора —
      // иначе системная клавиатура всплывает над списком, куда пользователь
      // вернулся (раньше это «дёргало» глаза после подбора иконки).
      builder: (ctx) => IconPickerSheet(selectedCodePoint: currentCodePoint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            Translations.t('chooseIcon', context),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              physics: const AlwaysScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.05,
              ),
              itemCount: HabitTaskIconList.picker.length,
              itemBuilder: (context, i) {
                final icon = HabitTaskIconList.picker[i];
                return _IconTile(
                  icon: icon,
                  selected: icon.codePoint == selectedCodePoint,
                  onTap: () => Navigator.pop(context, icon.codePoint),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Плитка иконки: при зажатии получает фон и лёгкое сжатие, как остальные
/// кнопки приложения (плавно, через AnimatedContainer + AnimatedScale).
class _IconTile extends StatefulWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _IconTile({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : _pressed
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: widget.selected
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: widget.selected
                ? theme.colorScheme.primary
                : _pressed
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
