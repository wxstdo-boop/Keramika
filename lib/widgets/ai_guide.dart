import 'dart:convert';
import '../services/haptics.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/translations.dart';
import '../services/ai_guide_service.dart';
import '../services/json_file.dart';
import '../services/prefs.dart';
import '../services/settings_service.dart';
import '../overlay/overlay_bridge.dart';
import '../utils/snackbar.dart';
import '../utils/context_menu.dart';
import '../utils/markdown_text.dart';
import '../widgets/beautiful_selection.dart';

export 'berserk_sheet.dart';

/// Режим «в окне»: мини-чат свернут в плавающее окошко поверх приложения.
/// Значение хранится в prefs ('ai_floating') — переживает перезапуск.
final ValueNotifier<bool> aiFloating = ValueNotifier<bool>(false);

/// Приватность: плавающее окошко скрывается, когда открыт экран блокировки
/// (PIN) — чтобы нельзя было открыть чат в обход блокировки.
final ValueNotifier<bool> aiLockScreenVisible = ValueNotifier<bool>(false);

/// Глобальный счётчик активных чатов — защита от множественного открытия
/// плавающего окошка (tap → chat → tap → chat → ...).
int _activeChats = 0;

/// Маленький кружок рядом с кнопкой «+». Появляется, когда в настройках
/// включён «Искусственный проводник». Открывает мини-чат Ады.
class AiGuideFloatingButton extends StatefulWidget {
  const AiGuideFloatingButton({super.key});

  @override
  State<AiGuideFloatingButton> createState() => _AiGuideFloatingButtonState();
}

class _AiGuideFloatingButtonState extends State<AiGuideFloatingButton> {
  @override
  void initState() {
    super.initState();
    // Подтягиваем текущее значение в notifier (на случай, если settings
    // ещё не грузились) — и виджет сам подхватит его через слушатель.
    SettingsService.loadAiGuide();
  }

