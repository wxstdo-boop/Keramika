import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../services/forge_agent.dart';
import '../services/forge_service.dart';
import '../services/haptics.dart';
import '../services/settings_service.dart';
import '../utils/context_menu.dart';
import '../utils/snackbar.dart';
import '../widgets/canary_icon.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../widgets/stagger_in.dart';
import 'developer_corner_screen.dart';

/// «Кузница» — мастерская внутри уголка разработчика: вставляешь токен
/// GitHub, описываешь задачу словами, и ИИ-агент сам правит код в отдельной
/// ветке и открывает pull request.
///
/// Прямая запись в основную ветку здесь сознательно не делается: с телефона
/// невозможно просмотреть diff, а сломанный `main` останавливает и автосборку
/// релиза. Ветка + PR оставляют решение за человеком.
class ForgeScreen extends StatefulWidget {
  const ForgeScreen({
    super.key,
    required this.owner,
    required this.repo,
    this.service,
  });

  final String owner;
  final String repo;

  /// Подменяемый сервис: в бою создаётся свой с токеном в Keystore,
  /// в тестах подставляется с хранилищем в памяти.
  final ForgeService? service;

  @override
  State<ForgeScreen> createState() => _ForgeScreenState();
}

class _ForgeScreenState extends State<ForgeScreen> {
  late final ForgeService _service = widget.service ?? ForgeService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _taskController = TextEditingController();

  bool _loadingToken = true;
  bool _checking = false;
  bool _running = false;
  String? _login;
  String? _tokenError;
  String _baseBranch = 'main';

