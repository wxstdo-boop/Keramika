import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../services/json_file.dart';

class StartupRecoveryApp extends StatelessWidget {
  const StartupRecoveryApp({
    required this.locale,
    required this.diagnostic,
    super.key,
  });

  final Locale locale;
  final String? diagnostic;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keramika recovery',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ru'), Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
      home: LocaleProvider(
        locale: locale,
        child: _StartupRecoveryScreen(diagnostic: diagnostic),
      ),
    );
  }
}

class _StartupRecoveryScreen extends StatefulWidget {
  const _StartupRecoveryScreen({required this.diagnostic});

  final String? diagnostic;

  @override
  State<_StartupRecoveryScreen> createState() => _StartupRecoveryScreenState();
}

class _StartupRecoveryScreenState extends State<_StartupRecoveryScreen> {
  final _phraseController = TextEditingController();
  String? _envelope;
  String? _backupName;
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLocalEnvelope();
  }

  @override
  void dispose() {
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalEnvelope() async {
    try {
      final envelope = await JsonFile.exportRecoveryEnvelope();
      if (mounted && envelope != null) setState(() => _envelope = envelope);
    } catch (_) {
      // An exported backup remains available even if local files cannot be read.
    }
  }

  Future<void> _chooseBackup() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked?.path == null) return;
    try {
      final file = File(picked!.path!);
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('Backup is too large');
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['keramika_key_recovery'] is! String) {
        throw const FormatException('Recovery information is missing');
      }
      if (mounted) {
        setState(() {
          _envelope = decoded['keramika_key_recovery'] as String;
          _backupName = picked.name;
          _status = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = Translations.t(
            'recoveryBackupInvalid',
            context,
            'This backup does not contain valid recovery information. No data was changed.',
          ),
        );
      }
    }
  }

  Future<void> _restoreKey() async {
    final envelope = _envelope;
    if (envelope == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await JsonFile.restoreEncryptionKey(
        _phraseController.text,
        envelope: envelope,
      );
      if (mounted) {
        _phraseController.clear();
        setState(
          () => _status = Translations.t(
            'recoveryRestoreSuccess',
            context,
            'The encryption key was restored without replacing existing data. Close and reopen Keramika. If you recovered from a backup after reinstalling, import that same backup from Settings.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _phraseController.clear();
        setState(
          () => _status = Translations.t(
            'recoveryRestoreFailed',
            context,
            'Recovery failed. The key and encrypted files were not replaced. Check the phrase and backup, and keep the backup unchanged.',
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 64, color: colors.primary),
                  const SizedBox(height: 20),
                  Text(
                    Translations.t(
                      'startupRecoveryTitle',
                      context,
                      'Keramika stopped safely',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Translations.t(
                      'startupRecoveryBody',
                      context,
                      'Keramika could not safely open its encrypted data and stopped before creating a replacement key. Existing files were left unchanged.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Translations.t(
                      'startupRecoveryBackupAdvice',
                      context,
                      'Do not clear app storage or uninstall until you have verified a separate Keramika JSON backup. If key recovery fails, preserve that backup before reinstalling, then import it.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.diagnostic != null &&
                      widget.diagnostic!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ExpansionTile(
                      title: Text(
                        Translations.t(
                          'startupRecoveryDetails',
                          context,
                          'Technical details',
                        ),
                      ),
                      children: [
                        SelectableText(
                          widget.diagnostic!,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    Translations.t(
                      'recoveryRestoreTitle',
                      context,
                      'Restore with a recovery phrase',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Translations.t(
                      'recoveryRestoreInstructions',
                      context,
                      'Choose the Keramika backup that contains your recovery information, then enter its 24-word phrase. The phrase is only used on this device and is not saved.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _chooseBackup,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(
                      _backupName ??
                          Translations.t(
                            'recoveryChooseBackup',
                            context,
                            'Choose recovery backup',
                          ),
                    ),
                  ),
                  TextField(
                    controller: _phraseController,
                    minLines: 3,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: Translations.t(
                        'recoveryPhraseInput',
                        context,
                        'Recovery phrase',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy || _envelope == null ? null : _restoreKey,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(
                      Translations.t(
                        'recoveryRestoreButton',
                        context,
                        'Restore encryption key',
                      ),
                    ),
                  ),
                  if (_envelope != null && _backupName == null)
                    Text(
                      Translations.t(
                        'recoveryLocalEnvelope',
                        context,
                        'Recovery information found on this device.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(_status!, textAlign: TextAlign.center),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
