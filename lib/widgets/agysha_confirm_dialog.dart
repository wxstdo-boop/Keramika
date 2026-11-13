import 'package:flutter/material.dart';

import '../l10n/translations.dart';

import '../utils/design_tokens.dart';
import 'press_scale.dart';

/// Единая «стеклянная» карточка подтверждения — вместо системного
/// [AlertDialog].
///
/// Тот же вид, что у окна сброса ивента: полупрозрачный алый кант бренда,
/// подложка с красным отливом (сквозь неё просвечивает фон) и мягкие тени.
/// Системный `AlertDialog` на дефолтной палитре выходил плоской серой плашкой,
/// выбивался из «кровавой» семьи, а его кнопки не отдавали под пальцем.
///
/// Раскладка нарочно простая: одна колонка, одинаковые поля, кнопки в общей
/// строке равной ширины — окно не «косит» ни на узком экране, ни при
/// увеличенном системном шрифте. [destructive] подкрашивает кнопку
/// подтверждения алым (удаление/сброс), иначе она идёт акцентом темы.
class AgyshaConfirmDialog extends StatelessWidget {
  const AgyshaConfirmDialog({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.confirmLabel,
    this.cancelLabel,
    this.onConfirm,
    this.onCancel,
    this.destructive = false,
  });

  final String title;

  /// Текст под заголовком. Может быть длинным — переносится и центрируется
  /// по левому краю, как обычный абзац.
  final String? body;

  /// Значок в кружке слева от заголовка. Без него строка заголовка занимает
  /// всю ширину.
  final IconData? icon;

  /// Подпись кнопки подтверждения. По умолчанию — «ОК».
  final String? confirmLabel;

  /// Подпись кнопки отмены. По умолчанию — «Отмена».
  final String? cancelLabel;

  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  /// Подтверждение — разрушающее (удаление/сброс): кнопка в брендовом алом.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.red.withValues(alpha: 0.55),
                  BrandColors.red.withValues(alpha: 0.22),
                  BrandColors.red.withValues(alpha: 0.46),
                ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.22),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              // Радиус подложки на толщину канта меньше внешнего: иначе кант
              // «съедается» и кромка читается неровной.
              borderRadius: BorderRadius.circular(Radii.xl - 1.4),
              child: Container(
                decoration: BoxDecoration(
                  // Полупрозрачная подложка с красным отливом: фон
                  // просвечивает, но плотности хватает, чтобы текст читался.
                  // Без `BackdropFilter` — размытие под анимацией всплытия
                  // мерцает.
                  color: Color.alphaBlend(
                    BrandColors.red.withValues(alpha: 0.24),
                    cs.surfaceContainerHigh.withValues(alpha: 0.90),
                  ),
                  borderRadius: BorderRadius.circular(Radii.xl - 1.4),
                  border: Border.all(
                    color: BrandColors.red.withValues(alpha: 0.30),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (icon != null) ...[
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: BrandColors.red.withValues(alpha: 0.16),
                            ),
                            child: Center(
                              child: Icon(
                                icon,
                                size: 20,
                                color: BrandColors.red,
                              ),
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: Weights.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (body != null) ...[
                      const SizedBox(height: Spacing.sm),
                      Text(
                        body!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: PressScale(
                            // Отдача нарочно СЛАБАЯ (0.97) и мягкая на
                            // отпускании: заметный «провал» кнопки читался
                            // лишней суетой.
                            pressedScale: 0.97,
                            duration: const Duration(milliseconds: 180),
                            releaseDuration: const Duration(milliseconds: 300),
                            child: TextButton(
                              onPressed:
                                  onCancel ??
                                  () => Navigator.pop(context, false),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                cancelLabel ?? Translations.cancelOf(context),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: PressScale(
                            pressedScale: 0.97,
                            duration: const Duration(milliseconds: 180),
                            releaseDuration: const Duration(milliseconds: 300),
                            child: FilledButton(
                              onPressed:
                                  onConfirm ??
                                  () => Navigator.pop(context, true),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: const StadiumBorder(),
                                backgroundColor: destructive
                                    ? Color.lerp(
                                        BrandColors.red,
                                        cs.primary,
                                        0.18,
                                      )
                                    : cs.primary,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                confirmLabel ??
                                    Translations.t('ok', context, 'ОК'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Показать [AgyshaConfirmDialog] тем же мягким всплытием, что и окно сброса
/// ивента: барьер затемняет сам маршрут (одним слоем — без «вспышки»),
/// карточка входит фейдом и лёгким масштабом.
///
/// Возвращает `true`/`false` по выбору, `null` — если окно закрыли тапом по
/// фону. Вызывать через `await` ровно как системный `showDialog<bool>`.
Future<bool?> showAgyshaConfirm(
  BuildContext context, {
  required String title,
  String? body,
  IconData? icon,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, _, _) => AgyshaConfirmDialog(
      title: title,
      body: body,
      icon: icon,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      onConfirm: () => Navigator.of(ctx).pop(true),
      onCancel: () => Navigator.of(ctx).pop(false),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
