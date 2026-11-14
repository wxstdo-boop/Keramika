part of 'settings_screen.dart';

/// Ада: включение, ключ, слежение и утренний/вечерний разбор.
extension _SettingsSectionAda on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы uild оставался читаемым.
  List<Widget> _settingsAdaSection(
    BuildContext context,
    AgyshaAppState appState,
    ThemeData theme,
  ) => <Widget>[
    const SizedBox(height: 8),
    // === Искусственный проводник: мини-чат с ИИ у кнопки «+». ===
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Значок Ады: своя «искры-светлячок» вместо общей
                // иконки-компаса — плавная анимация при тапе, как у
                // канарейки в уголке разработчика, только другой персонаж.
                const AdaIcon(size: 34),
                const SizedBox(width: 10),
                Text(
                  Translations.t('aiGuide', context, 'AI guide'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.auto_awesome,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  Translations.t('aiGuideToggle', context, 'Enable AI guide'),
                ),
                subtitle: Text(
                  Translations.t(
                    'aiGuideDesc',
                    context,
                    'A small circle appears next to the “+” button and opens a mini chat.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_aiGuide;
                  await SettingsService.saveAiGuide(newVal);
                  _refresh(() => _aiGuide = newVal);
                },
                trailing: VolumetricSwitch(
                  value: _aiGuide,
                  onChanged: (v) async {
                    await SettingsService.saveAiGuide(v);
                    _refresh(() => _aiGuide = v);
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            // Поле ключа появляется/исчезает плавно (SizeTransition + fade).
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              transitionBuilder: (child, animation) => SizeTransition(
                sizeFactor: animation,
                alignment: AlignmentDirectional.topStart,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: _aiGuide
                  ? Padding(
                      key: const ValueKey('ai_key_fields'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Text(
                            'Poolside / Agnes AI / Zen — API key',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Поле обёрнуто в FadeTransition: при переключении
                          // глазка текст плавно «переливается» (пульсация),
                          // не теряя фокус и не пересоздавая поле.
                          FadeTransition(
                            opacity: Tween<double>(begin: 0.35, end: 1.0)
                                .animate(
                                  CurvedAnimation(
                                    parent: _keyPulse,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: SmoothTyping(
                              controller: _aiKeyController,
                              // Ключ, скрытый «звёздочками», рисует само поле:
                              // по точкам анимация бессмысленна.
                              enabled: _aiKeyVisible,
                              builder: (style) => TextField(
                                style: style,
                                cursorOpacityAnimates: true,
                                magnifierConfiguration:
                                    TextMagnifierConfiguration.disabled,
                                controller: _aiKeyController,
                                contextMenuBuilder: minimalContextMenuBuilder,
                                obscureText: !_aiKeyVisible,
                                textInputAction: TextInputAction.done,
                                maxLength: 500,
                                inputFormatters: const [],
                                enableSuggestions: false,
                                autocorrect: false,
                                maxLines: 1,
                                decoration: InputDecoration(
                                  isDense: true,
                                  counterText: '',
                                  hintText:
                                      'Вставь ключ Poolside, Agnes AI или Zen',
                                  suffixIcon: AnimatedSwitcher(
                                    duration: const Duration(
                                      milliseconds: 220,
                                    ),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: animation,
                                            child: child,
                                          ),
                                        ),
                                    child: IconButton(
                                      key: ValueKey(
                                        'ai_key_eye_$_aiKeyVisible',
                                      ),
                                      icon: Icon(
                                        _aiKeyVisible
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        _refresh(
                                          () =>
                                              _aiKeyVisible = !_aiKeyVisible,
                                        );
                                        // Мягкий «перелив» текста ключа.
                                        _keyPulse.forward(from: 0);
                                      },
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onChanged: (v) => _aiKey = v,
                                onSubmitted: (v) =>
                                    SettingsService.saveAiKey(v),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Описание Ады: одна фраза про бесплатные модели.
                          Builder(
                            builder: (context) {
                              final note = Translations.t(
                                'aiGuideKeyNote',
                                context,
                                'Ада использует встроенные бесплатные модели (100 сообщений на ADA, остальное — FreeLLMPool).',
                              );
                              return Text(
                                note,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                          const Divider(height: 20),
                          // Ада-трекинг: утренний отчёт + вечерний разбор.
                          PressScale(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: const Icon(
                                Icons.wb_sunny_outlined,
                                color: Color(0xFFE89B3C),
                              ),
                              title: Text(
                                Translations.t(
                                  'adaTracking',
                                  context,
                                  'Ada tracking',
                                ),
                              ),
                              subtitle: Text(
                                Translations.t(
                                  'adaTrackingDesc',
                                  context,
                                  'Morning report “what is planned today” at 08:00 and evening review at 21:00 as notifications.',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              onTap: () => _toggleAiTracking(!_aiTracking),
                              trailing: VolumetricSwitch(
                                value: _aiTracking,
                                onChanged: _toggleAiTracking,
                                activeColor: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('ai_key_hidden')),
            ),
          ],
        ),
      ),
    ),
  ];
}
