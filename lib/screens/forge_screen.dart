import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/locale_provider.dart';
import '../l10n/translations.dart';
import '../services/forge_agent.dart';
import '../services/forge_chat_store.dart';
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
    this.chatFactory,
  });

  final String owner;
  final String repo;

  /// Подменяемый сервис: в бою создаётся свой с токеном в Keystore,
  /// в тестах подставляется с хранилищем в памяти.
  final ForgeService? service;

  /// Подменяемый диалог с моделью: в бою — пул бесплатных провайдеров,
  /// в тестах — скрипт, чтобы не ходить в сеть.
  final ForgeChat Function(String apiKey)? chatFactory;

  @override
  State<ForgeScreen> createState() => _ForgeScreenState();
}

class _ForgeScreenState extends State<ForgeScreen> {
  late final ForgeService _service = widget.service ?? ForgeService();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loadingToken = true;
  bool _checking = false;
  bool _running = false;
  String? _login;
  String? _tokenError;
  String _baseBranch = 'main';

  /// Разговор с агентом. Живёт между запусками приложения.
  final List<ForgeChatMessage> _messages = <ForgeChatMessage>[];

  /// Шаги текущего хода: показываются в «живом» пузыре, пока агент думает.
  final List<ForgeStep> _liveSteps = <ForgeStep>[];

  /// Имя бесплатного провайдера, который отвечает сейчас.
  String? _activeProvider;

  String? _runError;