  final List<ForgeStep> _log = <ForgeStep>[];
  ForgeRunResult? _result;
  String? _runError;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreToken());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  /// Токен поднимаем из защищённого хранилища при входе в экран — раньше
  /// введённое значение терялось между открытиями.
  Future<void> _restoreToken() async {
    final saved = await _service.loadToken();
    if (!mounted) return;
    setState(() {
      _loadingToken = false;
      if (saved != null) {
        _tokenController.text = saved;
      }
    });
    if (saved != null) unawaited(_checkToken(silent: true));
  }

  Future<void> _checkToken({bool silent = false}) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _tokenError = Translations.t('forgeTokenEmpty', context);
        _login = null;
      });
      return;
    }
    setState(() {
      _checking = true;
      _tokenError = null;
    });
    try {
      await _service.saveToken(token);
      final login = await _service.verifyToken(token);
      final canPush = await _service.canPush(
        widget.owner,
        widget.repo,
        token: token,
      );
      final branch = await _service.defaultBranch(
        widget.owner,
        widget.repo,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _login = login;
        _baseBranch = branch;
        _checking = false;
        // Токен без права записи проходит проверку входа, но агент не
        // сможет ни создать ветку, ни открыть PR — говорим об этом сразу,
        // а не после пяти минут работы модели.
        _tokenError = canPush
            ? null
            : Translations.t('forgeTokenReadOnly', context);
      });
      if (!silent && mounted) {
        showBeautifulSnackBar(
          context,
          message: canPush
              ? '${Translations.t('forgeTokenOk', context)}: $login'
              : Translations.t('forgeTokenReadOnly', context),
          icon: canPush
              ? Icons.verified_rounded
              : Icons.warning_amber_rounded,
          iconColor: canPush ? null : Colors.orange,
        );
      }
    } on ForgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _login = null;
        _tokenError = e.isAuth
            ? Translations.t('forgeTokenInvalid', context)
            : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _tokenError = e.toString();
      });
    }
  }

  Future<void> _forgetToken() async {
    await _service.clearToken();
    if (!mounted) return;
    setState(() {
      _tokenController.clear();
      _login = null;
      _tokenError = null;
    });
    showBeautifulSnackBar(
      context,
      message: Translations.t('forgeTokenForgotten', context),
      icon: Icons.delete_outline_rounded,
    );
  }

  Future<void> _run() async {
    final task = _taskController.text.trim();
    if (task.isEmpty) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('forgeTaskEmpty', context),
        icon: Icons.edit_note_rounded,
        iconColor: Colors.orange,
      );
      return;
    }
    if (_tokenController.text.trim().isEmpty) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('forgeTokenEmpty', context),
        icon: Icons.key_off_rounded,
        iconColor: Colors.orange,
      );
      return;
    }
    // Локаль и ключ ИИ читаем до первого ожидания: после него `context`
    // может быть уже недействителен (экран закрыли во время запроса).
    final languageCode = LocaleProvider.of(context).languageCode;
    final needAiKeyMessage = Translations.t('forgeNeedAiKey', context);
    final apiKey = (await SettingsService.loadAiKey()).trim();
    if (!mounted) return;
    if (apiKey.isEmpty) {
      showBeautifulSnackBar(
        context,
        message: needAiKeyMessage,
        icon: Icons.key_off_rounded,
        iconColor: Colors.orange,
      );
      return;
    }

    setState(() {
      _running = true;
      _runError = null;
      _result = null;
      _log.clear();
    });
    try {
      final agent = ForgeAgent(
        service: _service,
        chat: OpenAiForgeChat(apiKey: apiKey),
        owner: widget.owner,
        repo: widget.repo,
      );
      final result = await agent.run(
        task: task,
        baseBranch: _baseBranch,
        languageCode: languageCode,
        onStep: (step) {
          if (!mounted) return;
          setState(() => _log.add(step));
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = result;
      });
      Haptics.heavy();
    } on ForgeException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _runError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _runError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonTooltip(),
        title: Text(Translations.t('forgeTitle', context, 'Кузница')),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _hero(theme, accent),
                    const SizedBox(height: 22),
                    _sectionLabel(
                      theme,
                      accent,
                      Icons.key_rounded,
                      Translations.t('forgeTokenSection', context),
                    ),
                    const SizedBox(height: 8),
                    _tokenCard(theme, cs, accent),
                    const SizedBox(height: 22),
                    _sectionLabel(
                      theme,
                      accent,
                      Icons.auto_fix_high_rounded,
                      Translations.t('forgeTaskSection', context),
                    ),
                    const SizedBox(height: 8),
                    _taskCard(theme, cs, accent),
                    if (_log.isNotEmpty || _running) ...[
                      const SizedBox(height: 22),
                      _sectionLabel(
                        theme,
                        accent,
                        Icons.terminal_rounded,
                        Translations.t('forgeLogSection', context),
                      ),
                      const SizedBox(height: 8),
                      _logCard(theme, cs),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: 18),
                      _resultCard(theme, cs),
                    ],
                    if (_runError != null) ...[
                      const SizedBox(height: 18),
                      _errorCard(theme, cs),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(ThemeData theme, Color accent) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: devCardDecoration(theme, accent),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: const Center(child: CanaryIcon(size: 36)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.t('forgeTitle', context, 'Кузница'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  Translations.t('forgeSubtitle', context),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(
    ThemeData theme,
    Color accent,
    IconData icon,
    String label,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 9),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _tokenCard(ThemeData theme, ColorScheme cs, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: devCardDecoration(theme, accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            Translations.t('forgeTokenHint', context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          // Токен показываем точками и БЕЗ «глазка»: раскрывать секрет на
          // экране незачем, а подтверждение всё равно приходит логином ниже.
          // Оформление — как у остальных полей приложения (плотное, радиус
          // 14, минимальное меню, без лупы).
          TextField(
            controller: _tokenController,
            obscureText: true,
            obscuringCharacter: '•',
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            cursorOpacityAnimates: true,
            magnifierConfiguration: TextMagnifierConfiguration.disabled,
            contextMenuBuilder: minimalContextMenuBuilder,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'ghp_… / github_pat_…',
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  child: FilledButton.icon(
                    onPressed: _checking || _loadingToken
                        ? null
                        : () => _checkToken(),
                    icon: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(
                      Translations.t('forgeTokenCheck', context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Зажатие «тонет» неспешно и поднимается ещё медленнее —
              // как у кнопки сохранения в уголке: резкий щелчок значка
              // читался как отсутствие отдачи.
              PressScale(
                pressedScale: 0.94,
                duration: const Duration(milliseconds: 460),
                releaseDuration: const Duration(milliseconds: 720),
                child: IconButton(
                  tooltip: Translations.t('forgeTokenForget', context),
                  onPressed: _loadingToken
                      ? null
                      : () {
                          Haptics.light();
                          unawaited(_forgetToken());
                        },
                  icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                ),
              ),
            ],
          ),
          if (_tokenError != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tokenError!,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ),
              ],
            ),
          ] else if (_login != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${Translations.t('forgeTokenOk', context)}: $_login · '
                    '${widget.owner}/${widget.repo} ($_baseBranch)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskCard(ThemeData theme, ColorScheme cs, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: devCardDecoration(theme, accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Поле — в том же обёрточном стиле, что и остальные поля ввода
          // приложения: SmoothTyping плавно проявляет буквы, курсор
          // анимированный, лупа и лишнее меню отключены.
          SmoothTyping(
            controller: _taskController,
            builder: (typingStyle) => TextField(
              controller: _taskController,
              style: typingStyle,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              enabled: !_running,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              cursorOpacityAnimates: true,
              magnifierConfiguration: TextMagnifierConfiguration.disabled,
              contextMenuBuilder: minimalContextMenuBuilder,
              buildCounter: smoothCharCounterBuilder,
              decoration: InputDecoration(
                hintText: Translations.t('forgeTaskHint', context),
                alignLabelWithHint: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.65),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: accent, width: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          PressScale(
            child: FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.hardware_rounded, size: 18),
              label: Text(
                _running
                    ? Translations.t('forgeWorking', context)
                    : Translations.t('forgeRun', context),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Translations.t('forgeSafetyNote', context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logCard(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _log.length; i++)
            StaggerIn(
              index: i,
              step: const Duration(milliseconds: 45),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _log[i].ok
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 15,
                      color: _log[i].ok ? cs.primary : cs.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_log[i].tool}: ${_log[i].detail}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_running)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    Translations.t('forgeThinking', context),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultCard(ThemeData theme, ColorScheme cs) {
    final result = _result!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.merge_type_rounded,
                size: 18,
                color: Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Translations.t('forgeDone', context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.summary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            '${Translations.t('forgeBranch', context)}: ${result.branch} · '
            '${result.filesChanged} '
            '${Translations.t('forgeFiles', context)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (result.pullRequestUrl != null) ...[
            const SizedBox(height: 10),
            SelectableText(
              result.pullRequestUrl!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _runError!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
