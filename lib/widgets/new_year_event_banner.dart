import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../main.dart';
import '../services/new_year_event_service.dart';
import '../services/haptics.dart';
import '../utils/snackbar.dart';
import '../widgets/rolling_counter.dart';

/// Компактное окно ивента «Каждый день дарят шапку». Открывается по тапу на
/// Деду Морозу в заголовке: за каждый день ивента выдаётся одна шапка, и к
/// Новому году их накапливается до 12. Двенадцатая — не шапка, а подарок.
///
/// Диалог сам рисует затемнение фона тем же таймлайном, что и карточка: у
/// роута барьер прозрачный, поэтому вход и выход — одна плавная анимация без
/// «двойного» фейда и без залипшего чёрного фона.
class NewYearEventBanner extends StatefulWidget {
  final VoidCallback? onClose;
  const NewYearEventBanner({super.key, this.onClose});

  @override
  State<NewYearEventBanner> createState() => _NewYearEventBannerState();
}

class _NewYearEventBannerState extends State<NewYearEventBanner>
    with TickerProviderStateMixin {
  static const _kIn = Duration(milliseconds: 520);
  static const _kOut = Duration(milliseconds: 380);
  static const _kTotalHats = NewYearEventService.totalDays;

  /// Появление и уход считаются ДВУМЯ разными контроллерами.
  ///
  /// Причина прозаична: `CurvedAnimation.reverseCurve` в этой версии Flutter
  /// на обратном ходе не применяется вообще (замер по кадрам: фон держался
  /// 190мс и обнулялся за последние 160мс — отсюда «залип и рывок»). Поэтому
  /// форма ухода задаётся отдельным прямым прогрессом `_out`, а не реверсом.
  late final AnimationController _open;
  late final AnimationController _out;

  /// Отдельный контроллер волны шапок: при заборе/сбросе число не меняется
  /// скачком, а «перетекает» из старого в новое, и индикаторы растворяются
  /// по одному справа налево.
  late final AnimationController _hatsCtrl;
  double _hatsFrom = 0;
  double _hatsTo = 0;

  // ── Появление (прогресс 0 → 1) ───────────────────────────────────────────
  late final Animation<double> _scrimIn;
  late final Animation<double> _fadeIn;
  late final Animation<double> _popIn;

  // ── Уход (тот же смысл, но прогресс растёт: 1 → 0) ───────────────────────
  late final Animation<double> _scrimOut;
  late final Animation<double> _fadeOut;
  late final Animation<double> _popOut;

  bool _marked = false;
  int _hats = 0;
  bool _loading = true;
  bool _closing = false;
  bool _closed = false;

  /// Просмотр по тройному тапу: карточка показывает другой день ивента, ничего
  /// не записывая. null — показан реальный сегодняшний день.
  int? _previewDay;

  /// Настоящее число шапок до входа в просмотр, чтобы вернуться к нему.
  int _hatsReal = 0;

  /// Подарок 12-го дня уже выдан — строка под прогрессом меняется с
  /// «впереди подарок» на то, что именно подарили.
  bool _prize = false;

  @override
  void initState() {
    super.initState();
    _open = AnimationController(vsync: this, duration: _kIn);
    _out = AnimationController(vsync: this, duration: _kOut);
    _hatsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Фон надувается за первые 55% появления.
    _scrimIn = CurvedAnimation(
      parent: _open,
      curve: const Interval(0.0, 0.55, curve: Curves.easeInOut),
    );
    _fadeIn = CurvedAnimation(
      parent: _open,
      curve: const Interval(0.0, 0.60, curve: Curves.easeOutCubic),
    );
    _popIn = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _open,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutBack),
      ),
    );

    // Фон гаснет за первые 55% ухода (быстрее карточки, но с плавными
    // краями: easeInOut не даёт и «хлопка», и залипания).
    _scrimOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _out,
        curve: const Interval(0.0, 0.55, curve: Curves.easeInOut),
      ),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _out,
        curve: const Interval(0.15, 1.0, curve: Curves.easeInOut),
      ),
    );
    _popOut = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(
        parent: _out,
        curve: const Interval(0.15, 1.0, curve: Curves.easeInOut),
      ),
    );

    _open.forward();
    _refresh();
  }

  /// Общий прослущик: любая из фаз обязана перерисовывать скрим и карточку.
  Listenable get _phase => Listenable.merge([_open, _out]);

  double get _scrimT => _scrimIn.value * _scrimOut.value;
  double get _fadeT => _fadeIn.value * _fadeOut.value;
  double get _popT => _popIn.value * _popOut.value;

  /// Показанное сейчас число шапок (0..12, дробное во время перетекания).
  double get _hatsShown {
    final t = Curves.easeOutCubic.transform(_hatsCtrl.value);
    return _hatsFrom + (_hatsTo - _hatsFrom) * t;
  }

  /// Плавно перевести счётчик шапок к новому значению. [ms] — тем длиннее,
  /// чем больше шапок участвует в волне.
  void _setHats(int next, {required int ms}) {
    _hatsFrom = _hatsShown;
    _hatsTo = next.toDouble();
    _hats = next;
    _hatsCtrl.duration = Duration(milliseconds: ms);
    _hatsCtrl.forward(from: 0);
  }

  Future<void> _refresh() async {
    try {
      final svc = NewYearEventService();
      final now = DateTime.now();
      final todayKey =
          '${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final hats = await svc.hatCount();
      // Коллекция собрана → забирать больше нечего, и кнопка обязана быть
      // «Получено» даже там, где сегодня по календарю ещё не отмечено (тестовая
      // доводка дней пишет календарные даты ивента, а не сегодняшнюю).
      final marked = hats >= _kTotalHats || await svc.isMarked(todayKey);
      if (!mounted) return;
      setState(() {
        _marked = marked;
        _loading = false;
        _prize = svc.prizeGranted;
      });
      // Первый показ — каскадом: шапки засеваются одна за другой.
      _hatsReal = hats;
      _setHats(hats, ms: 160 + 50 * hats);
      // Коллекция уже собрана, а подарок не выдан (например, снекбар не
      // дожил до записи) — доезжает молча, без повторного поздравления.
      if (hats >= _kTotalHats) await _grantPrize(announce: false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onMark() async {
    final preview = _previewDay;
    if (preview != null) {
      // В бою одиночный тап в просмотре только возвращает к реальному дню:
      // чужой день никто не забирает. В тестовом режиме ([isTestMode]) —
      // наоборот, доезжает до показанного и по-настоящему: шапка выдаётся раз
      // в календарный день, за тестовую сборку 12 дней не набрать никогда, и
      // без этой доводки 12-й день с подарком просто недостижим.
      if (NewYearEventService.isTestMode) {
        await _fastForward(preview);
      } else {
        _showDay(null);
      }
      return;
    }
    if (_marked || _closing) return;
    Haptics.heavy();
    final svc = NewYearEventService();
    final bool ok;
    try {
      ok = await svc.markToday();
    } catch (_) {
      // Запись не легла на диск. Шапку НЕ отмечаем забранной: иначе она
      // горит в интерфейсе, а после перезапуска исчезает.
      if (!mounted) return;
      _say(
        Translations.t('nySaveFailed', context, 'Не удалось сохранить'),
        Icons.error_outline,
      );
      return;
    }
    if (!ok || !mounted) return;
    setState(() => _marked = true);
    _hatsReal = _hats + 1;
    _setHats(_hatsReal, ms: 460);
    if (_hatsReal >= _kTotalHats) await _grantPrize();
  }

  /// Довести коллекцию до показанного в просмотре дня (только тестовый
  /// режим). Возврат к своему дню — уже на новом, настоящем счётчике.
  Future<void> _fastForward(int day) async {
    final svc = NewYearEventService();
    try {
      await svc.fillTo(day);
    } catch (_) {
      // Опять же: без подтверждения не верим, что записалось. Иначе счётчик
      // в окне переехал бы, а после перезапуска встал на место.
      if (!mounted) return;
      _say(
        Translations.t('nySaveFailed', context, 'Не удалось сохранить'),
        Icons.error_outline,
      );
      return;
    }
    if (!mounted) return;
    final hats = await svc.hatCount();
    if (!mounted) return;
    final delta = (hats - _hats).abs();
    setState(() {
      _previewDay = null;
      _hatsReal = hats;
      _marked = hats >= _kTotalHats;
    });
    _setHats(hats, ms: 220 + 46 * delta);
    if (hats >= _kTotalHats) await _grantPrize();
  }

  /// Довести коллекцию до конца и выдать подарок. Идемпотентно: повторный
  /// вызов ничего не пишет и не шумит снекбаром.
  Future<void> _grantPrize({bool announce = true}) async {
    final svc = NewYearEventService();
    if (svc.prizeGranted) return;
    if (!await svc.grantPrize()) {
      // Флаг не лег на диск: тему НЕ включаем, иначе в этом окне она бы
      // появилась, а после перезапуска подарок исчез бы без следа.
      if (announce) {
        if (!mounted) return;
        _say(
          Translations.t('nySaveFailed', context, 'Не удалось сохранить'),
          Icons.error_outline,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _prize = true);
    // «Полярный набор» — это тема «Метель» и скин скважины на ПИН-экране.
    // Тему включаем сразу: 12-й день должен ощущаться открытым подарком, а
    // не строчкой в настройках, которую ещё надо найти. Откатывается так же
    // штатно — каруселью тем, а при сбросе события гаснет сама (см. _reset).
    _state()?.setThemeMode('metel');
    if (!announce) return;
    _say(
      Translations.t('nyPrizeGiven', context, 'Подарок открыт: Полярный набор'),
      Icons.card_giftcard_rounded,
    );
  }

  /// Состояние приложения (текущая тема) — nullable: окно ивента живёт в
  /// диалог-роуте, и кидать из-за отсутствующего предка нельзя.
  KeramikaAppState? _state() =>
      mounted ? context.findAncestorStateOfType<KeramikaAppState>() : null;

  void _say(String message, IconData icon) {
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: message,
      icon: icon,
      iconColor: icon == Icons.error_outline ? Colors.red : null,
    );
  }

  /// Тройной тап по «Забрать»: реальный день → 1-й → 12-й → реальный. По
  /// «Получено» — сразу 12-й («ты забрал всё, вот полная коллекция»), вторым
  /// тапом возврат. Числа и полоса шапок перетекают той же волной, что и при
  /// обычном заборе.
  void _onPreview() {
    if (_closing) return;
    Haptics.medium();
    final current = _previewDay;
    if (_marked) {
      _showDay(current == null ? _kTotalHats : null);
      return;
    }
    if (current == null) {
      _showDay(1);
    } else if (current == 1) {
      _showDay(_kTotalHats);
    } else {
      _showDay(null);
    }
  }

  void _showDay(int? day) {
    final target = day == null ? _hatsReal : day - 1;
    final delta = (target - _hats).abs();
    setState(() => _previewDay = day);
    _setHats(target, ms: 220 + 46 * delta);
  }

  /// Долгое нажатие на крестик — скрытый сброс прогресса (ивент привязан к
  /// календарю, иначе его нельзя перепроверить в одну дату).
  ///
  /// Сброс СПРАШИВАЕТСЯ: порог долгого нажатия — 500 мс, а этим же крестиком
  /// человек закрывает окно. Без подтверждения случайная задержка пальца
  /// молча стирала всю коллекцию — это и выглядело как «шапки не сохраняются».
  Future<void> _onReset() async {
    if (_closing) return;
    Haptics.heavy();
    final before = _hats;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('nyResetTitle', ctx, 'Сбросить ивент?')),
        content: Text(
          Translations.t(
            'nyResetBody',
            ctx,
            'Все собранные шапки и подарок исчезнут навсегда.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Translations.cancelOf(ctx)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Translations.t('nyResetConfirm', ctx, 'Сбросить')),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      await NewYearEventService().reset();
    } catch (_) {
      if (mounted) {
        _say(
          Translations.t('nySaveFailed', context, 'Не удалось сохранить'),
          Icons.error_outline,
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _marked = false;
      _previewDay = null;
      _hatsReal = 0;
      _prize = false;
    });
    // Сброс события ЗАБИРАЕТ подарок, значит и всё, что он давал: тема
    // «Метель» выключается, если была включена (скин скважины гаснет сам —
    // он читает prizeGranted при каждой сборке ПИН-экрана).
    final app = _state();
    if (app?.themeKey == 'metel') {
      app!.setThemeMode('grok');
      _say(
        Translations.t(
          'nyPrizeReverted',
          context,
          'Подарок снят: тема «Метель» выключена',
        ),
        Icons.snowing,
      );
    }
    _setHats(0, ms: 160 + 62 * before);
  }

  /// Плавный выход: scale+fade+дрейф вниз, затем синхронно закрываем.
  void _onAnimEnd(AnimationStatus status) {
    if (!_closing || status != AnimationStatus.completed) return;
    _out.removeStatusListener(_onAnimEnd);
    _doClose();
  }

  /// Идемпотентное закрытие: диалог закрывается ровно ОДИН раз.
  /// Страховка-таймаут в _close() вызывает тот же _doClose() — флаг
  /// _closed гарантирует, что двойной pop НЕ произойдёт (иначе на
  /// unmounted-контексте Navigator.of(context) ронял бы предыдущий экран).
  void _doClose() {
    if (_closed || !mounted) return;
    _closed = true;
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _close() {
    if (_closing) return;
    setState(() => _closing = true);
    _out.addStatusListener(_onAnimEnd);
    // Прогресс ухода растёт вперёд (0 → 1), поэтому форма задаётся обычным
    // curve-ом и reverseCurve тут не нужен вовсе.
    _out.forward();
    // Страховка: если animateTo не доехал до completed (быстрый повторный
    // тап / потеря vsync) — _doClose() всё равно закроет диалог ровно один
    // раз, иначе барьер «залипает» навсегда.
    Future.delayed(_kOut + const Duration(milliseconds: 150), _doClose);
  }

  @override
  void dispose() {
    _out.removeStatusListener(_onAnimEnd);
    _open.dispose();
    _out.dispose();
    _hatsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrimMax = isDark ? 0.68 : 0.44;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            // Alpha считается НАПРЯМУЮ в цвете, без FadeTransition: фейд
            // на весь экран — это Opacity-слой через saveLayer на каждый
            // кадр, на телефоне он и давал «дерганый» фон.
            child: AnimatedBuilder(
              animation: _phase,
              builder: (context, _) => ColoredBox(
                color: Colors.black.withValues(alpha: scrimMax * _scrimT),
              ),
            ),
          ),
        ),
        // Карточка: прозрачность — только по её собственным границам.
        Positioned.fill(
          child: Center(
            child: AnimatedBuilder(
              animation: _phase,
              // Карточка передаётся как `child:`, поэтому тики `_open`/`_out`
              // её НЕ пересобирают — меняется только обёртка. Раньше каждый
              // кадр входа/выхода перестраивал всё дерево (иконка, 12 шапок,
              // кнопки), и это и были 654 медленных кадра окна ивента.
              //
              // Форма дерева при этом ОБЯЗАНА быть неизменной. Соблазн
              // «в покое вообще снять Opacity/Transform» стоит того, что
              // было: последним кадром входа дерево меняет тип, Flutter
              // перемонтирует всю карточку, и у `AnimatedSwitcher`/`_SwapText`
              // слетают состояния — волна счётчика и перелистывание текста
              // обнулялись на середине (владельцу это выглядело как
              // «плавные счётчики и смены текстов пропали»).
              // Дешёвого пути это не отменяет: Opacity при 1.0 и 0.0
              // рисуется fast-path'ом без saveLayer (proxy_box.dart:896),
              // а Opacity с alpha>0 сам по себе композиционный слой, то
              // есть есть и граница перерисовки между скримом и карточкой.
              builder: (context, child) => Opacity(
                opacity: _fadeT,
                child: Transform.scale(
                  scale: _popT,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - _fadeT)),
                    child: child,
                  ),
                ),
              ),
              child: _loading || !NewYearEventService.isActive
                  ? _skeleton(cs)
                  : _card(context, cs, isDark),
            ),
          ),
        ),
      ],
    );
  }

  /// Пока грузим — компактный скелетон в цветах темы (не белое пятно).
  Widget _skeleton(ColorScheme cs) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: CircularProgressIndicator(color: cs.primary, strokeWidth: 2.5),
      ),
    );
  }

  Widget _card(BuildContext context, ColorScheme cs, bool isDark) {
    final day = _previewDay ?? NewYearEventService().currentDay;
    final isFinalDay = day == _kTotalHats;
    // В просмотре кнопка всегда «Забрать»: чужой день никто не забирает.
    final marked = _previewDay == null && _marked;
    final glass = isDark
        ? cs.surfaceContainerHigh.withValues(alpha: 0.6)
        : cs.surface.withValues(alpha: 0.78);
    final textMain = cs.onSurface;
    final textSub = isDark
        ? cs.onSurface.withValues(alpha: 0.65)
        : cs.onSurfaceVariant;

    /// Подпись дня. Число шапок едет ВОЛНОЙ, а не перескакивает в цель: иначе
    /// переезд на 1-й/12-й день выглядел щелчком, хотя полоса уже анимировалась.
    /// Строка перелистывается только по смене дня, а само число внутри неё
    /// крутится непрерывно — см. [_HatSubtitle].

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: glass,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? cs.outlineVariant.withValues(alpha: 0.45)
                : cs.outlineVariant.withValues(alpha: 0.7),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
              blurRadius: 26,
              spreadRadius: -4,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.5),
              blurRadius: 8,
              spreadRadius: -2,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _EventIcon(isFinalDay: isFinalDay, glow: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.t('nyEventTitle', context),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Подпись 12-го дня: эмодзи-салют 🎆 отсюда убран —
                      // во-первых, цветной эмодзи рисуется битмапом из
                      // NotoColorEmoji и не красится в цвет темы, во-вторых,
                      // на MIUI он местами рендерится тофу. Теперь это
                      // векторная «хлопушка» Material-шрифта в `cs.primary`.
                      //
                      // Слот под значок постоянен (14px всегда, не только в
                      // 12-й день): иначе при переезде на финальный день
                      // вся подпись прыгала бы вправо на ширину значка.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            child: AnimatedOpacity(
                              opacity: isFinalDay ? 1 : 0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              child: AnimatedScale(
                                scale: isFinalDay ? 1 : 0.5,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutBack,
                                child: Icon(
                                  Icons.celebration_rounded,
                                  size: 13,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            // Одна строка ВСЕГДА. Подпись живёт в колонке
                            // шириной ~200px (карточка 300 минус поля, иконка
                            // и слот значка), а «С Новым годом! Все 12 шапок
                            // собраны!» в эту ширину не влезало и роняло
                            // слово на вторую строку. `maxLines: 1` внутри
                            // `_SwapBox` сам оборачивает строку в
                            // FittedBox(scaleDown): текст чуть уменьшается
                            // (12 → ~11px), но остаётся целым на одной
                            // строке — и для любого языка, и при любом
                            // системном масштабе шрифта.
                            // Карточка-целиком пересобирается только по
                            // `_open`/`_out`; волна счётчика шапок трогает
                            // ровно этот узел и полосу ниже.
                            child: AnimatedBuilder(
                              animation: _hatsCtrl,
                              builder: (context, _) => _HatSubtitle(
                                template: Translations.t(
                                  'nyEventBody',
                                  context,
                                ),
                                finalText: Translations.t(
                                  'nyEventFinalDay',
                                  context,
                                ),
                                day: day,
                                shown: _hatsShown,
                                isFinalDay: isFinalDay,
                                style: TextStyle(fontSize: 12, color: textSub),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _hatsCtrl,
              builder: (context, _) => _HatProgress(
                shown: _hatsShown,
                total: _kTotalHats,
                accent: cs.primary,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Icon(
                  Icons.card_giftcard_rounded,
                  size: 12,
                  color: cs.primary.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _prize
                        ? Translations.t(
                            'nyPrizeDone',
                            context,
                            'Подарок открыт: тема «Метель», скин скважины, '
                                '60 дней истории питания и 30 категорий',
                          )
                        : Translations.t('nyGiftHint', context),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: textSub.withValues(alpha: 0.9),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _NyMarkButton(
                    marked: marked,
                    onTap: () async {
                      await _onMark();
                    },
                    onTripleTap: _onPreview,
                  ),
                ),
                const SizedBox(width: 8),
                _ClosePill(
                  isDark: isDark,
                  onTap: _close,
                  onLongPress: _onReset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const Color _kHatRed = Color(0xFFD8394F);
const Color _kHatFur = Color(0xFFEDE6E3);

/// Значок ивента — та самая шапка: чистый вектор с меховой опушкой, помпоном
/// и бликом (никаких растров и эмодзи). На финальный день — искра.
class _EventIcon extends StatelessWidget {
  final bool isFinalDay;
  final Color glow;
  const _EventIcon({required this.isFinalDay, required this.glow});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    glow.withValues(alpha: 0.26),
                    glow.withValues(alpha: 0.0),
                  ],
                  stops: const [0.25, 0.95],
                ),
              ),
            ),
          ),
          CustomPaint(
            size: const Size(38, 38),
            painter: _HatPainter(base: _kHatRed, trim: _kHatFur),
          ),
          Positioned(
            top: 1,
            right: 2,
            // Искра «прилетает» плавно: на переезде в 12-й день по тройному
            // тапу она появлялась одним кадром поверх остального плавного
            // перехода.
            child: AnimatedOpacity(
              opacity: isFinalDay ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: isFinalDay ? 1 : 0.4,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                // Финальный день — та же хлопнушка, что и в подписи: два
                // «искры-маркёра» разного смысла в одном окне выглядели случайным
                // набором значков.
                child: Icon(Icons.celebration_rounded, size: 14, color: glow),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Векторная шапка Санта-Клауса в юнит-квадрате (сторона = shortestSide):
/// левый склон поднимается, верх загибается вправо к помпону, правый край
/// опускается обратно к опушке.
class _HatPainter extends CustomPainter {
  final Color base;
  final Color trim;

  /// false — плоский силуэт: так рисуют ещё не забранные шапки в шкале.
  final bool detailed;
  const _HatPainter({
    required this.base,
    required this.trim,
    this.detailed = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double u(double v) => v * s;

    final body = Path()
      ..moveTo(u(0.08), u(0.78))
      ..cubicTo(u(0.09), u(0.45), u(0.27), u(0.18), u(0.52), u(0.14))
      ..cubicTo(u(0.70), u(0.11), u(0.84), u(0.23), u(0.85), u(0.40))
      ..cubicTo(u(0.78), u(0.34), u(0.70), u(0.32), u(0.63), u(0.36))
      ..cubicTo(u(0.68), u(0.51), u(0.72), u(0.64), u(0.73), u(0.78))
      ..close();

    final brimRect = Rect.fromLTRB(u(0.02), u(0.68), u(0.79), u(0.92));
    final brim = RRect.fromRectAndRadius(brimRect, Radius.circular(u(0.12)));
    final pomCenter = Offset(u(0.865), u(0.45));
    final pomRadius = u(0.125);

    if (!detailed) {
      final flat = Paint()..color = base;
      canvas.drawPath(body, flat);
      canvas.drawCircle(pomCenter, pomRadius, flat);
      canvas.drawRRect(brim, flat);
      return;
    }

    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, 0.26)!,
            base,
            Color.lerp(base, Colors.black, 0.24)!,
          ],
        ).createShader(Rect.fromLTRB(u(0.05), u(0.10), u(0.86), u(0.80))),
    );

    canvas.drawCircle(
      pomCenter,
      pomRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.5),
          colors: [Colors.white, trim],
        ).createShader(Rect.fromCircle(center: pomCenter, radius: pomRadius)),
    );

    canvas.drawRRect(
      brim,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, trim],
        ).createShader(brimRect),
    );

    // Блик по левому склону тульи.
    final sheen = Path()
      ..moveTo(u(0.17), u(0.72))
      ..cubicTo(u(0.18), u(0.48), u(0.32), u(0.28), u(0.49), u(0.23));
    canvas.drawPath(
      sheen,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.36)
        ..style = PaintingStyle.stroke
        ..strokeWidth = u(0.075).clamp(0.8, 2.4)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HatPainter old) =>
      old.base != base || old.trim != trim || old.detailed != detailed;
}

