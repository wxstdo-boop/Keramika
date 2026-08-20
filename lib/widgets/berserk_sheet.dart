import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../services/ai_guide_service.dart';
import '../services/prefs.dart';
import '../services/settings_service.dart';
import '../utils/markdown_text.dart';

/// Открывает плашку «МАКСИМАЛЬНЫЙ АПГРЕЙД УРОВНЯ BERSERK».
///
/// Режим открывается долгим зажатием «плюса» (FAB) на любом экране.
/// Содержимое подстраивается под выбранную тему, но сохраняет кровавый
/// акцент. В начале — «Практика от AGI»: шаги на сегодня, которые
/// генерирует встроенный ИИ раз в день (кэш в prefs, фолбэк оффлайн).
Future<void> showBerserkSheet(BuildContext context) async {
  // Зажатие «плюса» работает ТОЛЬКО когда режим включён в настройках.
  if (!SettingsService.berserkEnabled.value) return;
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final blood = const Color(0xFFB51F32);
  final bloodSoft = isDark ? const Color(0xFFFF5A6B) : const Color(0xFFC41E33);

  // Полная адаптация под тему: светлые темы получают тёплый светлый фон
  // с тёмным текстом и кровавыми акцентами; тёмные — фон ТЕМЫ (surface)
  // с лёгким кровавым оттенком, а не сплошной красный: бордово-красный
  // остаётся акцентом (рамка, чипы, заголовок), а не заливает весь экран.
  // Полная адаптация под тему: и тёмные, и светлые темы получают фон из
  // surfaceContainerLow самой темы с лёгким кровавым оттенком — никаких
  // захардкоженных цветов. Кровь остаётся только акцентом (рамка, чипы,
  // заголовок), а не заливает экран.
  final bgBlood = Color.lerp(cs.primary, blood, isDark ? 0.55 : 0.5)!;
  final base = cs.surfaceContainerLow;
  final titleColor = isDark
      ? Colors.white
      : Color.lerp(blood, cs.onSurface, 0.35)!;
  final bodyColor = isDark
      ? Colors.white.withValues(alpha: 0.9)
      : cs.onSurface.withValues(alpha: 0.82);
  final chipBg = isDark
      ? Colors.black.withValues(alpha: 0.38)
      : blood.withValues(alpha: 0.10);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.35),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // Лёгкая плавная кривая вместо «пружины» по умолчанию: на слабых
    // телефонах пружинный вход/выход проседает по кадрам и выглядит
    // «дёрганым». Кубическая кривая — дешёвая и очень плавная.
    sheetAnimationStyle: AnimationStyle(
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 300),
      reverseCurve: Curves.easeInCubic,
      reverseDuration: const Duration(milliseconds: 240),
    ),
    builder: (context) {
      return Container(
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base,
              Color.lerp(base, bgBlood, isDark ? 0.35 : 0.22)!,
              Color.lerp(base, bgBlood, isDark ? 0.6 : 0.4)!,
            ],
          ),
          border: Border.all(
            color: bloodSoft.withValues(alpha: isDark ? 0.7 : 0.5),
            width: 1.4,
          ),
          // blurRadius держим малым: большая тень на весь лист создаёт
          // дорогой saveLayer и на слабых телефонах тормозит открытие/закрытие.
          boxShadow: [
            BoxShadow(
              color: blood.withValues(alpha: isDark ? 0.35 : 0.18),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        // Никаких дополнительных анимаций поверх системного входа шторки:
        // Opacity-обёртка над всем скроллом создавала saveLayer и на слабых
        // телефонах «тормозила» и открытие, и прокрутку внутри. Шторка сама
        // плавно выезжает — этого достаточно. RepaintBoundary + отдача
        // сжатия при нажатии внутри окна.
        child: SafeArea(
          top: false,
          child: RepaintBoundary(
            child: _SheetPress(
              child: _BerserkContent(
                isDark: isDark,
                titleColor: titleColor,
                bodyColor: bodyColor,
                bloodSoft: bloodSoft,
                chipBg: chipBg,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Содержимое плашки. Stateful, потому что «Практика от AGI» генерируется
/// встроенным ИИ асинхронно: сразу показывается проверенный оффлайн-набор,
/// затем, когда ИИ ответит, — плавная смена на свежие шаги (без «загрузки»).
class _BerserkContent extends StatefulWidget {
  final bool isDark;
  final Color titleColor;
  final Color bodyColor;
  final Color bloodSoft;
  final Color chipBg;

  const _BerserkContent({
    required this.isDark,
    required this.titleColor,
    required this.bodyColor,
    required this.bloodSoft,
    required this.chipBg,
  });

  @override
  State<_BerserkContent> createState() => _BerserkContentState();
}

class _BerserkContentState extends State<_BerserkContent> {
  // Сразу показываем оффлайн-шаги — никакой «загрузки»: текст виден
  // мгновенно и плавно появляется, а если встроенный ИИ успеет дать
  // свежие шаги за день — они так же плавно заменят фолбэк.
  List<String> _steps = _fallbackSteps();
  // Крутится ли кнопка обновления (идёт генерация свежих шагов ИИ).
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  static String _dateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _practicePrompt() =>
      'Ты — встроенный ИИ приложения Keramika. Сгенерируй 3 подробных практических шага на сегодня для режима личной силы и фокуса. Каждый шаг — конкретное действие из 1–2 предложений, с деталями: когда, что и как сделать. Без нумерации и заголовков. Ответь только самими тремя шагами, каждый с новой строки.';

  /// Шаги на сегодня: сначала кэш (один вызов ИИ в день), затем — генерация
  /// встроенным ИИ через цепочку Ады. Пока ИИ думает, на экране УЖЕ
  /// показан проверенный оффлайн-набор — при появлении свежих шагов они
  /// плавно заменяют его, без пульсации и «загрузки».
  Future<void> _loadSteps() async {
    final key = 'berserk_agi_${_dateKey()}';
    final cached = globalPrefs.getStringList(key);
    if (cached != null && cached.isNotEmpty) {
      if (mounted) setState(() => _steps = cached);
      return;
    }
    final steps = await _generateSteps();
    if (steps != null && mounted) setState(() => _steps = steps);
  }

  /// Вызывает встроенный ИИ и возвращает свежие шаги (или null — ИИ
  /// недоступен, остаёмся на текущем наборе). Успех пишется в дневной кэш.
  Future<List<String>?> _generateSteps() async {
    try {
      final lang = Translations.languageOf(context);
      final raw = await AiGuideService.send(
        userText: _practicePrompt(),
        history: const [],
        languageCode: lang,
      );
      final steps = _parseSteps(raw);
      if (steps.isNotEmpty) {
        globalPrefs.setStringList('berserk_agi_${_dateKey()}', steps);
        return steps;
      }
    } catch (_) {
      // ИИ недоступен — остаёмся на проверенном оффлайн-наборе.
    }
    return null;
  }

  /// Кнопка «обновить»: генерирует СВЕЖИЕ советы ИИ прямо сейчас (в обход
  /// дневного кэша) и плавно подменяет шаги на экране.
  Future<void> _refreshSteps() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final steps = await _generateSteps();
    if (!mounted) return;
    setState(() {
      if (steps != null) _steps = steps;
      _refreshing = false;
    });
  }

  /// Разбирает ответ модели: строки → до трёх аккуратных шагов.
  static List<String> _parseSteps(String raw) {
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.replaceFirst(RegExp(r'^[-•*]\s*'), ''))
        .map((l) => l.replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.take(3).toList();
  }

  /// Оффлайн-фолбэк: детерминированный набор от даты (как раньше).
  static List<String> _fallbackSteps() {
    final now = DateTime.now();
    final day = now.difference(DateTime(now.year)).inDays;
    const pool = <List<String>>[
      [
        'Встань на 15 минут раньше обычного, умойся прохладной водой и первые 5 минут не бери телефон: просто дыши и наметь три главных дела на день.',
        'Выбери задачу, которую откладываешь дольше всего, и сделай её первым делом — до проверки мессенджеров и новостей, чтобы страх потерять свою силу.',
        'Вечером, перед сном, запиши три строки: что получилось, что не получилось и один конкретный шаг, который сделаешь завтра лучше.',
      ],
      [
        'Найди одну вещь, которая крадёт твоё время, и скажи «нет» одним спокойным предложением — без оправданий, вины и длинных объяснений.',
        'Выдели 10 минут движения: быстрая прогулка, растяжка или зарядка. Ровная спина и расправленные плечи — это тоже дисциплина, а не мелочь.',
        'Сформулируй одну просьбу точно: кому именно, что конкретно нужно и к какому сроку. Отправь её, не переписывая трижды.',
      ],
      [
        'Начни день со стакана воды и завтрака без экрана: первые 20 минут утра принадлежат тебе, а не чужим новостям.',
        'Разбери большую задачу, которая пугает, на три маленьких шага и сделай первый из них до обеда — начать всегда тяжелее, чем продолжать.',
        'За час до сна выключи уведомления и подведи итог дня в двух предложениях: что закрыл и что отложил осознанно.',
      ],
      [
        'Проверь свои границы: вспомни, где сегодня хочешь согласиться против желания, — и в этом месте спокойно откажи, одним предложением.',
        'Сделай один «дорогой» шаг к цели — тот, который приближает по-настоящему, даже если он маленький, страшный и неидеальный.',
        'Побудь 15 минут в тишине без контента и фона: просто свои мысли, без подкастов, музыки и скролла.',
      ],
      [
        'Утром запиши три конкретные цели на день с измеримым результатом, а вечером честно отметь, что из них реально закрыто.',
        'Потренируй внимание одним блоком работы на 25 минут без переключений: телефон в другой комнате, одна задача, один экран.',
        'Запиши одну ошибку дня как данные: причина → вывод → что изменить завтра. Ошибка без вывода — просто потеря времени.',
      ],
      [
        'Начни утро с трёх действий: встань, умойся холодной водой, заправь постель — они задают тон и дисциплину всему дню.',
        'Поймай момент, когда хочется сорваться или ответить резко, и вставь паузу на 10 секунд: три медленных вдоха и выбор, а не реакция.',
        'Подведи итог недели заранее: какие твои слова и действия сегодня ты бы повторил, а какие — изменил?',
      ],
      [
        'Отложи телефон на час и сделай самое важное дело в полной тишине — без фоновых приложений и уведомлений, с одним фокусом.',
        'Позволь себе один настоящий перерыв без чувства вины: 20 минут того, что нравится, без экрана и смартфона.',
        'Перед сном скажи вслух одну вещь, за которую благодарен сегодня, и одну конкретную вещь, которую сделаешь завтра первым делом.',
      ],
    ];
    return pool[day % pool.length];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: (widget.isDark ? Colors.white : widget.titleColor)
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.chipBg,
                  border: Border.all(
                    color: widget.bloodSoft.withValues(alpha: 0.85),
                    width: 1.4,
                  ),
                ),
                // Топор — символ режима (как на карточке в настройках).
                child: Center(
                  child: Text(
                    '🪓',
                    style: TextStyle(
                      fontSize: 24,
                      color: widget.isDark ? null : const Color(0xFF8E1020),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  Translations.t('berserkTitle', context),
                  style: TextStyle(
                    color: widget.titleColor,
                    fontSize: 18.5,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.55,
                    height: 1.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            Translations.t('berserkSubtitle', context),
            style: TextStyle(
              color: widget.bodyColor,
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          // === Практика от AGI — шаги на сегодня ===
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.chipBg,
                  widget.bloodSoft.withValues(
                    alpha: widget.isDark ? 0.22 : 0.08,
                  ),
                ],
              ),
              border: Border.all(
                color: widget.bloodSoft.withValues(
                  alpha: widget.isDark ? 0.55 : 0.35,
                ),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: widget.isDark
                          ? const Color(0xFFFFD166)
                          : const Color(0xFF8E1020),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        Translations.t('berserkPracticeTitle', context),
                        style: TextStyle(
                          color: widget.titleColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Мелкая кнопка обновления: при нажатии ИИ генерирует
                    // свежие советы прямо сейчас, шаги плавно подменяются.
                    _SmallRefreshButton(
                      refreshing: _refreshing,
                      color: widget.bloodSoft,
                      onTap: _refreshSteps,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                // AnimatedSize: при смене шагов высота блока тоже плавно
                // перетекает (иначе новый текст прыгал по высоте).
                AnimatedSize(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    // Текст всегда виден сразу; когда ИИ присылает свежие
                    // шаги — они плавно заменяют оффлайн-набор.
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: AnimatedOpacity(
                      // Пока ИИ генерирует свежие шаги — старые мягко
                      // приглушаются, чтобы было видно, что идёт обновление.
                      duration: const Duration(milliseconds: 300),
                      opacity: _refreshing ? 0.45 : 1.0,
                      child: _StepList(
                        key: const ValueKey('steps'),
                        steps: steps,
                        isDark: widget.isDark,
                        titleColor: widget.titleColor,
                        bodyColor: widget.bodyColor,
                        bloodSoft: widget.bloodSoft,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ..._principles(context).map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.bolt, color: widget.bloodSoft, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        color: widget.bodyColor,
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        height: 1.28,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Translations.t('berserkMotto', context),
            style: TextStyle(
              color: widget.titleColor,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Готовые шаги «Практики от AGI».
class _StepList extends StatelessWidget {
  final List<String> steps;
  final bool isDark;
  final Color titleColor;
  final Color bodyColor;
  final Color bloodSoft;

  const _StepList({
    super.key,
    required this.steps,
    required this.isDark,
    required this.titleColor,
    required this.bodyColor,
    required this.bloodSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bloodSoft.withValues(alpha: isDark ? 0.25 : 0.15),
                  border: Border.all(
                    color: bloodSoft.withValues(alpha: isDark ? 0.6 : 0.4),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  // Маркдаун из ИИ рендерится: **жирный**, *курсив*,
                  // `код` — а не показывается маркерами.
                  child: buildMarkdownText(
                    steps[i],
                    TextStyle(
                      color: bodyColor,
                      fontSize: 13,
                      // Шаги «Практики от AGI» — жирные, читаются сразу.
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (i != steps.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// 8 принципов режима — содержимое плашки (переведено на языки).
List<String> _principles(BuildContext context) => <String>[
  Translations.t('berserkPrinciple1', context),
  Translations.t('berserkPrinciple2', context),
  Translations.t('berserkPrinciple3', context),
  Translations.t('berserkPrinciple4', context),
  Translations.t('berserkPrinciple5', context),
  Translations.t('berserkPrinciple6', context),
  Translations.t('berserkPrinciple7', context),
  Translations.t('berserkPrinciple8', context),
];

/// Обёртка над обычным FAB. Режим открывается долгим зажатием самого
/// «плюса», поэтому обёртка просто сохраняет стабильный слот под FAB.
class BerserkFabStack extends StatelessWidget {
  final Widget child;
  const BerserkFabStack({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 56, height: 56, child: child);
  }
}

/// Плавная «отдача сжатия» всего содержимого окна BERSERK: при нажатии
/// внутри окна контент очень мягко сжимается (0.985), при отпускании —
/// так же плавно возвращается. Только визуал, ничего не открывает.
class _SheetPress extends StatefulWidget {
  final Widget child;
  const _SheetPress({required this.child});

  @override
  State<_SheetPress> createState() => _SheetPressState();
}

class _SheetPressState extends State<_SheetPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Мелкая круглая кнопка «обновить» у «Практики от AGI»: мягко
/// продавливается при нажатии, а пока ИИ генерирует свежие советы —
/// значок плавно крутится.
class _SmallRefreshButton extends StatefulWidget {
  final bool refreshing;
  final Color color;
  final VoidCallback onTap;
  const _SmallRefreshButton({
    required this.refreshing,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SmallRefreshButton> createState() => _SmallRefreshButtonState();
}

class _SmallRefreshButtonState extends State<_SmallRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.refreshing) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _SmallRefreshButton old) {
    super.didUpdateWidget(old);
    if (widget.refreshing && !old.refreshing) {
      _spin.repeat();
    } else if (!widget.refreshing && old.refreshing) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.86 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.12),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: widget.refreshing
              ? RotationTransition(
                  turns: _spin,
                  child: Icon(Icons.autorenew, size: 16, color: widget.color),
                )
              : Icon(Icons.refresh, size: 16, color: widget.color),
        ),
      ),
    );
  }
}