  /// Агент один на экран: он держит рабочую ветку диалога, поэтому правки
  /// нескольких ходов ложатся в один pull request.
  ForgeAgent? _agent;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreToken());
    unawaited(_restoreChat());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreChat() async {
    final saved = await ForgeChatStore.load();
    if (!mounted || saved.isEmpty) return;
    setState(() => _messages.addAll(saved));
    _scrollToEnd();
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

  Future<void> _clearChat() async {
    setState(() {
      _messages.clear();
      _liveSteps.clear();
      _runError = null;
      _agent = null; // новая сессия — новая рабочая ветка
    });
    await ForgeChatStore.clear();
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t('forgeChatCleared', context),
      icon: Icons.cleaning_services_rounded,
    );
  }

  /// Отправка реплики: обычный ход диалога. Агент сам решает, ответить
  /// текстом или править файлы — правки заканчиваются pull request'ом.
  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
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
    final providerNote = Translations.t('forgeProvider', context);
    // Свой ключ — вещь необязательная: если хранилище настроек недоступно,
    // прогон должен идти на бесплатных провайдерах, а не падать молча.
    String apiKey = '';
    try {
      apiKey = (await SettingsService.loadAiKey()).trim();
    } catch (_) {
      apiKey = '';
    }
    if (!mounted) return;

    final history = List<ForgeChatMessage>.from(_messages);
    _inputController.clear();
    setState(() {
      _running = true;
      _runError = null;
      _liveSteps.clear();
      _activeProvider = null;
      _messages.add(
        ForgeChatMessage(
          isUser: true,
          text: text,
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
    _scrollToEnd();

    try {
      // Пул — единственный путь: «Кузница» работает и без ключа. Свой ключ
      // ИИ, если задан, просто пробуется первым, а при отказе пул
      // продолжает на бесплатных провайдерах.
      var providerLogged = false;
      final chat =
          widget.chatFactory?.call(apiKey) ??
          FreePoolForgeChat(
            apiKey: apiKey,
            onProvider: (name) {
              if (providerLogged || !mounted) return;
              providerLogged = true;
              setState(() {
                _activeProvider = name;
                _liveSteps.add(ForgeStep(tool: name, detail: providerNote));
              });
            },
          );
      final agent =
          _agent ??
          ForgeAgent(
            service: _service,
            chat: chat,
            owner: widget.owner,
            repo: widget.repo,
            baseBranch: _baseBranch,
          );
      _agent = agent;

      final turn = await agent.respond(
        history: history,
        task: text,
        baseBranch: _baseBranch,
        languageCode: languageCode,
        onStep: (step) {
          if (!mounted) return;
          setState(() => _liveSteps.add(step));
          _scrollToEnd();
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _messages.add(
          ForgeChatMessage(
            isUser: false,
            text: turn.text.isEmpty
                ? Translations.t('forgeDone', context)
                : turn.text,
            steps: turn.steps,
            pullRequestUrl: turn.pullRequestUrl,
            branch: turn.branch,
            ts: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        _liveSteps.clear();
      });
      await ForgeChatStore.save(_messages);
      if (turn.madeChanges) Haptics.heavy();
      _scrollToEnd();
    } on ForgeException catch (e) {
      _failRun(e.message);
    } catch (e) {
      _failRun(e.toString());
    }
  }

  void _failRun(String message) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _runError = message;
      _liveSteps.clear();
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
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
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: Translations.t('forgeClearChat', context),
              onPressed: _running ? null : () => unawaited(_clearChat()),
              icon: const Icon(Icons.cleaning_services_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                            Icons.forum_rounded,
                            Translations.t('forgeChatSection', context),
                          ),
                          const SizedBox(height: 8),
                          if (_messages.isEmpty && !_running)
                            _emptyChat(theme, cs),
                          for (final message in _messages)
                            _bubble(theme, cs, accent, message),
                          if (_running) _runningBubble(theme, cs, accent),
                          if (_runError != null) ...[
                            const SizedBox(height: 12),
                            _errorCard(theme, cs),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _inputBar(theme, cs, accent),
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

  Widget _emptyChat(ThemeData theme, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Translations.t('forgeChatEmpty', context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Пузырь реплики: вопрос справа, ответ агента слева. В ответе видны шаги
  /// работы и ссылка на pull request — так видно, что именно агент сделал.
  Widget _bubble(
    ThemeData theme,
    ColorScheme cs,
    Color accent,
    ForgeChatMessage message,
  ) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser
              ? accent.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUser
                ? accent.withValues(alpha: 0.35)
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Row(
                children: [
                  Icon(Icons.smart_toy_outlined, size: 15, color: accent),
                  const SizedBox(width: 7),
                  Text(
                    Translations.t('forgeTitle', context, 'Кузница'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            SelectableText(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            if (message.steps.isNotEmpty) ...[
              const SizedBox(height: 10),
              _stepsList(theme, cs, message.steps),
            ],
            if (message.pullRequestUrl != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.merge_type_rounded,
                    size: 16,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      message.pullRequestUrl!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (message.branch != null && message.steps.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${Translations.t('forgeBranch', context)}: ${message.branch}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Пузырь «агент работает»: шаги появляются по мере выполнения.
  Widget _runningBubble(ThemeData theme, ColorScheme cs, Color accent) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _activeProvider == null
                        ? Translations.t('forgeThinking', context)
                        : '${Translations.t('forgeThinking', context)} · '
                              '$_activeProvider',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (_liveSteps.isNotEmpty) ...[
              const SizedBox(height: 10),
              _stepsList(theme, cs, _liveSteps),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepsList(ThemeData theme, ColorScheme cs, List<ForgeStep> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  step.ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 14,
                  color: step.ok ? cs.primary : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${step.tool}: ${step.detail}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Поле ввода закреплено снизу: в чате оно должно быть под рукой, а не
  /// уезжать вверх вместе с длинной историей.
  Widget _inputBar(ThemeData theme, ColorScheme cs, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Поле — в том же обёрточном стиле, что и остальные поля ввода
              // приложения: SmoothTyping плавно проявляет буквы, курсор
              // анимированный, лупа и лишнее меню отключены.
              SmoothTyping(
                controller: _inputController,
                builder: (typingStyle) => TextField(
                  controller: _inputController,
                  style: typingStyle,
                  minLines: 1,
                  maxLines: 6,
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
                  onPressed: _running ? null : _send,
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _running
                        ? Translations.t('forgeWorking', context)
                        : Translations.t('forgeRun', context),
                  ),
                ),
              ),
            ],
          ),
        ),
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