/// Подарок — коробка с крышкой, лентой и бантом. Тот же юнит-квадрат, что у
/// шапки, поэтому 12-й слот шкалы рисуется «в вес» с остальными.
class _GiftPainter extends CustomPainter {
  final Color base;
  final Color ribbon;
  final bool detailed;
  const _GiftPainter({
    required this.base,
    required this.ribbon,
    this.detailed = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double u(double v) => v * s;

    final box = RRect.fromRectAndRadius(
      Rect.fromLTRB(u(0.13), u(0.42), u(0.87), u(0.90)),
      Radius.circular(u(0.06)),
    );
    final lid = RRect.fromRectAndRadius(
      Rect.fromLTRB(u(0.06), u(0.28), u(0.94), u(0.45)),
      Radius.circular(u(0.06)),
    );
    final band = Rect.fromLTRB(u(0.43), u(0.42), u(0.57), u(0.90));
    final loopL = Rect.fromCircle(
      center: Offset(u(0.335), u(0.185)),
      radius: u(0.125),
    );
    final loopR = Rect.fromCircle(
      center: Offset(u(0.665), u(0.185)),
      radius: u(0.125),
    );
    final knot = Rect.fromCircle(
      center: Offset(u(0.5), u(0.245)),
      radius: u(0.085),
    );

    final flat = Paint()..color = base;
    if (!detailed) {
      canvas
        ..drawRRect(box, flat)
        ..drawRRect(lid, flat)
        ..drawOval(loopL, flat)
        ..drawOval(loopR, flat)
        ..drawOval(knot, flat);
      return;
    }

    final boxPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(base, Colors.white, 0.24)!,
          base,
          Color.lerp(base, Colors.black, 0.26)!,
        ],
      ).createShader(box.outerRect);
    canvas.drawRRect(box, boxPaint);
    canvas.drawRRect(
      lid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(base, Colors.white, 0.34)!,
            Color.lerp(base, Colors.black, 0.10)!,
          ],
        ).createShader(lid.outerRect),
    );

    final ribbonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, ribbon],
      ).createShader(band);
    canvas
      ..drawRect(band, ribbonPaint)
      ..drawOval(loopL, Paint()..color = ribbon)
      ..drawOval(loopR, Paint()..color = ribbon)
      ..drawOval(knot, Paint()..color = Color.lerp(ribbon, Colors.white, 0.5)!);

    // Складки банта, иначе на 20 px он читается как две сплошные пуговицы.
    final crease = Paint()
      ..color = Color.lerp(ribbon, Colors.black, 0.28)!.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u(0.035).clamp(0.6, 1.4);
    canvas
      ..drawArc(loopL.deflate(u(0.03)), 2.6, 1.6, false, crease)
      ..drawArc(loopR.deflate(u(0.03)), -0.5, 1.6, false, crease);
  }

  @override
  bool shouldRepaint(_GiftPainter old) =>
      old.base != base || old.ribbon != ribbon || old.detailed != detailed;
}

