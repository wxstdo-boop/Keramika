import 'package:flutter/material.dart';

class GlobalKeyboardManager {
  static OverlayEntry? _keyboardEntry;

  static void show(
    BuildContext context,
    TextEditingController controller,
    VoidCallback onBackspace,
    Function(String) onChar,
  ) {
    if (_keyboardEntry != null) return;

    _keyboardEntry = OverlayEntry(
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          child: MaterialYouKeyboard(
            controller: controller,
            onBackspace: onBackspace,
            onChar: onChar,
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_keyboardEntry!);
  }

  static void hide() {
    _keyboardEntry?.remove();
    _keyboardEntry = null;
  }
}

class MaterialYouKeyboard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onBackspace;
  final Function(String) onChar;

  const MaterialYouKeyboard({
    super.key,
    required this.controller,
    required this.onBackspace,
    required this.onChar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']),
          const SizedBox(height: 8),
          _row(context, ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p']),
          const SizedBox(height: 8),
          _row(context, ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l']),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _key(context, 'z', flex: 1)),
              Expanded(child: _key(context, 'x', flex: 1)),
              Expanded(child: _key(context, 'c', flex: 1)),
              Expanded(child: _key(context, 'v', flex: 1)),
              Expanded(child: _key(context, 'b', flex: 1)),
              Expanded(child: _key(context, 'n', flex: 1)),
              Expanded(child: _key(context, 'm', flex: 1)),
              Expanded(
                child: IconButton(
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: onBackspace,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, List<String> chars) {
    return Row(
      children: chars.map((c) => Expanded(child: _key(context, c))).toList(),
    );
  }

  Widget _key(BuildContext context, String char, {int flex = 1}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChar(char),
          child: Container(
            height: 45,
            alignment: Alignment.center,
            child: Text(
              char,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
