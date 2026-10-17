import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/json_file.dart';

class DeveloperCornerScreen extends StatefulWidget {
  const DeveloperCornerScreen({super.key});

  @override
  State<DeveloperCornerScreen> createState() => _DeveloperCornerScreenState();
}

class _DeveloperCornerScreenState extends State<DeveloperCornerScreen> {
  final _confirmationController = TextEditingController();
  final _testController = TextEditingController();
  String? _phrase;
  bool _hasEnvelope = false;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refreshEnvelopeState();
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    _testController.dispose();
    super.dispose();
  }

  Future<void> _refreshEnvelopeState() async {
    final present = await JsonFile.hasRecoveryEnvelope();
    if (mounted) setState(() => _hasEnvelope = present);
  }

  String _t(String key, String fallback) =>
      Translations.t(key, context, fallback);

  Future<void> _beginPhraseSetup() async {
    if (_hasEnvelope) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('recoveryReplaceTitle', 'Replace recovery phrase?')),
          content: Text(
            _t(
              'recoveryReplaceBody',
              'The previous phrase will stop working. Continue only if you can safely save and confirm the new phrase.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('cancel', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('continue', 'Continue')),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    setState(() {
      _phrase = JsonFile.generateRecoveryPhrase();
      _confirmationController.clear();
      _status = null;
    });
  }

  Future<void> _confirmPhrase() async {
    final phrase = _phrase;
    if (phrase == null) return;
    if (_normalize(_confirmationController.text) != _normalize(phrase)) {
      setState(
        () => _status = _t(
          'recoveryPhraseMismatch',
          'The confirmation does not match. Nothing was saved.',
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await JsonFile.createRecoveryEnvelope(phrase);
      if (!mounted) return;
      setState(() {
        _hasEnvelope = true;
        _phrase = null;
        _confirmationController.clear();
        _status = _t(
          'recoveryPhraseSaved',
          'Recovery protection is set. Test it below and keep your phrase offline.',
        );
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = _t(
            'recoverySetupFailed',
            'Could not save recovery protection. Existing data was not changed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  Future<void> _testPhrase() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final valid = await JsonFile.testRecoveryPhrase(_testController.text);
      if (mounted) {
        setState(
          () => _status = valid
              ? _t(
                  'recoveryTestPassed',
                  'Recovery phrase verified against this encrypted data. No data or key was changed.',
                )
              : _t(
                  'recoveryTestFailed',
                  'Phrase verification failed. Nothing was changed.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = _t(
            'recoveryTestFailed',
            'Phrase verification failed. Nothing was changed.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_t('developerCorner', 'Developer corner'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.key_rounded, size: 52, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              _t('recoveryPhraseTitle', 'Encryption recovery phrase'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                'recoveryPhraseWarning',
                'This 24-word phrase can unlock your encrypted data. Keep it private and offline. Keramika never stores the phrase or the unwrapped key in a backup. If you lose the phrase, it cannot be recreated.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy || _phrase != null ? null : _beginPhraseSetup,
              icon: const Icon(Icons.add_moderator_outlined),
              label: Text(
                _hasEnvelope
                    ? _t('recoveryReplaceButton', 'Create a new phrase')
                    : _t('recoveryCreateButton', 'Create recovery phrase'),
              ),
            ),
            if (_phrase case final phrase?) ...[
              const SizedBox(height: 20),
              SelectableText(
                phrase,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  height: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _t(
                  'recoveryConfirmInstructions',
                  'Write the phrase down in order and enter all 24 words to confirm. This screen will not show it again after confirmation.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmationController,
                minLines: 3,
                maxLines: 5,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _t('recoveryConfirmLabel', 'Confirm all words'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _confirmPhrase,
                child: Text(_t('recoveryConfirmButton', 'Confirm and protect')),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              _t('recoveryTestTitle', 'Test recovery'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _t(
                'recoveryTestInstructions',
                'Enter the saved phrase to test that it unlocks the current key. This is a non-destructive test; actual recovery is available on the startup recovery screen.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _testController,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _t('recoveryPhraseInput', 'Recovery phrase'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy || !_hasEnvelope ? null : _testPhrase,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(_t('recoveryTestButton', 'Test phrase')),
            ),
            if (_status != null) ...[
              const SizedBox(height: 16),
              Text(_status!, textAlign: TextAlign.center),
            ],
            if (_busy) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