/// Прогресс: полоса + 12 слотов. Забранные шапки — цветные, остальные —
/// плоские силуэты; последний слот — подарок. [shown] дробное, поэтому
/// набор и сброс идут волной: слот с номером выше `shown` гаснет плавно.
class _HatProgress extends StatelessWidget {
  final double shown;
  final int total;
  final Color accent;
  const _HatProgress({
    required this.shown,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = cs.outlineVariant.withValues(alpha: 0.55);

    Widget slot(int i, double px) {
      final isGift = i == total - 1;
      // 0..1: насколько этот слот уже «есть». Дробным он бывает только
      // во время перетекания счётчика — отсюда поштучное растворение.
      final vis = (shown - i).clamp(0.0, 1.0);
      final size = Size.square(px);
      return SizedBox(
        width: px,
        height: px,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (isGift)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: 0.20),
                        accent.withValues(alpha: 0.0),
                      ],
                      stops: const [0.35, 0.95],
                    ),
                  ),
                ),
              ),
            CustomPaint(
              size: size,
              painter: isGift
                  ? _GiftPainter(base: empty, ribbon: empty, detailed: false)
                  : _HatPainter(base: empty, trim: empty, detailed: false),
            ),
            if (vis > 0.001)
              Opacity(
                opacity: vis,
                child: Transform.scale(
                  scale: 0.55 + 0.45 * vis,
                  alignment: Alignment.bottomCenter,
                  child: CustomPaint(
                    size: size,
                    painter: isGift
                        ? _GiftPainter(
                            base: _kHatRed,
                            ribbon: _kHatFur,
                            detailed: true,
                          )
                        : _HatPainter(
                            base: _kHatRed,
                            trim: _kHatFur,
                            detailed: true,
                          ),
                  ),
                ),
              ),
            if (isGift && vis > 0.99)
              Positioned(
                top: -3,
                right: -2,
                child: Icon(Icons.auto_awesome_rounded, size: 9, color: accent),
              ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (shown / total).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: cs.outlineVariant.withValues(alpha: 0.4),
            color: accent,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < total - 1; i++)
              Expanded(child: Center(child: slot(i, 14))),
            // Подарок отделён и крупнее — он не «ещё одна шапка».
            const SizedBox(width: 5),
            slot(total - 1, 19),
          ],
        ),
      ],
    );
  }
}

