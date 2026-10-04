import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/nutrition_service.dart';
import 'rolling_counter.dart';

/// Лист настройки личной суточной нормы калорий.
///
/// Открывается тапом по кольцу прогресса. Возвращает [Navigator.pop] с
/// сохранённым числом либо null, если пользователь отменил, — сам экран и
/// показывает ответный снекбар, чтобы лист не знал про чужие уведомления.
class NormSheet extends StatefulWidget {
  const NormSheet({super.key, required this.service});

  final NutritionService service;

  @override
  State<NormSheet> createState() => _NormSheetState();
}

class _NormSheetState extends State<NormSheet> {
  late double _draft = widget.service.norm.toDouble();

  static const List<int> _presets = [1500, 2000, 2500, 3000];

  void _save() {
    Haptics.medium();
    final v = _draft.round().clamp(kMinCalorieNorm, kMaxCalorieNorm);
    widget.service.setNorm(v);
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final number = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: _draft > widget.service.norm ? cs.tertiary : cs.primary,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Translations.t('calorieNorm', context, 'Суточная норма'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              RollingCounter(value: _draft, style: number),
              const SizedBox(width: 4),
              Text(
                Translations.t('kcalShort', context, 'ккал'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            value: _draft,
            min: kMinCalorieNorm.toDouble(),
            max: kMaxCalorieNorm.toDouble(),
            divisions: (kMaxCalorieNorm - kMinCalorieNorm) ~/ 50,
            label: '${_draft.round()}',
            onChanged: (v) => setState(() => _draft = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in _presets)
                ActionChip(
                  label: Text('$preset'),
                  // Текущая норма подсвечивается сама: слайдер шагами по 50
                  // попадает в пресеты, и отдельного «активного» состояния не
                  // нужно.
                  onPressed: () {
                    Haptics.select();
                    setState(() => _draft = preset.toDouble());
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Translations.cancelOf(context)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _save,
                child: Text(Translations.saveOf(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
