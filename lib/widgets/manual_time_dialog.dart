import 'package:flutter/material.dart';
import '../services/haptics.dart';
import '../l10n/translations.dart';
import 'rolling_number.dart';

/// Открывает плавный диалог выбора времени (ЧЧ:ММ) — полностью БЕЗ
/// клавиатуры.
///
/// Значение меняется только стрелочками: тап — один шаг, зажатие —
/// плавная быстрая «прокрутка» цифр (ролик-анимация). Никаких TextField —
/// ни лупы, ни системного выделения, ни всплывающей клавиатуры.
Future<TimeOfDay?> showManualTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => _ManualTimeDialog(initial: initial),
  );
}

class _ManualTimeDialog extends StatefulWidget {
  final TimeOfDay initial;
  const _ManualTimeDialog({required this.initial});

  @override
  State<_ManualTimeDialog> createState() => _ManualTimeDialogState();
}

class _ManualTimeDialogState extends State<_ManualTimeDialog> {
  late int _hour;
  late int _minute;
  // Направление последнего изменения — ролик крутится «в ту сторону».
  int _hourDelta = 1;
  int _minuteDelta = 1;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  void _step(bool isHour, int delta) {
    setState(() {
      if (isHour) {
        _hour = (_hour + delta + 24) % 24;
        _hourDelta = delta;
      } else {
        _minute = (_minute + delta + 60) % 60;
        _minuteDelta = delta;
      }
    });
  }

  void _submit() {
    Haptics.medium();
    Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
  }

  Widget _buildColumn(ThemeData theme, bool isHour) {
    final value = isHour ? _hour : _minute;
    final delta = isHour ? _hourDelta : _minuteDelta;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoldStepper(
          icon: Icons.keyboard_arrow_up,
          onStep: () => _step(isHour, 1),
        ),
        const SizedBox(height: 2),
        RollingNumber(
          value: _two(value),
          delta: delta,
          width: 84,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          style:
              theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ) ??
              const TextStyle(fontSize: 44, fontWeight: FontWeight.w700),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        const SizedBox(height: 2),
        HoldStepper(
          icon: Icons.keyboard_arrow_down,
          onStep: () => _step(isHour, -1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('⏰', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Время',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildColumn(theme, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ':',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                _buildColumn(theme, false),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(Translations.cancelOf(context)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submit,
                  child: Text(Translations.okOf(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