/// Кнопка «Забрать шапку» с плавным «вдавливанием».
///
/// Тройной тап считается вручную, а не через `onTripleTap`: тот ставится в
/// один детектор с `onTap` и поэтому откладывает каждый одиночный тап на всё
/// окно распознавания жеста — забирать шапку стало бы заметно позже.
class _NyMarkButton extends StatefulWidget {
  final bool marked;
  final VoidCallback onTap;
  final VoidCallback onTripleTap;
  const _NyMarkButton({
    required this.marked,
    required this.onTap,
    required this.onTripleTap,
  });

  @override
  State<_NyMarkButton> createState() => _NyMarkButtonState();
}

class _NyMarkButtonState extends State<_NyMarkButton> {
  static const _kTapWindow = Duration(milliseconds: 480);

  /// Ширина слота подписи по обеим её вариантам, посчитанная один раз на
  /// пару подписей (см. [_labelSlotWidth]).
  static final Map<(String, String, TextStyle), double> _slotWidths = {};

  bool _pressed = false;
  int _taps = 0;
  Timer? _tapTimer;

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    _tapTimer?.cancel();
    _taps++;
    if (_taps >= 3) {
      _taps = 0;
      widget.onTripleTap();
      return;
    }
    _tapTimer = Timer(_kTapWindow, () => _taps = 0);
    // Первый тап сразу работает как «Забрать»; в состоянии «Получено» он
    // ничего не делает и только копится в тройной тап.
    if (!widget.marked) widget.onTap();
  }

  /// Слот подписи = ширина БОЛЕЕ ДЛИННОЙ из двух подписей.
  ///
  /// Row кнопки центрирует группу «значок + подпись» по содержимому, поэтому
  /// пока подпись имеет свою ширину, смена «Забрать» → «Получено» (а в
  /// французской локализации «Récupérer» → «Reçu» — почти вдвое) двигала и
  /// значок. Фиксированный слот убирает движение: габарит группы не меняется
  /// вовсе. Считается по TextPainter, а не константой, чтобы не зависеть от
  /// локализации и системного размера текста.
  ///
  /// Меряется НЕ стиль кнопки, а тот же стиль, что реально рисует [Text]:
  /// `Text` без своего DefaultTextStyle не остаётся — он берёт
  /// `DefaultTextStyle.style.merge(свой)`, поэтому унаследованные
  /// `letterSpacing`/`fontFamily`/`height` делали строку шире измеренного
  /// слота, и «Получено» переносилось на вторую строку. Плюс габарит
  /// округляется вверх: доступная ширина равна слоту, и запас в доли пикселя
  /// — это уже перенос слова.
  double _labelSlotWidth(BuildContext context, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final measured = effective.copyWith(
      fontSize: scaler.scale(effective.fontSize ?? 14),
    );
    final a = Translations.t('nyMarkBtn', context);
    final b = Translations.t('nyMarkedBtn', context);
    final key = (a, b, measured);
    final cached = _slotWidths[key];
    if (cached != null) return cached;
    final dir = Directionality.of(context);
    var w = 0.0;
    for (final s in [a, b]) {
      final tp = TextPainter(textDirection: dir)
        ..text = TextSpan(text: s, style: measured)
        ..layout();
      w = math.max(w, tp.width);
    }
    final slot = w.ceilToDouble() + 1;
    _slotWidths[key] = slot;
    return slot;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      color: widget.marked ? cs.onSurface : cs.onPrimary,
    );
    final label = Translations.t(
      widget.marked ? 'nyMarkedBtn' : 'nyMarkBtn',
      context,
    );
    // Оба состояния — из цветов ТЕКУЩЕЙ темы. Раньше «Получено» красилось
    // плоским `secondary`, который в половине тем совпадал с фоном карточки,
    // и кнопка выглядела серой заглушкой.
    final base = widget.marked
        ? Color.lerp(cs.surfaceContainerHigh, cs.primary, dark ? 0.20 : 0.16)!
        : cs.primary;
    final deep = widget.marked
        ? Color.lerp(cs.surfaceContainerHigh, cs.primary, dark ? 0.06 : 0.05)!
        : cs.tertiary;
    final fg = widget.marked ? cs.onSurface : cs.onPrimary;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            // Градиент, тень и цвет перетекают, а не переключаются кадром:
            // «Забрать» → «Получено» должно быть одним движением. Время —
            // то же, что у перелистывания подписи и значка.
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                // Три стопа: зеркальный блик у верхней кромки, тело, глубина
                // внизу — та же стеклянность, что у таблетки разделов.
                colors: [Color.lerp(base, Colors.white, 0.30)!, base, deep],
                stops: const [0.0, 0.46, 1.0],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: widget.marked ? (dark ? 0.16 : 0.55) : 0.32,
                ),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(
                    alpha: widget.marked ? (dark ? 0.16 : 0.12) : 0.30,
                  ),
                  blurRadius: 14,
                  spreadRadius: -2,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Слот фиксированной ширины: у галки и подарка разные
                // габариты на одном и том же size 15, и при смене «Забрать»
                // → «Получено» подпись уезжала влево вместе со значком.
                SizedBox(
                  width: 20,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutQuad,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.55, end: 1).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      key: ValueKey(widget.marked),
                      widget.marked
                          ? Icons.check_circle_rounded
                          : Icons.card_giftcard_rounded,
                      size: 15,
                      color: fg,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: _labelSlotWidth(context, labelStyle),
                  child: _SwapText(text: label, style: labelStyle, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Компактная кнопка закрытия (X) в карточке с плавным «вдавливанием».
/// Долгое нажатие — скрытый сброс накопленных шапок.
class _ClosePill extends StatefulWidget {
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ClosePill({
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_ClosePill> createState() => _ClosePillState();
}

class _ClosePillState extends State<_ClosePill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          // AnimatedContainer, а не Container: фон кружка при зажатии щёлкал
          // одним кадром, хотя сам кружок уже сжимался плавно.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pressed
                  ? cs.outlineVariant.withValues(
                      alpha: widget.isDark ? 0.4 : 0.3,
                    )
                  : cs.outlineVariant.withValues(
                      alpha: widget.isDark ? 0.18 : 0.12,
                    ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: widget.isDark ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Плавная смена содержимого по ключу [swapKey]: старое уходит вверх и
/// гаснет, новое приезжает снизу.
///
/// Ключ задаёт вызывающая сторона, и это принципиально: [child] перестраивается
/// каждый кадр волны счётчика, а перелистывать нужно только настоящую смену
/// подписи.
class _SwapBox extends StatelessWidget {
  final Widget child;

  /// По чему менять именно КРОССФЕЙД. У [_SwapText] по умолчанию сам текст,
  /// но для строки с числом шапок это дало бы двенадцать наложенных
  /// затуханий за одну волну. Там ключ — день: фраза перелистывается один
  /// раз, а счётчик внутри неё крутится своей волной.
  final Object? swapKey;

  /// Где стоит строка внутри Stack-обёртки. Для подписи в колонке у карточки
  /// это `centerStart` (левый край на месте), для текста внутри кнопки —
  /// `center`.
  final AlignmentGeometry align;

  /// Ограничение на число строк. Подпись кнопки обязана быть в одну строку:
  /// её слот имеет ширину самой длинной из двух подписей, и любой запас в
  /// доли пикселя (калькулятор округлит ширину на 1e-13 больше измеренного
  /// габарита) ронял бы слово на вторую строку — на телефоне, а не в тесте.
  final int? maxLines;

  const _SwapBox({
    required this.child,
    this.swapKey,
    this.align = Alignment.center,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      // Коробка строки перетекает, а не переключается кадром: на 12-й день
      // подпись длиннее и переносится в две строки, Row центрирует колонку по
      // вертикали — без этой обёртки заголовок «Каждый день дарят шапку»
      // дёргался вверх на полстроки. Время = времени кроссфейду, иначе высота
      // доезжает раньше, чем доехала строка.
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOut,
      alignment: align,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        // Кривые ПОСИММЕТРИЧНЕЕ, чем было. Раньше уход шёл по
        // `easeInCubic`: старая строка висела почти непрозрачной до конца
        // перехода и исчезала одним кадром — это и читалось как «сменяется
        // НЕ плавно», хотя сам кроссфейд был. `easeOut` на уходе гасит
        // строку с самого начала, и ход становится непрерывным.
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutQuad,
        layoutBuilder: (current, previous) => Stack(
          alignment: align,
          children: <Widget>[...previous, ?current],
        ),
        transitionBuilder: (child, anim) {
          // Уходящая строка доезжает до нуля ВВЕРХ, откуда пришла новая.
          // С одним Tween на оба направления у старого слоя прогресс идёт
          // 1 → 0, то есть он уехал бы на +0.45 вниз — строки менялись бы
          // местами, расходясь в разные стороны, вместо перелистывания.
          final leaving = anim.status == AnimationStatus.reverse;
          // Ход отдельно от прозрачности: движение по easeOutCubic, иначе
          // смещение «догоняет» к концу и последние кадры выглядят рывком.
          final slide = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              // 0.45 строки (≈5px для 12px подписи) глаз не ловил вовсе:
              // перелистывание выглядело как обычный фейд. ~0.9 строки —
              // видно, что строка именно сошла/пришла, а не мигнула.
              position: Tween<Offset>(
                begin: Offset(0, leaving ? -0.9 : 0.9),
                end: Offset.zero,
              ).animate(slide),
              child: child,
            ),
          );
        },
        // Ключ обязан стоять НА ПРЯМОМ ребёнке switcher'а. AnimatedSwitcher
        // решает «анимировать смену или просто подменить текст» по
        // Widget.canUpdate своего child (runtimeType + key). Когда строка
        // ради переноса «Получено» завернулась в бесключевой FittedBox,
        // canUpdate всегда давал true, ветка анимации не выполнялась, и и
        // подпись дня, и «Забрать»→«Получено» менялись одним кадром —
        // «смены текстов пропали», хотя сам кроссфейд был на месте.
        // KeyedSubtree поднимает ключ на уровень выше, не меняя тип ребёнка,
        // а обёртка по [maxLines] лежит УЖЕ внутри ключа.
        child: KeyedSubtree(
          key: ValueKey(swapKey),
          child: maxLines == 1
              ? FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child)
              : child,
        ),
      ),
    );
  }
}

