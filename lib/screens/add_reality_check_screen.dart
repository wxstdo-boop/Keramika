import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/reality_check.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/icon_map.dart';
import '../widgets/icon_picker_sheet.dart';
import '../widgets/smooth_keyboard_body.dart';

class AddRealityCheckScreen extends StatefulWidget {
  final RealityCheck? existing;
  const AddRealityCheckScreen({super.key, this.existing});

  @override
  State<AddRealityCheckScreen> createState() => _AddRealityCheckScreenState();
}

class _AddRealityCheckScreenState extends State<AddRealityCheckScreen> {
  late TextEditingController _questionCtrl;
  late int _iconCodePoint;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _questionCtrl = TextEditingController(text: widget.existing!.question);
      _iconCodePoint = widget.existing!.iconCodePoint;
      _editing = true;
    } else {
      _questionCtrl = TextEditingController();
      // По умолчанию — «голова с шестерёнкой» (psychology_outlined),
      // как просил пользователь.
      _iconCodePoint = 0xf2d2;
    }
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  void _pickIcon() async {
    final result = await IconPickerSheet.show(context, _iconCodePoint);
    if (result != null) setState(() => _iconCodePoint = result);
  }

  void _save() {
    final question = _questionCtrl.text.trim();
    if (question.isEmpty) return;
    final check = RealityCheck(
      id: widget.existing?.id ?? const Uuid().v4(),
      question: question,
      totalChecks: widget.existing?.totalChecks ?? 0,
      lastCheckedAt: widget.existing?.lastCheckedAt,
      iconCodePoint: _iconCodePoint,
      createdAt: widget.existing?.createdAt,
    );
    Navigator.of(context).pop(check);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? Translations.t('editRc', context)
              : Translations.t('newRc', context),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(Translations.saveOf(context)),
          ),
        ],
      ),
      resizeToAvoidBottomInset: false,
      body: SmoothKeyboardBody(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickIcon,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      iconDataForCodePoint(_iconCodePoint),
                      key: ValueKey(_iconCodePoint),
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: _pickIcon,
                icon: const Icon(Icons.touch_app, size: 16),
                label: Text(Translations.t('changeIcon', context)),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: TextField(
                  magnifierConfiguration: TextMagnifierConfiguration.disabled,
                  controller: _questionCtrl,
                  contextMenuBuilder: minimalContextMenuBuilder,
                  maxLength: 200,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: Translations.t('rcQuestion', context),
                    prefixIcon: const Icon(Icons.help_outline),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
