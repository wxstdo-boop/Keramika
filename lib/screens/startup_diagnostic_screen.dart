import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';

/// Visible, non-silent fallback for a startup failure that is NOT a
/// JsonFileException (see `json_file.dart`).
///
/// Why this exists: the Android window background is near-black (`#17181C`).
/// Before this screen, any non-Json startup error did `rethrow` in `main()`,
/// the main Dart isolate died silently, and the user saw only that dark
/// window — a "black screen" with a live process. Routing EVERY startup error
/// here means the failure is never silent: it shows the raw error + stack and
/// offers Retry, Copy, and Save-to-file.
class StartupDiagnosticApp extends StatefulWidget {
  const StartupDiagnosticApp({
    required this.locale,
    required this.error,
    required this.stack,
    required this.onRetry,
    super.key,
  });

  final Locale locale;
  final String error;
  final String stack;

  /// Re-runs the startup routine. Passing `_startApp` from `main.dart` means
  /// a Retry simply replaces this diagnostic root with a fresh attempt.
  final Future<void> Function() onRetry;

  @override
  State<StartupDiagnosticApp> createState() => _StartupDiagnosticAppState();
}

class _StartupDiagnosticAppState extends State<StartupDiagnosticApp> {
  bool _busy = false;
  String? _notice;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await widget.onRetry();
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = Translations.t(
          'startupDiagRetryFailed',
          context,
          'Restart did not succeed. The error below is unchanged.',
        );
        debugPrint('Diagnostic retry failed: $error\n$stackTrace');
      });
    }
  }

  Future<void> _copyReport() async {
    final report = 'Keramika startup diagnostic\n'
        'Error: ${widget.error}\n'
        'Stack:\n${widget.stack}';
    try {
      await Clipboard.setData(ClipboardData(text: report));
      if (mounted) {
        setState(() {
          _notice = Translations.t(
            'startupDiagCopied',
            context,
            'Copied to clipboard.',
          );
        });
      }
    } catch (_) {
      // Clipboard is optional; ignore.
    }
  }

  Future<void> _saveReport() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().toUtc().toIso8601String();
      final file = File(
        '${dir.path}/keramika_startup_error_$stamp.log',
      );
      final report = 'Keramika startup diagnostic\n'
          'Saved: $stamp\n'
          'Error: ${widget.error}\n'
          'Stack:\n${widget.stack}\n';
      await file.writeAsString(report, flush: true);
      if (!mounted) return;
      final prefix = Translations.t(
        'startupDiagSaved',
        context,
        'Log saved:',
      );
      setState(() => _notice = '$prefix ${file.path}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = Translations.t(
          'startupDiagSaveFailed',
          context,
          'Could not save the log to a file.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MaterialApp(
      title: 'Keramika diagnostic',
      debugShowCheckedModeBanner: false,
      locale: widget.locale,
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
        locale: widget.locale,
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bug_report_outlined,
                            size: 64,
                            color: colors.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            Translations.t(
                              'startupDiagTitle',
                              context,
                              'Keramika stopped safely',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            Translations.t(
                              'startupDiagBody',
                              context,
                              'Keramika could not finish starting and stopped '
                              'before it drew the first screen. Nothing was '
                              'changed on disk. You can retry, or copy/save '
                              'the details below to report the problem.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            Translations.t(
                              'startupDiagDetailsTitle',
                              context,
                              'Technical details',
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              'Error: ${widget.error}\n\n'
                                  'Stack:\n${widget.stack}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _copyReport,
                                icon: const Icon(Icons.copy_outlined),
                                label: Text(
                                  Translations.t(
                                    'startupDiagCopy',
                                    context,
                                    'Copy',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _saveReport,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(
                                  Translations.t(
                                    'startupDiagSave',
                                    context,
                                    'Save log',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _busy ? null : _retry,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _busy
                                  ? Translations.t(
                                      'startupDiagRetrying',
                                      context,
                                      'Retrying…',
                                    )
                                  : Translations.t(
                                      'startupDiagRetry',
                                      context,
                                      'Try again',
                                    ),
                            ),
                          ),
                          if (_notice != null) ...[
                            const SizedBox(height: 12),
                            Text(_notice!, textAlign: TextAlign.center),
                          ],
                          if (_busy && _notice == null) ...[
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
          },
        ),
      ),
    );
  }
}