  @override
  Widget build(BuildContext context) {
    // Живой слушатель: кружок появляется МГНОВЕННО при включении
    // проводника в настройках — без перезапуска приложения.
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.aiGuideEnabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        // Режим «в окне» включён — кружок у «+» скрыт, живёт окошко.
        // Возвращение кнопки после закрытия окошка — плавное (fade+scale
        // с пружинкой), а не мгновенное.
        return ValueListenableBuilder<bool>(
          valueListenable: aiFloating,
          builder: (context, floating, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: floating
                  ? const SizedBox.shrink(key: ValueKey('hidden'))
                  : KeyedSubtree(
                      key: const ValueKey('ada_fab'),
                      child: _buildFab(context),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _buildFab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      // Stable heroTag: rebuilding settings/chat must never move or recreate
      // the floating Ada button as a new hero on a weak Android device.
      heroTag: 'ai_guide_fab',
      tooltip: Translations.t('aiGuide', context, 'AI guide'),
      onPressed: () => showAiGuideChat(context),
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      child: const _AdaAvatar(size: 20),
    );
  }
}

/// Вариант аватарки Ады: градиент + значок.
class _AdaVariant {
  final List<Color> colors;
  final IconData icon;
  const _AdaVariant(this.colors, this.icon);
}

/// Все варианты Ады: 6 авторских + 114 сгенерированных = 120 уникальных
/// градиентов. Индекс выбранного сохраняется в prefs ('ada_avatar_variant')
/// и переживает перезапуск; тап по аватарке/имени меняет его рандомно.
/// Генерация детерминированная — порядок стабилен между запусками.
final List<_AdaVariant> _adaVariants = _buildAdaVariants();

List<_AdaVariant> _buildAdaVariants() {
  const specials = <_AdaVariant>[
    _AdaVariant([
      Color(0xFFFF9EC6),
      Color(0xFFB06AB3),
      Color(0xFF7C4DFF),
    ], Icons.favorite),
    _AdaVariant([
      Color(0xFFFFB199),
      Color(0xFFFF6B9D),
      Color(0xFFE63946),
    ], Icons.local_florist),
    _AdaVariant([
      Color(0xFF9BE8FF),
      Color(0xFF7C4DFF),
      Color(0xFF2E3192),
    ], Icons.auto_awesome),
    _AdaVariant([
      Color(0xFF8BF0C8),
      Color(0xFF2BB3A0),
      Color(0xFF0F6E6E),
    ], Icons.wb_sunny),
    _AdaVariant([
      Color(0xFFFFD166),
      Color(0xFFFF8C42),
      Color(0xFFD62828),
    ], Icons.star),
    _AdaVariant([
      Color(0xFFC9B8FF),
      Color(0xFF8E7CFF),
      Color(0xFF4A3F9E),
    ], Icons.psychology),
  ];
  // Набор значков: повторяется через каждые 24 варианта, но hue каждый раз
  // другой (шаг 47° по цветовому кругу) — комбинации не повторяются.
  const icons = <IconData>[
    Icons.favorite,
    Icons.local_florist,
    Icons.auto_awesome,
    Icons.wb_sunny,
    Icons.star,
    Icons.psychology,
    Icons.bolt,
    Icons.flare,
    Icons.water_drop,
    Icons.eco,
    Icons.rocket_launch,
    Icons.diamond,
    Icons.energy_savings_leaf,
    Icons.nights_stay,
    Icons.face_retouching_natural,
    Icons.celebration,
    Icons.shield_moon,
    Icons.spa,
    Icons.forest,
    Icons.emoji_emotions,
    Icons.light_mode,
    Icons.wb_twilight,
    Icons.air,
    Icons.blur_on,
  ];
  final generated = <_AdaVariant>[];
  for (var i = 0; i < 114; i++) {
    final hue = (i * 47) % 360;
    final band = i ~/ 24;
    final sat = (0.52 + 0.30 * (band % 3)).clamp(0.0, 1.0);
    final light = (0.46 + 0.16 * ((band ~/ 3) % 3)).clamp(0.0, 1.0);
    final c1 = HSLColor.fromAHSL(1, hue.toDouble(), sat, light).toColor();
    final c2 = HSLColor.fromAHSL(
      1,
      ((hue + 36) % 360).toDouble(),
      sat,
      (light - 0.10).clamp(0.0, 1.0),
    ).toColor();
    final c3 = HSLColor.fromAHSL(
      1,
      ((hue + 72) % 360).toDouble(),
      sat,
      (light - 0.20).clamp(0.0, 1.0),
    ).toColor();
    generated.add(_AdaVariant([c1, c2, c3], icons[i % icons.length]));
  }
  return [...specials, ...generated];
}

int _savedAvatarVariant() => (globalPrefs.getInt('ada_avatar_variant') ?? 0)
    .clamp(0, _adaVariants.length - 1);

/// Живой индекс значка Ады: ВСЕ аватарки (шапка, пузыри сообщений и плавающее
/// мини-окошко) следят за ним и меняются мгновенно и плавно, где бы их ни
/// нажали — работает из любого места приложения.
final ValueNotifier<int> adaAvatarVariant = ValueNotifier<int>(
  _savedAvatarVariant(),
);

/// Тап по сердечку/значку Ады — случайный другой вариант. Сохраняется
/// навсегда (переживает перезапуск). Вызывается из шапки, пузырей и
/// плавающего окошка.
void cycleAdaAvatar() {
  // Переключаем только на УНИКАЛЬНЫЙ значок: вариант с той же иконкой,
  // что у текущего, пропускаем — раньше могли «выпадать» дубли.
  final cur = _adaVariants[adaAvatarVariant.value];
  var next = adaAvatarVariant.value;
  var guard = 0;
  while (guard < _adaVariants.length * 3) {
    next = math.Random().nextInt(_adaVariants.length);
    final v = _adaVariants[next];
    if (v.icon != cur.icon) break;
    guard++;
  }
  // Вырожденный случай (не нашли с первого захода) — соседний индекс.
  if (next == adaAvatarVariant.value) {
    next = (adaAvatarVariant.value + 1) % _adaVariants.length;
  }
  adaAvatarVariant.value = next;
  globalPrefs.setInt('ada_avatar_variant', next);
  Haptics.select();
}

/// Аватарка Ады — градиентный кружок со свечением и бликом.
/// [variantIndex] — индекс в [_adaVariants]; -1 — следит за живым
/// [adaAvatarVariant] (меняется сразу во всех местах).
class _AdaAvatar extends StatelessWidget {
  final double size;
  final int variantIndex;
  const _AdaAvatar({super.key, this.size = 34, this.variantIndex = -1});

  @override
  Widget build(BuildContext context) {
    if (variantIndex >= 0) return _core(context, _adaVariants[variantIndex]);
    return ValueListenableBuilder<int>(
      valueListenable: adaAvatarVariant,
      builder: (context, idx, _) => _core(context, _adaVariants[idx]),
    );
  }

  Widget _core(BuildContext context, _AdaVariant v) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: v.colors,
        ),
        boxShadow: [
          BoxShadow(
            color: v.colors[1].withValues(alpha: 0.45),
            blurRadius: size * 0.35,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Блик сверху — «стеклянный» объём.
          Positioned(
            top: size * 0.06,
            left: size * 0.16,
            child: Container(
              width: size * 0.42,
              height: size * 0.24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Значок Ады (плавно меняется на другой при тапе).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              v.icon,
              key: ValueKey<int>(v.icon.codePoint),
              size: size * 0.42,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}

/// Открывает мини-чат Ады снизу экрана.
Future<void> showAiGuideChat(BuildContext context) {
  if (_activeChats > 0) return Future<void>.value();
  _activeChats++;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Плавный выезд с МЯГКИМ стартом: easeInOutQuart — начинает медленно
    // и так же плавно останавливается. Раньше был easeOutQuart, который
    // стартует с максимальной скоростью — отсюда «дёрганое начало».
    // Закрытие — тот же мягкий профиль, без резких рывков.
    sheetAnimationStyle: AnimationStyle(
      curve: Curves.easeInOutQuart,
      duration: const Duration(milliseconds: 500),
      reverseCurve: Curves.easeInOutQuart,
      reverseDuration: const Duration(milliseconds: 380),
    ),
    // Отделяем тяжёлую ленту чата в отдельный composited layer: во время
    // выезда bottom sheet Android двигает готовый слой, а не перерисовывает
    // весь экран и все карточки под ним на каждом кадре.
    builder: (_) => const RepaintBoundary(child: _AiChatSheet()),
  ).whenComplete(() => _activeChats = 0);
}

class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet();

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet>
    with SingleTickerProviderStateMixin {
  static const _historyKey = 'ai_chat_history';
  static const _pinsKey = 'ai_pinned_messages';
  static const int _maxPins = 10;

  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  final List<AiMessage> _messages = [];
  // Закреплённые сообщения Ады: живут отдельно от чата и НЕ стираются
  // вместе с ним — только ручным откреплением.
  final List<AiMessage> _pinned = [];
  // Сообщения, отмеченные сердечком (лайк). Живут отдельно от чата,
  // переживают очистку и перезапуск приложения.
  final Set<String> _liked = {};
  bool _busy = false;
  bool _error = false;
  String _errorMsg = '';
  // Веб-поиск: значок перед быстрыми чипами плавно включает режим,
  // при котором Ада реально ищет в интернете (DuckDuckGo + Wikipedia).
  bool _webSearch = false;
  // Плавная передача эстафеты «печатает…» → ответ: индикатор сначала
  // гаснет, и только потом ответ всплывает — без резкого щелчка.
  bool _typingFade = false;
  // Сколько сообщений было в чате на момент открытия. Анимация входа
  // пузыря — ТОЛЬКО у новых (добавленных ПОСЛЕ открытия): иначе при
  // открытии последние 3 сообщения истории «всплывали» прямо во время
  // выезда листа, и появление чата казалось дёрганым.
  int _openedCount = 0;
  String _lang = 'en';
  int _quotaLeft = 0;
  String _modelLabel = 'ada-0.0.3';
  // Плавная очистка чата: список гаснет, потом стирается.
  late final AnimationController _clearCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  // Троеточие тикает ТОЛЬКО пока Ада отвечает (repeat/stop в _send):
  // вечный repeat() гонял кадры даже когда индикатор не виден — на
  // слабых устройствах это постоянный расход CPU/батареи.
  late final AnimationController _dotsCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadPins();
    _loadLiked();
    // Ада-трекинг: если утренний (08:00) или вечерний (21:00) отчёт уже
    // наступил, а в чат ещё не писался — Ада пишет его сюда. История
    // загружается сразу, сообщение подхватится через _onAdaReportTick.
    _ensureReports();
    // Открытый чат слушает доставку и перечитывает историю — отчёт
    // появляется в ленте в момент доставки, без переоткрытия.
    AiGuideService.adaReportTick.addListener(_onAdaReportTick);
    SettingsService.loadLanguageCode()
        .then((c) {
          if (!mounted) return;
          setState(() => _lang = c);
          _claimRewards();
        })
        .catchError((_) {});
    AiGuideService.hfRemainingToday()
        .then((n) {
          if (mounted) setState(() => _quotaLeft = n);
        })
        .catchError((_) {});
    AiGuideService.currentModelLabel()
        .then((m) {
          if (mounted) setState(() => _modelLabel = m);
        })
        .catchError((_) {});
    // Веб-поиск: запоминаем, был ли он включён — переживает перезапуск.
    try {
      _webSearch = globalPrefs.getBool('ai_web_search') ?? false;
    } catch (_) {}
  }

  /// Догоняет пропущенный отчёт Ады (если время наступило) и подхватывает
  /// его в ленту. В фоне: история уже на экране, сообщение появится
  /// плавно, когда ИИ допишет.
  Future<void> _ensureReports() async {
    try {
      final delivered = await AiGuideService.maybeDeliverAdaReports('');
      if (delivered.isNotEmpty) await _loadHistory();
    } catch (_) {}
  }

  void _onAdaReportTick() {
    _loadHistory();
  }

  void _refreshModelLabel() {
    AiGuideService.currentModelLabel()
        .then((m) {
          if (mounted && m != _modelLabel) setState(() => _modelLabel = m);
        })
        .catchError((_) {});
  }

  void _cycleAvatar() {
    // adaAvatarVariant сам уведомляет все аватарки. Не вызываем setState
    // всего чата: это лишний полный rebuild ленты на слабом телефоне.
    cycleAdaAvatar();
  }

  @override
  void dispose() {
    AiGuideService.adaReportTick.removeListener(_onAdaReportTick);
    _clearCtrl.dispose();
    _dotsCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final raw = await JsonFile.read(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            // Чат исчерпал 1000 сообщений — стираем и начинаем заново.
            if (loaded.length >= 1000) {
              _messages.clear();
            } else {
              _messages
                ..clear()
                ..addAll(loaded);
            }
            // Всё, что было загружено при открытии, НЕ анимирует вход —
            // только сообщения, добавленные после (см. animate ниже).
            _openedCount = _messages.length;
          });
          _saveHistory();
          // Открытие чата: мгновенно на последнее сообщение, без
          // «проезда» по всей истории.
          _scrollToBottom(animate: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      await JsonFile.write(
        _historyKey,
        jsonEncode(_messages.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _loadPins() async {
    try {
      final raw = await JsonFile.read(_pinsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _pinned
              ..clear()
              ..addAll(loaded.take(_maxPins));
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _savePins() async {
    try {
      await JsonFile.write(
        _pinsKey,
        jsonEncode(_pinned.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Ключ сообщения для лайков/закрепления — текст+автор (сообщения в чате
  /// неизменны, так что совпадений между разными сообщениями нет).
  String _msgKey(AiMessage m) => '${m.text.hashCode}_${m.isUser}';

  /// Лайки переживают перезапуск (хранятся отдельно key => ключ сообщения).
  void _loadLiked() {
    final raw = globalPrefs.getStringList('ai_liked_messages');
    if (raw != null) {
      _liked
        ..clear()
        ..addAll(raw);
    }
  }

  void _saveLiked() {
    globalPrefs.setStringList('ai_liked_messages', _liked.toList());
  }

  /// Сердечко на сообщении Ады: пустое ↔ залитое, плавно и навсегда.
  void _toggleLike(AiMessage m) {
    final k = _msgKey(m);
    setState(() {
      if (_liked.contains(k)) {
        _liked.remove(k);
      } else {
        _liked.add(k);
      }
    });
    _saveLiked();
    // Ада «запоминает» стиль/содержание лайкнутого ответа и подстраивается
    // под него в следующих сообщениях (паттерн живёт в системном промпте).
    if (!m.isUser) {
      AiGuideService.rememberLikedPattern(m.text);
    }
    Haptics.select();
  }

  bool _isPinned(AiMessage m) =>
      _pinned.any((p) => p.text == m.text && p.isUser == m.isUser);

  /// Копировать сообщение Ады — всегда доступно кнопкой на пузыре, даже если
  /// системный тулбар выделения не появился.
  Future<void> _copyMessage(AiMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.text));
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t('copied', context, 'Скопировано'),
      icon: Icons.copy,
      iconColor: Colors.lightBlueAccent,
      groupKey: 'ada_copy',
    );
  }

  /// Зажать сообщение Ады — закрепить (плавно уезжает вверх, до 10 штук).
  /// Повторное зажатие открепляет.
  void _togglePin(AiMessage m) {
    if (m.isUser) return;
    var limitHit = false;
    setState(() {
      final idx = _pinned.indexWhere(
        (p) => p.text == m.text && p.isUser == m.isUser,
      );
      if (idx >= 0) {
        _pinned.removeAt(idx);
      } else if (_pinned.length < _maxPins) {
        _pinned.add(m);
      } else {
        limitHit = true;
      }
    });
    _savePins();
    if (limitHit) {
      // Лимит 10: ничего не стираем, просто мягко подсказываем.
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'pinLimit',
          context,
          'You can pin up to 10 messages',
        ),
        icon: Icons.push_pin_outlined,
        iconColor: Theme.of(context).colorScheme.primary,
        groupKey: 'ada_pin_limit',
      );
      Haptics.select();
    }
  }

  void _scrollToBottom({bool animate = true}) {
    // Лента с reverse:true — индекс 0 это низ чата, открытие сразу
    // показывает последнее сообщение БЕЗ итеративных прыжков (раньше
    // цикл сходимости из 14 jumpTo дёргал layout и «лагал» появление).
    // Новые сообщения появляются у низа автоматически; animate — плавный
    // возврат к низу, если пользователь листал историю вверх.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (animate) {
        if (pos.pixels > 4) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (pos.pixels > 0) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  String _friendlyAiError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return 'Ада не успела получить ответ. Попробуй ещё раз через мгновение.';
    }
    if (raw.contains('429') || raw.contains('rate')) {
      return 'Ада сейчас занята — я уже попробую другой бесплатный канал.';
    }
    if (raw.contains('все провайдеры') || raw.contains('unavailable')) {
      return 'Все бесплатные каналы сейчас недоступны. Проверь интернет — '
          'или вставь свой ключ Poolside в настройках, и нажми «обновить».';
    }
    return 'Связь с Адой прервалась. Нажми обновить — я попробую снова.';
  }

  /// Отправляет сообщение. [text] — если null, берём из поля ввода.
  /// Мелкий круглый значок веб-поиска: листается вместе с таблетками
  /// (вставлен первым элементом в горизонтальный список), включается и
  /// выключается плавно — заливается фирменным цветом, появляется
  /// свечение, иконка мягко меняется (fade + лёгкий scale БЕЗ перелёта).
  /// Фон свой (нейтральный), НЕ таблетный — значок всегда различим.
  Widget _buildWebSearchToggle(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    return Tooltip(
      message: Translations.t(
        _webSearch ? 'aiWebSearchOn' : 'aiWebSearch',
        context,
        _webSearch ? 'Web search ON' : 'Web search',
      ),
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.light();
          setState(() {
            _webSearch = !_webSearch;
            try {
              globalPrefs.setBool('ai_web_search', _webSearch);
            } catch (_) {}
          });
        },
        child: ClipOval(
          // ClipOval: иконка при анимации НИКОГДА не вылезает за круг.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Чёткий круг БЕЗ boxShadow: размытая тень выглядела
              // «размазанно-таблетной» вместо круглого значка.
              shape: BoxShape.circle,
              color: _webSearch ? cs.primary : cs.surface,
              border: Border.all(
                color: _webSearch
                    ? cs.primary
                    : cs.outline.withValues(alpha: 0.45),
                width: 1.4,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              // Только fade, БЕЗ scale: иконка не увеличивается и не
              // «заезжает за границы» при переключении.
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Icon(
                _webSearch ? Icons.travel_explore : Icons.public,
                key: ValueKey('web_toggle_icon_$_webSearch'),
                size: 19,
                color: _webSearch ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [keepUserBubble] — true при повторной отправке с плашки «ИИ на курорте»:
  /// сообщение уже на экране, дубликат не добавляем.
  Future<void> _send({String? text, bool keepUserBubble = false}) async {
    final message = (text ?? _inputCtrl.text).trim();
    if (message.isEmpty || _busy) return;
    Haptics.light();
    _inputCtrl.clear();
    setState(() {
      // Лимит чата: 1000 сообщений, дальше — стереть и начать новый диалог.
      if (_messages.length >= 1000) _messages.clear();
      if (!keepUserBubble) {
        _messages.add(AiMessage(isUser: true, text: message));
      }
      _busy = true;
      _error = false;
    });
    _dotsCtrl.repeat();
    _saveHistory();
    _scrollToBottom();
    try {
      final answer = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: _lang,
        useWebSearch: _webSearch,
      );
      if (!mounted) return;
      // Эстафета «печатает…» → ответ: индикатор плавно гаснет, и только
      // потом ответ всплывает (его собственная анимация входа).
      _dotsCtrl.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 210));
      if (!mounted) return;
      setState(() {
        // Пустой ответ («три точки») никогда не показываем — вместо него
        // запасная фраза, чтобы не выглядело, будто Ада «промолчала».
        final finalText = answer.trim().isEmpty
            ? Translations.t(
                'aiEmptyAnswer',
                context,
                'Хм, я не смогла собрать ответ. Попробуй ещё раз!',
              )
            : answer;
        _messages.add(AiMessage(isUser: false, text: finalText));
        if (_messages.length > 1000) {
          _messages.removeRange(0, _messages.length - 1000);
        }
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      AiGuideService.hfRemainingToday().then((n) {
        if (mounted) setState(() => _quotaLeft = n);
      });
      _refreshModelLabel();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _dotsCtrl.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 210));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _errorMsg = _friendlyAiError(e);
        _typingFade = false;
      });
      _scrollToBottom();
      // Плашка «ИИ на курорте» остаётся видимой, пока пользователь не
      // нажмёт «обновить» или не отправит новое сообщение: иначе при
      // медленной/заблокированной сети создаётся впечатление, что Ада
      // «просто не ответила на сообщение».
      // (Скрывается в начале _send при новом сообщении: _error = false.)
    }
  }

  /// Кнопка «Повторить» на плашке: переотправляет ПОСЛЕДНЕЕ сообщение
  /// пользователя БЕЗ дубликата — пузырь остаётся на месте, плашка гаснет,
  /// идёт новая отправка того же текста.
  void _retryLast() {
    final lastUser = _messages.lastWhere(
      (m) => m.isUser,
      orElse: () => const AiMessage(isUser: true, text: ''),
    );
    if (lastUser.text.isEmpty) return;
    setState(() => _error = false);
    _send(text: lastUser.text, keepUserBubble: true);
  }

  /// «Отменить последнее действие» — удаляет созданное Адой или
  /// восстанавливает удалённое. Результат появляется в чате как ответ Ады.
  Future<void> _undoLast() async {
    final result = await AiGuideService.undoLastAction();
    if (!mounted) return;
    setState(() {
      _messages.add(AiMessage(isUser: false, text: result));
    });
    _saveHistory();
    _scrollToBottom();
  }

  /// Плавная очистка всего чата: список гаснет (350мс), потом стирается.
  void _clearChat() {
    if (_messages.isEmpty && !_busy) return;
    if (_clearCtrl.isAnimating) return;
    _clearCtrl.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _busy = false;
        _error = false;
      });
      _dotsCtrl.stop();
      _saveHistory();
      _clearCtrl.reset();
    });
  }

  /// Свернуть чат в плавающее окошко / выключить окошко (обратное нажатие).
  ///
  /// На Android — СИСТЕМНЫЙ оверлей поверх ДРУГИХ приложений (живёт даже
  /// после выхода из приложения): сначала окно-чат, тап по «Ада, ничего
  /// не надо» сворачивает его в пузырь, который сам катается по экрану.
  /// На web — внутриприложенный пузырь (плагин оверлея не поддерживает web).
  Future<void> _toggleFloating() async {
    final next = !aiFloating.value;
    if (next) {
      if (!kIsWeb) {
        // Android: сразу показываем системный оверлей (с запросом
        // разрешения «поверх других приложений», если его ещё нет).
        final ctx = context;
        final dpr = View.of(ctx).devicePixelRatio;
        final size = MediaQuery.sizeOf(ctx);
        final shown = await ensureAdaOverlay(
          devicePixelRatio: dpr,
          screenWidth: size.width,
          screenHeight: size.height,
        );
        if (!shown) {
          // Разрешение не дали — показываем подсказку и остаёмся в чате.
          if (ctx.mounted) {
            showBeautifulSnackBar(
              ctx,
              message: Translations.t(
                'aiOverlayPermissionHint',
                ctx,
                'Allow Keramika to draw over other apps to enable the mini window',
              ),
              icon: Icons.warning_amber_rounded,
              iconColor: Theme.of(ctx).colorScheme.error,
              duration: const Duration(seconds: 3),
              groupKey: 'ada_window',
            );
          }
          return;
        }
      }
      aiFloating.value = true;
      globalPrefs.setBool('ai_floating', true);
      // Свернули — закрываем чат (на Android живёт системный оверлей,
      // на web — внутренний пузырь).
      showBeautifulSnackBar(
        context,
        message: Translations.t(
          'aiWindowHint',
          context,
          'Collapsed to a mini window — tap it to return',
        ),
        icon: Icons.picture_in_picture_alt_outlined,
        iconColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 2),
        groupKey: 'ada_window',
      );
      if (mounted && context.mounted) Navigator.pop(context);
    } else {
      // Выключили — окошко исчезает, чат остаётся открытым.
      aiFloating.value = false;
      globalPrefs.setBool('ai_floating', false);
      if (!kIsWeb) await closeAdaOverlay();
    }
  }

  /// Открепить сообщение (тап на крестик в панели закреплённых).
  void _unpin(AiMessage m) {
    setState(() {
      _pinned.removeWhere((p) => p.text == m.text && p.isUser == m.isUser);
    });
    _savePins();
  }

  /// Награды Ады (стрики, все задачи выполнены) появляются в чате первым
  /// сообщением при открытии. Каждая награда выдаётся только один раз.
  Future<void> _claimRewards() async {
    try {
      final rewards = await AiGuideService.collectRewards(_lang);
      if (!mounted || rewards.isEmpty) return;
      setState(() {
        for (final r in rewards) {
          _messages.add(AiMessage(isUser: false, text: r));
        }
      });
      _saveHistory();
      _scrollToBottom();
    } catch (_) {
      // Награды — не критично: сбой не должен ронять чат.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    // Клавиатура: лист плавно ПОДНИМАЕТСЯ над ней (AnimatedPadding),
    // а высота ужимается, чтобы шапка не уходила за экран. Поле ввода
    // всегда видно. Лист на весь экран — нет «белой полосы» снизу.
    final insets = media.viewInsets.bottom;
    final available = media.size.height - insets;
    final sheetHeight = available.clamp(260.0, available);

    // БЕЗ AnimatedPadding/AnimatedContainer: на Android 11+ viewInsets
    // приходит покадрово вместе с анимацией клавиатуры — обычный Padding
    // и Container двигают лист ровно с ней. Свои 200-220 мс задержки
    // открывали белую полосу под листом, когда клавиатура уже уехала.
    //
    // ВАЖНО про дёрганье: тяжёлое содержимое (лента сообщений) обёрнуто в
    // MediaQuery.removeViewInsets — при поднятии/опускании клавиатуры
    // viewInsets меняются покадрово, и БЕЗ изоляции весь чат пересобирался
    // на каждом кадре (отсюда «дёрганое тормозное» поднятие). Теперь
    // двигается только лёгкая оболочка (Padding + Container), а содержимое
    // не перестраивается пока идёт анимация клавиатуры.
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // Поле ввода должно видеть клавиатуру (каретка/выделение), поэтому
        // изолируем ТОЛЬКО ленту сообщений (см. _buildMessages), а не весь
        // лист. Здесь оставляем как есть — само содержимое ниже уже
        // отрисовано в отдельном слое.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ручка.
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Шапка — Ада. Тап по имени/аватарке меняет её значок.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cycleAvatar,
                    // Живой слушатель adaAvatarVariant: смена значка из ЛЮБОГО
                    // места (тап по сердечку у сообщений, шапка, мини-чат)
                    // мгновенно и плавно обновляет аватарку в шапке.
                    child: ValueListenableBuilder<int>(
                      valueListenable: adaAvatarVariant,
                      builder: (context, idx, _) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: _AdaAvatar(
                          variantIndex: idx,
                          key: ValueKey('ada_avatar_$idx'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _cycleAvatar,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Строка 1: «Ада, ничего не надо».
                          Text(
                            '${Translations.t('adaName', context, 'Ада')}, '
                            '${Translations.t('adaTagline', context, 'ничего не надо')}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // Строка 2: кто ответил и какая модель —
                          // Kilo · openrouter/free / LLM7 · codestral.
                          // Переключается плавно при смене провайдера.
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SizeTransition(
                                    sizeFactor: animation,
                                    alignment: AlignmentDirectional.topStart,
                                    child: child,
                                  ),
                                ),
                            child: Text(
                              _modelLabel,
                              key: ValueKey(_modelLabel),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Кнопка очистки чата. Без серой подсветки при наведении.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _clearChat,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.delete_sweep_outlined,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // Свернуть чат в плавающее окошко (режим «в окне»).
                  ValueListenableBuilder<bool>(
                    valueListenable: aiFloating,
                    builder: (context, floating, _) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleFloating,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          floating
                              ? Icons.picture_in_picture_alt
                              : Icons.picture_in_picture_alt_outlined,
                          size: 22,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Закреплённые сообщения Ады — живут над чатом, не стираются
            // очисткой. Открепляются тапом на крестик.
            AnimatedSize(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.35),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _pinned.isEmpty
                    ? const SizedBox(
                        key: ValueKey('pins_none'),
                        width: double.infinity,
                      )
                    : _PinnedBar(
                        key: const ValueKey('pins_bar'),
                        pinned: _pinned,
                        onUnpin: _unpin,
                      ),
              ),
            ),
            // Сообщения (гаснут при очистке).
            //
            // Лента изолирована от изменений MediaQuery (RepaintBoundary +
            // MediaQuery.removeViewInsets): при поднятии/опускании клавиатуры
            // viewInsets меняются покадрово, и БЕЗ изоляции тяжёлая лента
            // (сотни сообщений) пересобиралась на каждом кадре — отсюда
            // «дёрганое тормозное» поднятие клавиатуры в чате. Теперь
            // двигается только лёгкая оболочка (Padding + Container), а лента
            // остаётся готовой текстурой.
            Expanded(
              child: MediaQuery.removeViewInsets(
                context: context,
                removeBottom: true,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                animation: _clearCtrl,
                builder: (context, child) =>
                    Opacity(opacity: 1.0 - _clearCtrl.value, child: child),
                // Stack: лента ВСЕГДА на месте, подсказка поверх с
                // AnimatedOpacity. БЕЗ AnimatedSwitcher — при стирании чата
                // и при первом сообщении не мигает (не было двойного fade
                // «лента гаснет + подсказка вспыхивает»).
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListView.builder(
                      controller: _scrollCtrl,
                      // reverse:true — индекс 0 это НИЗ чата: открытие сразу
                      // показывает последние сообщения, никаких прыжков.
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      itemCount: _messages.length + (_busy ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (_busy && i == 0) {
                          // «Печатает…» — самый нижний элемент, прямо у поля.
                          // AnimatedOpacity: при ответе индикатор плавно гаснет,
                          // а не выпадает резко (см. _typingFade в _send).
                          return AnimatedOpacity(
                            opacity: _typingFade ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, child) => Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: 0.7 + 0.3 * t,
                                  child: child,
                                ),
                              ),
                              child: _TypingIndicator(animation: _dotsCtrl),
                            ),
                          );
                        }
                        // Индекс в исходном массиве (0 = последнее сообщение).
                        final mi = _busy
                            ? _messages.length - i
                            : _messages.length - 1 - i;
                        final m = _messages[mi];
                        // Сосед ВЫШЕ в ленте (следующий по истории).
                        final above = mi + 1 < _messages.length
                            ? _messages[mi + 1]
                            : null;
                        // Анимация входа — ТОЛЬКО у сообщений, добавленных
                        // ПОСЛЕ открытия чата (последние 3 из них). Сообщения
                        // истории при открытии НЕ анимируются: лист уже выезжает,
                        // и пузыри не «прыгают» поверх. Также не анимируются
                        // старые пузыри при скролле большого чата.
                        final isNew = mi >= _openedCount;
                        final animate = isNew && mi >= _messages.length - 3;
                        return RepaintBoundary(
                          key: ValueKey('msg_layer_$mi'),
                          child: _MessageBubble(
                            key: ValueKey('msg_$mi'),
                            message: m,
                            firstInGroup:
                                above == null || above.isUser != m.isUser,
                            animate: animate,
                            liked: _liked.contains(_msgKey(m)),
                            pinned: _isPinned(m),
                            onToggleLike: () => _toggleLike(m),
                            onCopy: () => _copyMessage(m),
                            // Зажать аватарку Ады — закрепить/открепить (до 10).
                            onLongPress: m.isUser ? null : () => _togglePin(m),
                            onTogglePin: m.isUser ? null : () => _togglePin(m),
                            onCycleAvatar: _cycleAvatar,
                          ),
                        );
                      },
                    ),
                    // Подсказка пустого чата: плавно появляется, когда
                    // сообщений нет, и гаснет при первом сообщении.
                    AnimatedOpacity(
                      opacity: _messages.isEmpty && !_busy ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !(_messages.isEmpty && !_busy),
                        child: const _EmptyChatPlaceholder(),
                      ),
                    ),
                  ],
                ),
                  ),
                ),
              ),
            ),
            // Плашка «ИИ на курорте» (с кодом ошибки для диагностики).
            _AnimatedErrorPlaque(
              visible: _error,
              errorMsg: _errorMsg,
              onRetry: _retryLast,
            ),
            // Быстрые действия: чип заполняет поле ввода шаблоном — дальше
            // локальный парсер выполнит команду мгновенно, без сети.
            _QuickChips(
              // Значок веб-поиска — первый элемент списка, листается
              // вместе с таблетками (не приклеен столбом слева).
              leading: _buildWebSearchToggle(context, theme),
              onTap: (template) {
                _inputCtrl.text = template;
                _inputCtrl.selection = TextSelection.collapsed(
                  offset: _inputCtrl.text.length,
                );
                _inputFocus.requestFocus();
              },
            ),
            // Подсказка про лимит Ады.
            if (_quotaLeft > 0 && _quotaLeft <= 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: Color(0xFFB06AB3),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ClipRect(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            final t = Curves.easeOutCubic.transform(
                              animation.value,
                            );
                            return FadeTransition(
                              opacity: animation,
                              child: Transform.translate(
                                offset: Offset(0, 10 * (1 - t)),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            Translations.t(
                              'adaQuota',
                              context,
                              'Ada: N free left today',
                            ).replaceFirst('N', '$_quotaLeft'),
                            key: ValueKey('quota_$_quotaLeft'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // «Отменить последнее действие» — появляется/исчезает плавно
            // после того, как Ада что-то создала или удалила.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  alignment: AlignmentDirectional.topCenter,
                  child: child,
                ),
              ),
              child: (AiGuideService.lastAction == null || _busy)
                  ? const SizedBox.shrink(key: ValueKey('undo_none'))
                  : Padding(
                      key: const ValueKey('undo_chip'),
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          avatar: const Icon(Icons.undo, size: 16),
                          label: Text(
                            '${Translations.t('aiUndo', context, 'Undo')}: '
                            '${AiGuideService.lastAction!.label}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _busy ? null : _undoLast,
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: cs.primary.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ),
            ),
            // Поле ввода.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      // Плавное выделение поля при фокусе: обводка и цвет
                      // анимируются (AnimatedBuilder на FocusNode → AnimatedContainer).
                      child: AnimatedBuilder(
                        animation: _inputFocus,
                        builder: (context, child) => AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _inputFocus.hasFocus
                                  ? cs.primary.withValues(alpha: 0.65)
                                  : cs.outlineVariant.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: child,
                        ),
                        child: Stack(
                          children: [
                            // Предпросмотр markdown убран: прозрачный
                            // TextField + RichText давали «разъехавшиеся
                            // буквы» (шрифт Avenir Next недоступен на Android
                            // и фолбэк рендерил слои со сдвигом). Теперь
                            // текст обычный, видимый, без артефактов.
                            // Настоящее поле СВЕРХУ: текст прозрачный (его
                            // рисует предпросмотр), но каретка, выделение и
                            // клавиатура работают как обычно.
                            TextField(
                              magnifierConfiguration:
                                  TextMagnifierConfiguration.disabled,
                              controller: _inputCtrl,
                              focusNode: _inputFocus,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 13000,
                              // Отключаем автоподсказки/автокоррекцию клавиатуры:
                              // Gboard/MIUI добавляет свой автопробел после
                              // выбранного слова — отсюда «пробел в конце».
                              enableSuggestions: false,
                              autocorrect: false,
                              // Меню при зажатии: только Копировать/Вставить/
                              // Вырезать/Курсив — без «Поделиться», «Спросить
                              // Copilot» и лишних пунктов системного меню.
                              contextMenuBuilder: minimalContextMenuBuilder,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.4,
                                color: cs.onSurface,
                              ),
                              cursorColor: cs.primary,
                              decoration: InputDecoration(
                                hintText: Translations.t(
                                  'aiGuideHint',
                                  context,
                                  'Ask me…',
                                ),
                                counterText: '',
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SendButton(busy: _busy, onTap: () => _send()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подсказка в пустом чате: ПО ЦЕНТРУ, две строки жирным, с переводом.
class _EmptyChatPlaceholder extends StatelessWidget {
  const _EmptyChatPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Text(
          Translations.t('adaEmptyChat', context),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            height: 1.35,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Пузырь сообщения с плавным появлением (fade + подъём) при добавлении.
class _MessageBubble extends StatelessWidget {
  final AiMessage message;
  final bool firstInGroup;
  final bool animate;
  final bool liked;
  final bool pinned;
  final VoidCallback? onLongPress;
  final VoidCallback? onTogglePin;
  final VoidCallback? onToggleLike;
  final VoidCallback? onCopy;
  final VoidCallback? onCycleAvatar;
  const _MessageBubble({
    super.key,
    required this.message,
    required this.firstInGroup,
    this.animate = true,
    this.liked = false,
    this.pinned = false,
    this.onLongPress,
    this.onTogglePin,
    this.onToggleLike,
    this.onCopy,
    this.onCycleAvatar,
  });

  /// Сообщение-награда Ады (стрики/задачи) — особая «подарочная» плашка.
  bool get _isReward =>
      message.text.startsWith('🎖️') ||
      message.text.startsWith('🏆') ||
      message.text.startsWith('🎁');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final Widget bubble = Padding(
      padding: EdgeInsets.only(top: firstInGroup ? 10 : 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            // Тап по сердечку Ады — сменить значок; ЗАЖАТЬ — закрепить вверх.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: cycleAdaAvatar,
              onLongPress: onLongPress,
              child: const _AdaAvatar(size: 18),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: _isReward
                      ? BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isUser ? 18 : 6),
                            bottomRight: Radius.circular(isUser ? 6 : 18),
                          ),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFF6D8), Color(0xFFFFE1B2)],
                          ),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        )
                      : BoxDecoration(
                          color: isUser
                              ? cs.primaryContainer
                              : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(isUser ? 18 : 6),
                            bottomRight: Radius.circular(isUser ? 6 : 18),
                          ),
                        ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isReward) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 6),
                          child: Icon(
                            Icons.card_giftcard,
                            size: 15,
                            color: const Color(0xFFB0712A),
                          ),
                        ),
                      ],
                      Flexible(
                        child: SelectableText.rich(
                          parseMarkdownSpans(
                            message.text,
                            TextStyle(
                              color: _isReward
                                  ? const Color(0xFF7A4B00)
                                  : (isUser
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface),
                              fontSize: 14.5,
                              height: 1.3,
                            ),
                          ),
                          // Красивые ручки выделения + меню Копировать/
                          // Поделиться, без системной лупы (приближение
                          // текста — бесит). Долгое нажатие больше НИЧЕМ
                          // не перехватывается — выделение и тулбар с
                          // кнопкой «Копировать» работают всегда.
                          selectionControls: BeautifulSelectionControls(),
                          contextMenuBuilder: buildChatSelectionMenu,
                          magnifierConfiguration:
                              TextMagnifierConfiguration.disabled,
                        ),
                      ),
                    ],
                  ),
                ),
                // Действия под сообщением Ады: сердечко, скопировать, булавка.
                if (!isUser)
                  _BubbleActions(
                    liked: liked,
                    pinned: pinned,
                    onToggleLike: onToggleLike,
                    onCopy: onCopy,
                    onTogglePin: onTogglePin,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      // Анимируется один раз при первом появлении пузыря; у старых
      // сообщений анимация отключена (animate: false) — скролл большого
      // чата не дёргается. Только fade + лёгкий scale — БЕЗ подъёма:
      // в reverse-ленте новое сообщение вставляется снизу и список сам
      // сдвигается вниз; одновременный подъём пузыря давал «дёрганое»
      // двойное движение на слабом устройстве.
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final e = Curves.easeOutCubic.transform(t);
        return Opacity(
          opacity: e,
          child: Transform.scale(scale: 0.97 + 0.03 * e, child: child),
        );
      },
      child: bubble,
    );
  }
}