/// Плавная смена подписи или числа: старое значение гаснет и уходит вверх,
/// новое приходит снизу. Ключ — сам текст, поэтому анимация случается ровно
/// на смене значения, а не на каждом кадре анимации шапок.
class _SwapText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;

  const _SwapText({required this.text, required this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    return _SwapBox(
      // Ключ — сам текст: анимация случается ровно на смене значения.
      swapKey: text,
      maxLines: maxLines,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        // Для однострочной подписи этого достаточно, чтобы ВООБЩЕ не было
        // второй строки при любой ширине слота: `softWrap: false` запрещает
        // сам перенос. Раньше «Получено» переносилось, потому что слот
        // расходился с реальным габаритом строки на доли пикселя.
        softWrap: maxLines == 1 ? false : null,
      ),
    );
  }
}

/// Подпись дня в карточке ивента: «День 3 из 12 · Шапок собрано: » + число.
///
/// Число ВЫНЕСЕНО из перелистываемой фразы. Пока весь текст с подставленным
/// счётчиком был одним [_SwapText] с ключом «день/число», волна 0→12
/// запускала двенадцать 380-мс перелистываний всей фразы подряд; переходы
/// не успевали закончиться и накладывались друг на друга — строки
/// «переплетались». Теперь фраза перелистывается ровно один раз, по смене
/// дня, а счётчик внутри неё крутится непрерывно за дробной частью значения
/// ([RollingCounter]).
class _HatSubtitle extends StatelessWidget {
  /// Шаблон подписи с {0} — день и {1} — число шапок.
  final String template;
  final int day;

