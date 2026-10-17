/// habits_screen - extracted part file.
part of 'habits_screen.dart';

/// Drag-ручка карточки привычки: долгое нажатие начинает перетаскивание
/// в ReorderableListView (index — позиция в текущем списке).
class _HabitDragHandle extends StatelessWidget {
  final int index;
  final Widget child;
  const _HabitDragHandle({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return ReorderableDelayedDragStartListener(index: index, child: child);
  }
}

/// Абстракция «какой индекс использовать для карточки»: для плоского списка
/// локальный и drag-индекс совпадают; для секции это локальный индекс
/// внутри секции.
abstract class IndexSource {
  int localIndex(BuildContext context, List<Habit> habits);
  int dragIndex(BuildContext context, List<Habit> habits);
}

class _FlatIndexSource implements IndexSource {
  final int index;
  const _FlatIndexSource(this.index);

  @override
  int localIndex(BuildContext context, List<Habit> habits) => index;

  @override
  int dragIndex(BuildContext context, List<Habit> habits) => index;
}

class _SectionIndexSource implements IndexSource {
  final int index;
  final List<Habit> sectionHabits;
  const _SectionIndexSource(this.index, this.sectionHabits);

  @override
  int localIndex(BuildContext context, List<Habit> habits) => index;

  @override
  int dragIndex(BuildContext context, List<Habit> habits) {
    final habit = sectionHabits[index];
    final global = habits.indexOf(habit);
    return global < 0 ? index : global;
  }
}

/// Мелкие «кровавые» пятнышки на таблетке «Сегодня очищено».
///
/// Пятна рисуются ПОД текстом (painter у CustomPaint), поэтому буквы
/// остаются чистыми, а заливка выглядит подтёкшей. Никаких размытий —
/// только чистые заливки, чтобы на Adreno не появлялись «серые квадраты».
class _BloodSpeckPainter extends CustomPainter {
  const _BloodSpeckPainter({this.isDark = false});

  /// На тёмной теме заливка тонкая и тёмная, поэтому пятнышки чуть плотнее
  /// и светлее — иначе они пропадали вовсе.
  final bool isDark;

  /// x, y (доли ширины/высоты), радиус (доля высоты), плотность (0..1).
  static const List<List<double>> _spots = [
    [0.05, 0.34, 0.15, 0.85],
    [0.13, 0.74, 0.09, 0.55],
    [0.22, 0.30, 0.07, 0.45],
    [0.33, 0.78, 0.11, 0.65],
    [0.44, 0.26, 0.06, 0.40],
    [0.55, 0.72, 0.08, 0.52],
    [0.66, 0.34, 0.07, 0.44],
    [0.76, 0.76, 0.12, 0.60],
    [0.86, 0.32, 0.06, 0.38],
    [0.95, 0.62, 0.09, 0.50],
  ];

  static const Color _dry = Color(0xFF3C0206);
  static const Color _wet = Color(0xFFFF8A90);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    for (final s in _spots) {
      final center = Offset(size.width * s[0], size.height * s[1]);
      final r = size.height * s[2];
      final density = s[3];
      final dryPaint = Paint()
        ..color = _dry.withValues(
          alpha: (isDark ? 0.52 : 0.34) * density,
        );
      // Основное пятнышко.
      canvas.drawCircle(center, r, dryPaint);
      // Мазок рядом — пятно получается неровным, «живым».
      canvas.drawCircle(
        center + Offset(r * 1.6, r * 0.5),
        r * 0.52,
        Paint()
          ..color = _dry.withValues(
            alpha: (isDark ? 0.40 : 0.24) * density,
          ),
      );
      // Влажный блик — чуть светлее заливки.
      canvas.drawCircle(
        center - Offset(r * 0.35, r * 0.4),
        r * 0.32,
        Paint()
          ..color = _wet.withValues(
            alpha: (isDark ? 0.22 : 0.14) * density,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BloodSpeckPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}