/// Ряд мелких действий под сообщением Ады: сердечко (лайк), скопировать,
/// закрепить. Сердечко плавно меняет значок пустое ↔ залитое.
class _BubbleActions extends StatelessWidget {
  final bool liked;
  final bool pinned;
  final VoidCallback? onToggleLike;
  final VoidCallback? onCopy;
  final VoidCallback? onTogglePin;
  const _BubbleActions({
    this.liked = false,
    this.pinned = false,
    this.onToggleLike,
    this.onCopy,
    this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant.withValues(alpha: 0.75);
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Сердечко анимируется плавно: пустое ↔ залитое с лёгким «попом».
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _ActionIcon(
              key: ValueKey('like_$liked'),
              icon: liked ? Icons.favorite : Icons.favorite_border,
              size: 14,
              color: liked ? Colors.pink.shade400 : muted,
              onTap: onToggleLike,
              tooltip: Translations.t('like', context, 'Like'),
            ),
          ),
          const SizedBox(width: 2),
          _ActionIcon(
            icon: Icons.copy_outlined,
            size: 13,
            color: muted,
            onTap: onCopy,
            tooltip: Translations.t('copy', context, 'Copy'),
          ),
          const SizedBox(width: 2),
          // Булавка меняет вид: пустая ↔ залитая (когда закреплена).
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _ActionIcon(
              key: ValueKey('pin_$pinned'),
              icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 13,
              color: pinned ? cs.primary : muted,
              onTap: onTogglePin,
              tooltip: pinned
                  ? Translations.t('unpinMsg', context, 'Unpin')
                  : Translations.t('pinMsg', context, 'Pin'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;
  const _ActionIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final Animation<double> animation;
  const _TypingIndicator({required this.animation});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const _AdaAvatar(size: 18),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // «Сочиняю» — плавно появляется над точками и мягко
                // пульсирует в такт тиканью троеточия.
                AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final pulse =
                        0.7 + 0.3 * ((animation.value * 2) % 1).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: pulse,
                      child: Text(
                        Translations.t('aiComposing', context),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) {
                        final t = ((animation.value * 3 - i) % 3).clamp(
                          0.0,
                          1.0,
                        );
                        final scale = 0.6 + 0.6 * t;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Transform.scale(
                            scale: scale,
                            child: Icon(
                              Icons.circle,
                              size: 7,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Плавная плашка «ИИ на курорте, подожди немного» с кнопкой повтора.
class _AnimatedErrorPlaque extends StatelessWidget {
  final bool visible;
  final String errorMsg;
  final VoidCallback onRetry;
  const _AnimatedErrorPlaque({
    required this.visible,
    this.errorMsg = '',
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, child: child),
      ),
      child: visible
          ? Padding(
              key: const ValueKey('ai_error_plaque'),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3D6), Color(0xFFFFE0B2)],
                  ),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.beach_access,
                      color: Color(0xFFE68A00),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Translations.t(
                              'aiResort',
                              context,
                              'AI is on vacation, wait a bit',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF8A5A00),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (errorMsg.isNotEmpty)
                            Text(
                              errorMsg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFFB0712A),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: Color(0xFFE68A00),
                        size: 20,
                      ),
                      tooltip: Translations.t('retry', context, 'Retry'),
                      onPressed: onRetry,
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('ai_error_hidden')),
    );
  }
}

/// Быстрые действия Ады: мелкие чипы, которые подставляют шаблон команды
/// в поле ввода (локальный парсер создаст привычку/задачу/будильник и т.д.
/// мгновенно и без сети).
class _QuickChips extends StatelessWidget {
  final ValueChanged<String> onTap;

