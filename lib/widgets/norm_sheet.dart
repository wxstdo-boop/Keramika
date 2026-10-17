import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/nutrition_service.dart';
import 'press_scale.dart';
import 'rolling_counter.dart';

/// Лист настройки личной суточной нормы калорий.
///
/// Открывается тапом по кольцу прогресса. Возвращает [Navigator.pop] с
/// сохранённым числом либо null, если пользователь отменил, — сам экран и
/// показывает ответный снекбар, чтобы лист не знал про чужие уведомления.
///
/// Число докручивается барабаном за ползунком: шаг деления 50 ккал, и без
/// промежуточной анимации цифры «перескакивали» через полсотни значений за
/// кадр. Шаг ±50 дублирует ползунок кнопками — попасть в круглое значение
/// пальцем на 190 делениях неудобно.
class NormSheet extends StatefulWidget {
  const NormSheet({super.key, required this.service});

  final NutritionService service;

  @override
  State<NormSheet> createState() => _NormSheetState();
}

class _NormSheetState extends State<NormSheet> {
  late double _draft = widget.service.norm.toDouble();

  static const List<int> _presets = [1500, 2000, 2500, 3000];

  /// Шаг ползунка и кнопок: одно деление = 50 ккал.
  static const int _step = 50;

  int get _rounded => _draft.round().clamp(kMinCalorieNorm, kMaxCalorieNorm);

  void _set(double value) {
    final next = value.clamp(
      kMinCalorieNorm.toDouble(),
      kMaxCalorieNorm.toDouble(),
    );
    if (next == _draft) return;
    setState(() => _draft = next);
  }

  void _stepBy(int delta) => _set((_draft + delta).roundToDouble());

  void _save() {
    Haptics.medium();
    final v = _rounded;
    widget.service.setNorm(v);
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final kcal = Translations.t('kcalShort', context, 'ккал');
    final number = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: cs.primary,
      height: 1,
      letterSpacing: -0.5,
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_fire_department_rounded,
                  size: 22,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Translations.t('calorieNorm', context, 'Суточная норма'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$kMinCalorieNorm – $kMaxCalorieNorm $kcal',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _StepButton(
                      icon: Icons.remove_rounded,
                      tooltip: '−$_step',
                      onStep: () => _stepBy(-_step),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          TweenAnimationBuilder<double>(
                            // `end` меняется вместе с ползунком: барабан
                            // докручивается до нового значения, а не
                            // переставляет цифры одним кадром. 340 мс вместо
                            // 190: на быстрой прокрутке ползунка барабан
                            // успевал «перещёлкнуть» полсотни значений —
                            // теперь цифры именно перетекают.
                            tween: Tween<double>(begin: _draft, end: _draft),
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            builder: (context, shown, _) => RollingCounter(
                              value: shown,
                              style: number,
                              // Ширина зафиксирована под пять разрядов:
                              // иначе при переходе «999 → 1000» центрированное
                              // число съезжало в сторону.
                              sample: '99999',
                              alignment: Alignment.center,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            kcal,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StepButton(
                      icon: Icons.add_rounded,
                      tooltip: '+$_step',
                      onStep: () => _stepBy(_step),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: cs.primary,
                    inactiveTrackColor: cs.surfaceContainerHighest,
                    thumbColor: cs.primary,
                    overlayColor: cs.primary.withValues(alpha: 0.10),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                      elevation: 0,
                      pressedElevation: 0,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 18,
                    ),
                    trackShape: const RoundedRectSliderTrackShape(),
                    showValueIndicator: ShowValueIndicator.never,
                  ),
                  child: Slider(
                    value: _draft,
                    min: kMinCalorieNorm.toDouble(),
                    max: kMaxCalorieNorm.toDouble(),
                    divisions: (kMaxCalorieNorm - kMinCalorieNorm) ~/ _step,
                    label: '$_rounded',
                    semanticFormatterCallback: (v) => '${v.round()} $kcal',
                    onChanged: _set,
                    onChangeEnd: (_) => Haptics.select(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Text(
                        '$kMinCalorieNorm',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$kMaxCalorieNorm',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                _PresetChip(
                  value: preset,
                  selected: _rounded == preset,
                  onTap: () {
                    Haptics.select();
                    _set(preset.toDouble());
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
              PressScale(
                pressedScale: 0.965,
                duration: const Duration(milliseconds: 300),
                releaseDuration: const Duration(milliseconds: 380),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: Text(Translations.saveOf(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Кнопка «±50» с удержанием: первый шаг сразу, затем учащающийся ряд.
/// Хаптик звучит только на первом шаге — иначе удержание превращается в
/// непрерывную вибрацию.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onStep,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _begin() {
    Haptics.select();
    widget.onStep();
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 400), () {
      _hold = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => widget.onStep(),
      );
    });
  }

  void _end() {
    _hold?.cancel();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Listener(
      onPointerDown: (_) => _begin(),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: PressScale(
        pressedScale: 0.92,
        duration: const Duration(milliseconds: 240),
        releaseDuration: const Duration(milliseconds: 320),
        // Без Tooltip: он показывает подсказку по долгому нажатию, а долгое
        // нажатие здесь — это автоповтор шага.
        child: Semantics(
          button: true,
          label: widget.tooltip,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.30)),
            ),
            child: Icon(widget.icon, size: 22, color: cs.primary),
          ),
        ),
      ),
    );
  }
}

/// Чип-пресет. Выбранное состояние — акцентная заливка и жирная цифра:
/// раньше пресеты никак не показывали, что норма уже равна им.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$value',
      child: PressScale(
        pressedScale: 0.95,
        duration: const Duration(milliseconds: 260),
        releaseDuration: const Duration(milliseconds: 340),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            // Заливка и обводка перетекают вместе с нажатием, а не раньше
            // него: 320 мс и симметричная кривая — выбор пресета больше не
            // «вспыхивает» одним кадром.
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.14)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? cs.primary.withValues(alpha: 0.55)
                    : cs.outline.withValues(alpha: 0.28),
              ),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: Text('$value', maxLines: 1),
            ),
          ),
        ),
      ),
    );
  }
}
