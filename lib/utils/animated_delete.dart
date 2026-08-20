import 'package:flutter/material.dart';
import '../l10n/translations.dart';

/// Builds a nice red delete background with rounded corners, icon and label.
///
/// [borderRadius] matches the radius of the card being swiped, so the red
/// background lines up with the card corners. Defaults to 20, which is the
/// radius used by most cards in the app.
Widget animatedDeleteBackground(
  BuildContext context, {
  double borderRadius = 20,
}) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
      ),
    ),
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 24),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.delete_outline, color: Colors.white, size: 24),
        const SizedBox(width: 8),
        Text(
          Translations.deleteOf(context),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}