  /// Необязательный элемент в начале списка (например, значок веб-поиска).
  /// Листается горизонтально вместе с таблетками, а не приклеен столбом.
  final Widget? leading;
  const _QuickChips({required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Шаблоны БЕЗ пробела в конце: раньше trailing-пробел вставлялся
    // в поле ввода и выглядел как «странный пробел в конце сообщения».
    final chips = <(String, String)>[
      (Translations.t('aiChipHabit', context, 'Привычка'), 'создай привычку'),
      (Translations.t('aiChipTask', context, 'Задача'), 'создай задачу'),
      (
        Translations.t('aiChipAlarm', context, 'Будильник'),
        'поставь будильник на',
      ),
      (
        Translations.t('aiChipRC', context, 'Проверка'),
        'создай проверку реальности',
      ),
      (Translations.t('aiChipMeal', context, 'Еда'), 'запиши приём пищи'),
    ];
    // Первый элемент — значок веб-поиска (если задан), дальше таблетки.
    final hasLeading = leading != null;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: hasLeading ? chips.length + 1 : chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          if (hasLeading && i == 0) return leading!;
          final (label, template) = hasLeading ? chips[i - 1] : chips[i];
          return GestureDetector(
            onTap: () => onTap(template),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onTap;
  const _SendButton({required this.busy, required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  // Пока идёт ответ — сплеш-спиннер плавно вращается.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _SendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _spin.repeat();
    } else if (!widget.busy && oldWidget.busy) {
      _spin.stop();
      _spin.reset();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onTap: widget.busy
          ? null
          : () {
              Haptics.light();
              widget.onTap();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary,
              Color.lerp(cs.primary, cs.secondary, 0.6) ?? cs.secondary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
              spreadRadius: 1,
            ),
          ],
        ),
        // Плавный переход иконок: стрелка ↔ сплеш-спиннер.
        // Без RotationTransition (на слабом GPU поворот при каждой смене
        // «дёргал» переход) — мягкий scale + fade, без overshoot.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: Tween<double>(begin: 0.82, end: 1).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: widget.busy
              ? AnimatedBuilder(
                  key: const ValueKey('busy_splash'),
                  animation: _spin,
                  builder: (context, _) => Transform.rotate(
                    angle: _spin.value * 2 * 3.14159,
                    child: Icon(Icons.autorenew, color: cs.onPrimary, size: 26),
                  ),
                )
              : Icon(
                  Icons.arrow_upward_rounded,
                  key: const ValueKey('send_arrow'),
                  color: cs.onPrimary,
                  size: 24,
                ),
        ),
      ),
    );
  }
}