  /// Показанное сейчас число шапок, дробное во время волны.
  final double shown;
  final TextStyle style;
  final bool isFinalDay;
  final String finalText;

  const _HatSubtitle({
    required this.template,
    required this.day,
    required this.shown,
    required this.style,
    required this.isFinalDay,
    required this.finalText,
  });

  @override
  Widget build(BuildContext context) {
    const tag = '{1}';
    final at = template.indexOf(tag);
    final head = (at < 0 ? template : template.substring(0, at)).replaceAll(
      '{0}',
      '$day',
    );
    final tail = at < 0
        ? ''
        : template.substring(at + tag.length).replaceAll('{0}', '$day');
    return _SwapBox(
      // Одна и та же структура ветки в обоих режимах: если финальный день
      // возвращать другим виджетом, AnimatedSwitcher увидит смену типа и
      // перемонтирует строку одним кадром вместо перелистывания.
      swapKey: isFinalDay ? 'final' : 'day$day',
      align: AlignmentDirectional.centerStart,
      maxLines: 1,
      // mainAxisSize.min + внешняя scaleDown: строка живёт на своей
      // естественной ширине и только уменьшается, если не влезает, — ровно
      // как это делал FittedBox вокруг одного Text.
      child: isFinalDay
          ? Text(finalText, style: style, maxLines: 1, softWrap: false)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(head, style: style, maxLines: 1),
                RollingCounter(value: shown, style: style),
                if (tail.isNotEmpty) Text(tail, style: style, maxLines: 1),
              ],
            ),
    );
  }
}
