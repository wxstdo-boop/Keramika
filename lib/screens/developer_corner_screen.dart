import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

class DeveloperModePasswordDialog extends StatefulWidget {
  final String title;
  final String prompt;
  final String invalidCode;
  final String cancelLabel;
  final String unlockLabel;
  final VoidCallback onCancel;
  final Future<void> Function() onUnlock;

  const DeveloperModePasswordDialog({
    super.key,
    required this.title,
    required this.prompt,
    required this.invalidCode,
    required this.cancelLabel,
    required this.unlockLabel,
    required this.onCancel,
    required this.onUnlock,
  });

  @override
  State<DeveloperModePasswordDialog> createState() =>
      _DeveloperModePasswordDialogState();
}

class _DeveloperModePasswordDialogState
    extends State<DeveloperModePasswordDialog>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final _visibilityAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  bool _obscured = true;
  bool _invalid = false;
  bool _busy = false;
  bool _transitioning = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    _visibilityAnimation.dispose();
    super.dispose();
  }

  Future<void> _toggleVisibility() async {
    if (_transitioning || _busy) return;
    setState(() => _transitioning = true);
    await _visibilityAnimation.forward();
    if (!mounted) return;
    setState(() => _obscured = !_obscured);
    await _visibilityAnimation.reverse();
    if (mounted) setState(() => _transitioning = false);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_controller.text != '7720') {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _busy = true;
      _invalid = false;
    });
    await widget.onUnlock();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = colors.primary;
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(accent, Colors.white, 0.62)!,
                  accent.withValues(alpha: 0.5),
                  Color.lerp(accent, Colors.black, 0.14)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.24),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            padding: const EdgeInsets.all(1.2),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(29),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(29),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: accent.withValues(
                              alpha: _focused ? 0.85 : 0.32,
                            ),
                            width: _focused ? 1.8 : 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: _focused ? 0.26 : 0.12,
                              ),
                              blurRadius: _focused ? 22 : 12,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 30,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.prompt,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(19),
                          boxShadow: [
                            BoxShadow(
                              color: (_invalid ? colors.error : accent)
                                  .withValues(alpha: _focused ? 0.16 : 0.06),
                              blurRadius: _focused ? 18 : 8,
                            ),
                          ],
                        ),
                        child: AnimatedBuilder(
                          animation: _visibilityAnimation,
                          builder: (context, child) => TextField(
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color:
                                  (theme.textTheme.bodyLarge?.color ??
                                          colors.onSurface)
                                      .withValues(
                                        alpha: 1 - _visibilityAnimation.value,
                                      ),
                            ),
                            cursorColor: accent,
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            obscureText: _obscured,
                            maxLength: 4,
                            enableSuggestions: false,
                            autocorrect: false,
                            cursorOpacityAnimates: true,
                            magnifierConfiguration:
                                TextMagnifierConfiguration.disabled,
                            contextMenuBuilder: minimalContextMenuBuilder,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            buildCounter: smoothCharCounterBuilder,
                            onChanged: (_) {
                              if (_invalid) setState(() => _invalid = false);
                            },
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: '••••',
                              prefixIcon: Icon(
                                Icons.pin_outlined,
                                color: colors.onSurfaceVariant,
                              ),
                              suffixIcon: IconButton(
                                onPressed: _toggleVisibility,
                                icon: AnimatedBuilder(
                                  animation: _visibilityAnimation,
                                  builder: (context, child) => Transform.scale(
                                    scale:
                                        1 -
                                        0.1 *
                                            math.sin(
                                              math.pi *
                                                  _visibilityAnimation.value,
                                            ),
                                    child: child,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: animation,
                                            child: RotationTransition(
                                              turns: Tween<double>(
                                                begin: -0.08,
                                                end: 0,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          ),
                                        ),
                                    child: Icon(
                                      _obscured
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      key: ValueKey(_obscured),
                                    ),
                                  ),
                                ),
                              ),
                              filled: true,
                              fillColor: colors.surfaceContainerHighest
                                  .withValues(alpha: 0.46),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 17,
                                horizontal: 18,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(19),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(19),
                                borderSide: BorderSide(
                                  color: colors.outlineVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(19),
                                borderSide: BorderSide(
                                  color: _invalid ? colors.error : accent,
                                  width: 1.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 26,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ExcludeSemantics(
                            excluding: !_invalid,
                            child: AnimatedOpacity(
                              opacity: _invalid ? 1 : 0,
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeInOut,
                              child: Text(
                                widget.invalidCode,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.error,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _busy ? null : widget.onCancel,
                              child: Text(widget.cancelLabel),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _submit,
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.lock_open_rounded,
                                      size: 18,
                                    ),
                              label: Text(widget.unlockLabel),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
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
      ),
    );
  }
}

class DeveloperCornerScreen extends StatefulWidget {
  final String title;
  final String controlsLabel;
  final String subtitle;
  final String disableLabel;
  final Future<void> Function() onDisable;
  final String developerPrompt;
  final Future<void> Function(String value) onSaveDeveloperPrompt;
  final List<Widget> children;
  final Color accent;

  const DeveloperCornerScreen({
    super.key,
    required this.title,
    required this.controlsLabel,
    required this.subtitle,
    required this.disableLabel,
    required this.onDisable,
    required this.developerPrompt,
    required this.onSaveDeveloperPrompt,
    required this.children,
    required this.accent,
  });

  @override
  State<DeveloperCornerScreen> createState() => _DeveloperCornerScreenState();
}

class _DeveloperCornerScreenState extends State<DeveloperCornerScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonTooltip(),
        title: Text(widget.title),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: widget.onDisable,
            tooltip: widget.disableLabel,
            icon: Icon(Icons.lock_outline_rounded, color: colors.error),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.accent.withValues(alpha: 0.19),
                          colors.surfaceContainerLow,
                          colors.surfaceContainerHigh,
                        ],
                      ),
                      border: Border.all(
                        color: widget.accent.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.accent.withValues(alpha: 0.16),
                            border: Border.all(
                              color: widget.accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(
                            Icons.developer_mode_rounded,
                            color: widget.accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                widget.subtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 18, color: widget.accent),
                      const SizedBox(width: 9),
                      Text(
                        widget.controlsLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: widget.accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DeveloperPromptEditor(
                    initialValue: widget.developerPrompt,
                    accent: widget.accent,
                    onSave: widget.onSaveDeveloperPrompt,
                  ),
                  const SizedBox(height: 22),
                  for (var i = 0; i < widget.children.length; i++) ...[
                    StaggerIn(
                      index: i,
                      step: const Duration(milliseconds: 95),
                      duration: const Duration(milliseconds: 440),
                      child: widget.children[i],
                    ),
                    if (i < widget.children.length - 1)
                      Divider(
                        height: 1,
                        indent: 52,
                        color: colors.outlineVariant.withValues(alpha: 0.48),
                      ),
                  ],
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: widget.onDisable,
                      icon: const Icon(Icons.lock_outline_rounded, size: 18),
                      label: Text(widget.disableLabel),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DeveloperPromptEditor extends StatefulWidget {
  final String initialValue;
  final Color accent;
  final Future<void> Function(String value) onSave;

  const DeveloperPromptEditor({
    super.key,
    required this.initialValue,
    required this.accent,
    required this.onSave,
  });

  @override
  State<DeveloperPromptEditor> createState() => _DeveloperPromptEditorState();
}

class _DeveloperPromptEditorState extends State<DeveloperPromptEditor> {
  static const _maxLength = 10000;
  static const _saveDelay = Duration(milliseconds: 700);

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  Timer? _saveTimer;
  late String _draft = widget.initialValue;
  late String _savedValue = widget.initialValue;
  bool _saving = false;
  bool _saveQueued = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_draft != _savedValue) unawaited(_save());
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _draft = value;
    setState(() => _saveFailed = false);
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () => unawaited(_save()));
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final value = _draft;
    if (value == _savedValue) return;
    if (_saving) {
      _saveQueued = true;
      return;
    }

    _saving = true;
    _saveQueued = false;
    if (mounted) setState(() => _saveFailed = false);
    var succeeded = false;
    try {
      await widget.onSave(value);
      _savedValue = value;
      succeeded = true;
    } catch (_) {
      if (mounted) setState(() => _saveFailed = true);
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }

    final changedWhileSaving = _saveQueued || _draft != _savedValue;
    _saveQueued = false;
    if (succeeded && changedWhileSaving) await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = widget.accent;
    final isDirty = _draft != _savedValue;
    final status = _saving
        ? Translations.t('devPromptSaving', context)
        : _saveFailed
        ? Translations.t('devPromptSaveError', context)
        : isDirty
        ? Translations.t('devPromptUnsaved', context)
        : Translations.t('devPromptSaved', context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.2),
            colors.surfaceContainerLow,
            colors.surfaceContainerHigh,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.36), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: accent, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Translations.t('devPromptTitle', context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Translations.t('devPromptDescription', context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            minLines: 6,
            maxLines: 12,
            maxLength: _maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) => null,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            contextMenuBuilder: minimalContextMenuBuilder,
            decoration: InputDecoration(
              hintText: Translations.t('devPromptHint', context),
              alignLabelWithHint: true,
              filled: true,
              fillColor: colors.surface.withValues(alpha: 0.76),
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(19),
                borderSide: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(19),
                borderSide: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(19),
                borderSide: BorderSide(color: accent, width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              status,
              key: ValueKey(status),
              style: theme.textTheme.labelSmall?.copyWith(
                color: _saveFailed ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: isDirty && !_saving ? () => unawaited(_save()) : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(Translations.t('devPromptSave', context)),
              style: FilledButton.styleFrom(
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