/// Панель закреплённых сообщений Ады: плашки с булавкой и текстом,
/// тап на крестик — открепить. Появляются/исчезают плавно.
class _PinnedBar extends StatelessWidget {
  final List<AiMessage> pinned;
  final ValueChanged<AiMessage> onUnpin;
  const _PinnedBar({super.key, required this.pinned, required this.onUnpin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxHeight: 132),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: pinned.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final m = pinned[i];
          return AnimatedSwitcher(
            // Плавное появление/исчезание: выезжает сверху и занимает
            // своё место, при откреплении мягко «уезжает» вверх и
            // сжимается, освобождая строку.
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                sizeFactor: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
            ),
            child: Container(
              key: ValueKey('pin_${m.text.hashCode}_${m.isUser}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Icon(Icons.push_pin, size: 13, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onUnpin(m),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Плавающее мини-окошко Ады — компактный ЧАТ: шапка с аватаркой, лента
/// последних сообщений и поле ввода. Перемещается пальцем (за шапку),
/// живёт поверх всех экранов и не исчезает при выходе из приложения
/// (режим хранится в prefs). Тап по кнопке «развернуть» плавно открывает
/// полный чат. Скрывается на PIN-локскрине (приватность «недавних»).
class AiFloatingBubble extends StatefulWidget {
  /// Развернуть в полный чат (кнопка со стрелками / тап по телу окошка).
  final VoidCallback onOpen;

  const AiFloatingBubble({super.key, required this.onOpen});

  @override
  State<AiFloatingBubble> createState() => _AiFloatingBubbleState();
}

class _AiFloatingBubbleState extends State<AiFloatingBubble>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _historyKey = 'ai_chat_history';
  static const double _expandedHeight = 240;
  static const double _collapsedSize = 64;

  /// Ширина развёрнутого окошка: компактная, ближе к квадрату.
  static double _windowWidth(double screenWidth) =>
      (screenWidth * 0.58).clamp(200.0, 250.0);

  Offset _pos = Offset.zero;
  // Позиция окошка — ValueNotifier: драг двигает только Positioned
  // (готовый слой), НЕ перестраивая весь чат на каждый пиксель.
  final ValueNotifier<Offset> _posNotifier = ValueNotifier<Offset>(Offset.zero);
  final List<AiMessage> _messages = [];
  bool _busy = false;
  bool _typingFade = false;
  // Сколько сообщений было при открытии окошка: только новые проигрывают
  // анимацию входа, иначе при разворачивании вся история «вспыхивала».
  int _openedCount = 0;
  // Свёрнуто ли окошко в мелкий кружок-аватарку (тап по названию/аватарке).
  bool _collapsed = false;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  // Плавное появление/исчезание окошка при переключении режима «в окне».
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: aiFloating.value ? 1.0 : 0.0,
  );
  // Троеточие «Ада печатает…» в мини-окошке (repeat пока busy).
  late final AnimationController _dotsCtrlMini = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadHistory();
    aiFloating.addListener(_onFloatChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pos == Offset.zero) {
      final size = MediaQuery.of(context).size;
      try {
        _pos = Offset(
          (globalPrefs.getDouble('ai_bubble_fx') ?? 0.58) * size.width,
          (globalPrefs.getDouble('ai_bubble_fy') ?? 0.65) * size.height,
        );
      } catch (_) {
        _pos = Offset(size.width * 0.58, size.height * 0.65);
      }
      _clampPos(size);
      _posNotifier.value = _pos;
    }
  }

  void _clampPos(Size screen) {
    final w = _windowWidth(screen.width);
    _pos = Offset(
      _pos.dx.clamp(8.0, screen.width - w - 8.0),
      _pos.dy.clamp(8.0, screen.height - _expandedHeight - 8.0),
    );
  }

  void _onFloatChanged() {
    _ctrl.animateTo(aiFloating.value ? 1.0 : 0.0, curve: Curves.easeOutCubic);
  }

  /// Загружаем ПОЛНУЮ историю диалога — единый контекст с полным чатом.
  /// Раньше здесь брался «хвост» из 20 сообщений и сохранялся обратно —
  /// из-за этого общий чат обрезался и контекст расходился.
  Future<void> _loadHistory() async {
    try {
      final raw = await JsonFile.read(_historyKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        final loaded = list
            .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _messages
              ..clear()
              ..addAll(loaded);
            _openedCount = _messages.length;
          });
          _scrollToBottom(animate: false);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      var toSave = _messages;
      if (toSave.length > 1000) {
        toSave = toSave.sublist(toSave.length - 1000);
      }
      await JsonFile.write(
        _historyKey,
        jsonEncode(toSave.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _scrollToBottom({bool animate = true}) {
    // Лента с reverse:true — индекс 0 это низ; открытие сразу показывает
    // последние сообщения без ретрай-цикла jumpTo (тот дёргал layout).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final pos = _scrollCtrl.position;
      if (animate) {
        if (pos.pixels > 4) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (pos.pixels > 0) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  /// Отправка прямо из компактного окошка. Язык — как у пользователя
  /// (раньше был захардкожен 'en', из-за чего Ада отвечала по-английски).
  Future<void> _send() async {
    final message = _inputCtrl.text.trim();
    if (message.isEmpty || _busy) return;
    _inputCtrl.clear();
    setState(() {
      _messages.add(AiMessage(isUser: true, text: message));
      _busy = true;
      _typingFade = false;
    });
    _dotsCtrlMini.repeat();
    _saveHistory();
    _scrollToBottom();
    try {
      final lang = await SettingsService.resolveLanguageCode();
      final answer = await AiGuideService.send(
        userText: message,
        history: _messages.take(_messages.length - 1).toList(),
        languageCode: lang,
      );
      if (!mounted) return;
      // Эстафета «печатает…» → ответ: точки плавно гаснут, потом ответ
      // всплывает — как в полном чате, без резкого щелчка.
      _dotsCtrlMini.stop();
      setState(() => _typingFade = true);
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() {
        _messages.add(AiMessage(isUser: false, text: answer));
        _busy = false;
        _typingFade = false;
      });
      _saveHistory();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _typingFade = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Окошко не скрываем при переходе в фон/возврате.
  }

  @override
  void dispose() {
    aiFloating.removeListener(_onFloatChanged);
    _ctrl.dispose();
    _dotsCtrlMini.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _posNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _drag(Offset delta, Size screen) {
    final next = _pos + delta;
    final w = _windowWidth(screen.width);
    _pos = Offset(
      next.dx.clamp(8.0, screen.width - w - 8.0),
      next.dy.clamp(8.0, screen.height - _expandedHeight - 8.0),
    );
    _posNotifier.value = _pos;
  }

  void _savePos(Size screen) {
    globalPrefs.setDouble('ai_bubble_fx', _pos.dx / screen.width);
    globalPrefs.setDouble('ai_bubble_fy', _pos.dy / screen.height);
  }

  /// Объёмная «пузырьковая» оболочка: градиентный корпус, глянцевый блик,
  /// цветное свечение + глубокая тень — выглядит как плавающий пузырь.
  BoxDecoration _bubbleDecoration(ColorScheme cs, bool collapsed) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(collapsed ? 32 : 24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cs.surfaceContainerHighest.withValues(alpha: 0.99),
          cs.surfaceContainerLowest.withValues(alpha: 0.99),
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.4),
        width: 1.2,
      ),
      boxShadow: [
        // Цветное свечение — «объём» пузыря.
        BoxShadow(
          color: cs.primary.withValues(alpha: collapsed ? 0.4 : 0.25),
          blurRadius: collapsed ? 14 : 22,
          offset: const Offset(0, 4),
        ),
        // Убираем тёмный фон с незакруглёнными углами: прозрачная
        // поверх градиентного пузыря, остаётся только драг-хендл.
      ],
    );
  }

  /// Глянцевый блик сверху (стеклянная «выпуклость»).
  Widget _glassHighlight(ColorScheme cs, bool collapsed) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(collapsed ? 32 : 24),
            // Убираем тёмный фон с незакруглёнными углами: прозрачная
            // поверх градиентного пузыря, остаётся только драг-хендл.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.32),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.45],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.of(context).size;
    final w = _windowWidth(screen.width);
    return ValueListenableBuilder<bool>(
      valueListenable: aiLockScreenVisible,
      builder: (context, locked, _) {
        if (locked) return const SizedBox.shrink();
        return AnimatedBuilder(
          animation: _ctrl,
          // Тяжёлый контент (лента сообщений, поле ввода) строится ОДИН раз
          // и живёт как готовый child — при анимации появления/закрытия
          // пересоздаётся только Opacity/Scale (готовый слой двигается),
          // а не весь чат на каждый кадр. Раньше на Redmi Note 12 каждый
          // тик 260-мс анимации перестраивал весь ListView — тормозило.
          child: AnimatedContainer(
            // easeOutBack давал overshoot — окошко «перелетало» размер
            // и дёргалось при разворачивании. Плавная easeOutCubic.
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            width: _collapsed ? _collapsedSize : w,
            height: _collapsed ? _collapsedSize : _expandedHeight,
            decoration: _bubbleDecoration(cs, _collapsed),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    // Меньше «сжатости» при разворачивании: чат больше не
                    // вылезает из «сжатой» 0.9-копии, а мягко проявляется.
                    child: ScaleTransition(
                      scale: Tween(begin: 0.965, end: 1.0).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _collapsed
                      ? _buildCollapsedCircle(cs, key: const ValueKey('circle'))
                      : _buildExpanded(
                          cs,
                          screen,
                          key: const ValueKey('expanded'),
                        ),
                ),
                // Блик поверх любого состояния.
                _glassHighlight(cs, _collapsed),
              ],
            ),
          ),
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_ctrl.value);
            if (t <= 0.001) return const SizedBox.shrink();
            return ValueListenableBuilder<Offset>(
              valueListenable: _posNotifier,
              builder: (context, pos, _) => Positioned(
                left: pos.dx,
                top: pos.dy,
                child: IgnorePointer(
                  ignoring: !aiFloating.value || t < 1.0,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * t,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Мелкий кружок-аватарка (свёрнутое состояние). Тап — развернуть.
  Widget _buildCollapsedCircle(ColorScheme cs, {Key? key}) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _collapsed = false),
      onPanUpdate: (d) => _drag(d.delta, MediaQuery.of(context).size),
      onPanEnd: (_) => _savePos(MediaQuery.of(context).size),
      child: Center(
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primaryContainer, cs.primary.withValues(alpha: 0.85)],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Center(child: _AdaAvatar(size: 36)),
        ),
      ),
    );
  }

  /// Развёрнутое состояние: шапка (перетаскивание, скрутить, развернуть,
  /// закрыть) + лента сообщений + поле ввода.
  Widget _buildExpanded(ColorScheme cs, Size screen, {Key? key}) {
    return Column(
      key: key,
      children: [
        // Шапка — перетаскивание + скрутить в кружок + развернуть + закрыть.
        GestureDetector(
          onPanUpdate: (d) => _drag(d.delta, screen),
          onPanEnd: (_) => _savePos(screen),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            // Прозрачная шапка поверх градиентного пузыря — без «квадратной»
            // заливки, остаётся только драг-хендл.
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _collapsed = true),
                  child: _AdaAvatar(size: 26),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _collapsed = true),
                    child: Text(
                      Translations.t('aiGuide', context, 'AI guide'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                // Развернуть в полный чат — плавно.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.open_in_full_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                // Закрыть окошко (выключить режим).
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    aiFloating.value = false;
                    globalPrefs.setBool('ai_floating', false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Лента последних сообщений. Тап по ней — плавно открыть полный чат.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        Translations.t(
                          'aiOverlayEmpty',
                          context,
                          'Chat with Ada',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_busy && i == 0) {
                        // «Печатает…»: точки гаснут плавно перед ответом
                        // (эстафета как в полном чате — _typingFade).
                        return AnimatedOpacity(
                          opacity: _typingFade ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: _TypingDotsMini(animation: _dotsCtrlMini),
                        );
                      }
                      final mi = _busy
                          ? _messages.length - i
                          : _messages.length - 1 - i;
                      return _MiniBubble(
                        message: _messages[mi],
                        colorScheme: cs,
                        avatar: 0,
                        // Анимация входа — только у новых сообщений
                        // (добавленных после открытия окошка).
                        animate: mi >= _openedCount,
                      );
                    },
                  ),
          ),
        ),
        const Divider(height: 1),
        // Поле ввода + отправка.
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          // Прозрачное поле ввода поверх градиентного пузыря — без «квадратной»
          // заливки, остаётся только драг-хендл.
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Предпросмотр markdown убран (тот же артефакт
                    // «разъехавшихся букв», что и в основном чате).
                    // Текст обычный и видимый.
                    TextField(
                      magnifierConfiguration:
                          TextMagnifierConfiguration.disabled,
                      contextMenuBuilder: minimalContextMenuBuilder,
                      controller: _inputCtrl,
                      minLines: 1,
                      maxLines: 2,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      // Автопробел клавиатуры — убираем подсказки.
                      enableSuggestions: false,
                      autocorrect: false,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: cs.onSurface,
                      ),
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        hintText: Translations.t(
                          'aiInputHint',
                          context,
                          'Message…',
                        ),
                        hintStyle: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: cs.surfaceContainerHigh.withValues(
                          alpha: 0.7,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 30,
                        height: 30,
                        child: Padding(
                          padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      )
                    : IconButton.filled(
                        key: const ValueKey('send'),
                        onPressed: () {
                          Haptics.light();
                          _send();
                        },
                        icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                        style: IconButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          minimumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Плавное «троеточие» Ада печатает… — три точки, прыгающие по очереди.
/// [animation] — внешний AnimationController (останавливается в _send),
/// чтобы точки не тикали, когда ответ уже пришёл.
class _TypingDotsMini extends StatefulWidget {
  final Animation<double> animation;
  const _TypingDotsMini({required this.animation});

  @override
  State<_TypingDotsMini> createState() => _TypingDotsMiniState();
}

class _TypingDotsMiniState extends State<_TypingDotsMini> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final t = widget.animation.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                    // Волна: каждая точка прыгает со своим сдвигом.
                    transform: Matrix4.translationValues(
                      0,
                      -4 * (0.5 - 0.5 * math.cos((t * 2 * math.pi) - i * 0.9)),
                      0,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Компактный пузырь сообщения в мини-окошке. Появление — плавное:
/// сообщение мягко всплывает (fade + slide вверх), как в полном чате.
/// Только у НОВЫХ сообщений ([animate] true) — старые при открытии
/// окошка не «прыгают» поверх разворачивания.
class _MiniBubble extends StatelessWidget {
  final AiMessage message;
  final int avatar;
  final ColorScheme colorScheme;
  final bool animate;
  const _MiniBubble({
    required this.message,
    required this.avatar,
    required this.colorScheme,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final cs = colorScheme;
    final Widget bubble = Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.55,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 14 : 12),
            topRight: Radius.circular(isUser ? 12 : 14),
            bottomLeft: const Radius.circular(14),
            bottomRight: const Radius.circular(14),
          ),
        ),
        child: buildMarkdownText(
          message.text,
          TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: isUser ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      child: bubble,
      builder: (context, value, child) {
        final e = Curves.easeOutCubic.transform(value);
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - e)),
            child: child,
          ),
        );
      },
    );
  }
}
