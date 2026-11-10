import 'package:flutter/material.dart';
import '../l10n/translations.dart';

/// Builds a nice red delete background with rounded corners, icon and label.
///
/// [borderRadius] matches the radius of the card being swiped, so the red
/// background lines up with the card corners. Defaults to 20, which is the
/// radius used by most cards in the app.
///
/// [opacity] запекается ПРЯМО В ЦВЕТА, а не навешивается сверху через
/// `Opacity`. Виджет `Opacity` каждый кадр заводит `saveLayer` — на слабом GPU
/// это лишняя композитная работа ровно там, где палец двигает плашку. Альфа в
/// градиенте и в цветах текста/иконки даёт тот же вид без слоя.
Widget animatedDeleteBackground(
  BuildContext context, {
  double borderRadius = 20,
  double opacity = 1.0,
}) {
  final a = opacity.clamp(0.0, 1.0);
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFFFF5252).withValues(alpha: a),
          const Color(0xFFFF1744).withValues(alpha: a),
        ],
      ),
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 24),
    // Плашка может быть УЖЕ своей подписи (она растёт вместе со свайпом),
    // поэтому содержимое не сжимается, а «уезжает» вправо и обрезается:
    // иконка с надписью прижаты к правому краю, левый край отсекает
    // ClipRect — без этого Row переполнялся и рисовал полосы переполнения.
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerRight,
        minWidth: 0,
        maxWidth: double.infinity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline,
              color: Colors.white.withValues(alpha: a),
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              Translations.deleteOf(context),
              style: TextStyle(
                color: Colors.white.withValues(alpha: a),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
