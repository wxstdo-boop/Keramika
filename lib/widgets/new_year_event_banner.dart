import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../l10n/translations.dart';
import '../main.dart';
import '../services/new_year_event_service.dart';
import '../services/haptics.dart';
import '../utils/design_tokens.dart';
import '../utils/snackbar.dart';
import '../widgets/press_scale.dart';

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
  static const _kIn = Duration(milliseconds: 560);
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
  late final Animation<double> _contentIn;

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
    // Без `easeOutBack`: «отскок» за единицу читался рывком в конце
    // появления — карточка «дёргалась» на последних кадрах.
    _popIn = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _open,
        curve: const Interval(0.0, 0.90, curve: Curves.easeOutCubic),
      ),
    );
    // Содержимое карточки «догоняет» её появление: заголовок, полоса и
    // кнопки всплывают на считаные пиксели позже самой плашки. Один общий
    // прогресс — ни одного лишнего контроллера, а вход читается собранным,
    // а не «вспышкой целиком».
    _contentIn = CurvedAnimation(
      parent: _open,
      curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic),
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

  /// Кривая текущей волны. Для коротких переходов — мягкий разгон,
  /// для длинных (0→12, сброс) — симметричная `easeInOutCubic`: она трогается
  /// и останавливается плавно, поэтому цифры и полоса не «взмывают» на первых
  /// кадрах и не «втыкаются» в конце.
  Curve _hatsCurve = Curves.easeOutCubic;

  /// Показанное сейчас число шапок (0..12, дробное во время перетекания).
  double get _hatsShown {
    final t = _hatsCurve.transform(_hatsCtrl.value);
    return _hatsFrom + (_hatsTo - _hatsFrom) * t;
  }

  /// Плавно перевести счётчик шапок к новому значению. [ms] — тем длиннее,
  /// чем больше шапок участвует в волне.
  void _setHats(int next, {required int ms}) {
    final delta = (next.toDouble() - _hatsShown).abs();
    _hatsFrom = _hatsShown;
    _hatsTo = next.toDouble();
    _hats = next;
    _hatsCurve = delta >= 4 ? Curves.easeInOutCubic : Curves.easeOutCubic;
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
  AgyshaAppState? _state() =>
      mounted ? context.findAncestorStateOfType<AgyshaAppState>() : null;

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
    final sure = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      // Затемняет фон сам маршрут, поэтому отдельного скрима внутри окна нет:
      // окно не «вспыхивает» двойным затемнением на входе.
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, _) => _ResetEventDialog(
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
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
              // Пока грузим — скелетон, дальше карточка. Смена идёт
              // КРОССФЕЙДОМ: раньше карточка (вместе с кнопкой «Забрать»)
              // появлялась одним кадром поверх скелетона и читалась как
              // «дёрнулась». Тот же мягкий ход, что у прочих окон.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.97, end: 1).animate(anim),
                    child: child,
                  ),
                ),
                child: _loading || !NewYearEventService.isActive
                    ? _skeleton(cs)
                    : _card(context, cs, isDark),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Пока грузим — компактная «дышащая» заглушка в цветах темы.
  ///
  /// Раньше здесь крутилось штатное `CircularProgressIndicator`: оно
  /// перерисовывается КАЖДЫЙ кадр, пока идёт чтение, и вход окна читался
  /// «дёрганым» (жалоба «загрузка лаги остались»). Пульсация сделана на
  /// `TweenAnimationBuilder` — короткий разовый проход, дальше кадры не
  /// тратятся. Габарит тот же, что у карточки, поэтому переход в неё не
  /// «прыгает».
  Widget _skeleton(ColorScheme cs) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(26),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 0.85),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        builder: (context, t, _) => Center(
          child: Container(
            width: 120,
            height: 10,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.16 * t),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ColorScheme cs, bool isDark) {
    final day = _previewDay ?? NewYearEventService().currentDay;
    final isFinalDay = day == _kTotalHats;
    final marked = _previewDay == null && _marked;
    final textMain = cs.onSurface;
    final textSub = isDark
        ? cs.onSurface.withValues(alpha: 0.66)
        : cs.onSurfaceVariant;
    // Единый акцент карточки — АЛЫЙ с лёгкой примесью тона темы. Раньше
    // медальон, бейдж дня, полоса прогресса и значок подарка брали
    // `cs.primary`: на дефолтной палитре это сирень, в «Метели» — бирюза, и
    // внутри кровавой карточки они читались чужими вставками. Теперь весь
    // набор — в одном красном роду, тема лишь подкрашивает его на 10 %.
    final accent = Color.lerp(BrandColors.red, cs.primary, 0.10)!;

    // Подложка карточки — мягкий вертикальный градиент с фирменным отливом
    // сверху: окно читается «снежным стеклом», а не плоской плашкой. Градиент
    // статичен, поэтому ни одного лишнего слоя в кадрах анимации входа.
    final glass = isDark
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                BrandColors.red.withValues(alpha: 0.14),
                cs.surfaceContainerHigh,
              ),
              cs.surfaceContainerLow,
            ],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                BrandColors.red.withValues(alpha: 0.05),
                cs.surface,
              ),
              cs.surfaceContainerLow,
            ],
          );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          gradient: glass,
          borderRadius: BorderRadius.circular(26),
          // Кант карточки — полупрозрачный БРЕНДОВЫЙ АЛЫЙ, а не сиреневый
          // `primary`: на дефолтной палитре окно читалось чужеродным синим
          // ободком посреди кровавой семьи.
          border: Border.all(
            color: BrandColors.red.withValues(alpha: isDark ? 0.42 : 0.34),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.52 : 0.16),
              blurRadius: 30,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
            // Верхний блик: карточка «приподнята», а не вклеена в фон.
            BoxShadow(
              color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.6),
              blurRadius: 8,
              spreadRadius: -2,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            children: [
              // Свечение из верхнего левого угла — «полярное сияние» за
              // медальоном. Один статичный слой, без пересборки за кадр.
              Positioned(
                top: -46,
                left: -36,
                child: IgnorePointer(
                  child: Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          BrandColors.red.withValues(
                            alpha: isDark ? 0.20 : 0.10,
                          ),
                          BrandColors.red.withValues(alpha: 0.0),
                        ],
                        stops: const [0.1, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _contentIn,
                builder: (context, child) => Opacity(
                  opacity: _contentIn.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - _contentIn.value)),
                    child: child,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _EventIcon(isFinalDay: isFinalDay, glow: accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Заголовок занимает ВСЮ ширину строки: раньше
                                // рядом с ним стоял бейдж дня, и на узком
                                // экране «главный» текст ужимался до мелочи
                                // («не умещается»). Теперь заголовок не делит
                                // строку ни с кем, а день ушёл вниз — к строке
                                // со шапками, где раньше он и дублировался
                                // («День 3 из 12» под бейджем «3 / 12»).
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      Translations.t('nyEventTitle', context),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.1,
                                        color: textMain,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                // `AnimatedSize` держит высоту строки живой:
                                // при смене подписи на 12-й день (строка
                                // переносится) высота доезжает, а не прыгает
                                // кадром — карточка не «дёргается».
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 380),
                                  curve: Curves.easeInOut,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // День ивента — компактный бейдж «3 / 12»:
                                      // ЕДИНСТВЕННОЕ место, где день назван (из
                                      // подписи ниже его дубль убран). Число
                                      // языконезависимо, поэтому новых строк
                                      // перевода не заводим. Бейдж НЕ сжимается.
                                      // Бейдж дня идёт за ДРОБНОЙ волной
                                      // счётчика: на 12-й день и при сбросе
                                      // число перекатывается вместе с шапками,
                                      // а не щёлкает кадром.
                                      AnimatedBuilder(
                                        animation: _hatsCtrl,
                                        builder: (context, _) => _DayBadge(
                                          dayShown: _previewDay != null
                                              ? _previewDay!.toDouble()
                                              : (_hatsShown + 1).clamp(
                                                  1.0,
                                                  _kTotalHats.toDouble(),
                                                ),
                                          total: _kTotalHats,
                                          accent: accent,
                                          isDark: isDark,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        width: 14,
                                        child: AnimatedOpacity(
                                          opacity: isFinalDay ? 1 : 0,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          child: AnimatedScale(
                                            scale: isFinalDay ? 1 : 0.5,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOutBack,
                                            child: Icon(
                                              Icons.celebration_rounded,
                                              size: 13,
                                              color: accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
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
                                            shown: _hatsShown,
                                            isFinalDay: isFinalDay,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textSub,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
                          accent: accent,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Подарок — отдельная «капсула» с иконкой, а не голая
                      // строка: читается как награда, а не мелкий приписной
                      // текст.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: BrandColors.red.withValues(
                            alpha: isDark ? 0.13 : 0.06,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: BrandColors.red.withValues(
                              alpha: isDark ? 0.26 : 0.18,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Значок и текст меняются КРОССФЕЙДОМ, а не кадром:
                            // на 12-й день и при сбросе капсула «перетекает»,
                            // как и остальные надписи окна.
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 380),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutQuad,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                    opacity: anim,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.72,
                                        end: 1,
                                      ).animate(anim),
                                      child: child,
                                    ),
                                  ),
                              child: Icon(
                                key: ValueKey(_prize),
                                _prize
                                    ? Icons.check_circle_rounded
                                    : Icons.card_giftcard_rounded,
                                size: 14,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: _SwapBox(
                                swapKey: _prize,
                                align: AlignmentDirectional.centerStart,
                                child: Text(
                                  _prize
                                      ? Translations.t(
                                          'nyPrizeDone',
                                          context,
                                          'Подарок открыт: тема «Метель», скин '
                                              'скважины, 60 дней истории '
                                              'питания и 30 категорий',
                                        )
                                      : Translations.t('nyGiftHint', context),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: textSub.withValues(alpha: 0.95),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Бейдж дня ивента: «3 / 12». Числа языконезависимы, поэтому новых строк
/// перевода не требуется, а акцентная капсула держит взгляд на прогрессе.
class _DayBadge extends StatelessWidget {
  /// Дробный день ивента: перекатывается вместе с волной шапок, поэтому
  /// смена дня (в том числе на 12-й и при сбросе) идёт плавно.
  final double dayShown;
  final int total;
  final Color accent;
  final bool isDark;

  const _DayBadge({
    required this.dayShown,
    required this.total,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RollDigits(
            value: dayShown,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: accent,
              height: 1.1,
            ),
          ),
          Text(
            ' / $total',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accent.withValues(alpha: 0.7),
              height: 1.1,
            ),
          ),
        ],
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
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Медальон: мягкая заливка + кант акцента. Шапка читается
          // «наградой» в оправе, а не значком, приклеенным к фону.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glow.withValues(alpha: dark ? 0.16 : 0.10),
                border: Border.all(color: glow.withValues(alpha: 0.30)),
                boxShadow: [
                  BoxShadow(
                    color: glow.withValues(alpha: dark ? 0.22 : 0.14),
                    blurRadius: 12,
                    spreadRadius: -3,
                  ),
                ],
              ),
            ),
          ),
          CustomPaint(
            size: const Size(34, 34),
            painter: _HatPainter(base: _kHatRed, trim: _kHatFur),
          ),
          Positioned(
            top: 0,
            right: 0,
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
                // «искры-маркёра» разного смысла в одном окне выглядели
                // случайным набором значков.
                child: Icon(Icons.celebration_rounded, size: 15, color: glow),
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
  final bool isDark;
  const _HatProgress({
    required this.shown,
    required this.total,
    required this.accent,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = cs.outlineVariant.withValues(alpha: isDark ? 0.42 : 0.55);

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
        // Полоса прогресса — своя: у штатной `LinearProgressIndicator` край
        // «щёлкает» на смене значения. Здесь значение уже дробное (волна), а
        // закруглённый трек и заливка совпадают по радиусу — край читается
        // цельным.
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: cs.outlineVariant.withValues(alpha: 0.35)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: total == 0 ? 0 : (shown / total).clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Полоса — от светлого аля к глубокому, БЕЗ примеси
                      // `tertiary`: в «Метели» третичный фиолетовый, и заливка
                      // уезжала в чужой тон посреди красной карточки.
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(accent, Colors.white, 0.18)!,
                          Color.lerp(accent, const Color(0xFF5E0812), 0.35)!,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        // Строка слотов живёт в собственном слое: тики волны перерисовывают
        // только её, а не полосу, подписи и кнопки карточки.
        RepaintBoundary(
          child: Row(
            children: [
              for (var i = 0; i < total - 1; i++)
                Expanded(child: Center(child: slot(i, 14))),
              // Подарок отделён и крупнее — он не «ещё одна шапка».
              const SizedBox(width: 5),
              slot(total - 1, 19),
            ],
          ),
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
      color: widget.marked ? cs.onSurface : Colors.white,
    );
    final label = Translations.t(
      widget.marked ? 'nyMarkedBtn' : 'nyMarkBtn',
      context,
    );
    // Оба состояния — из цветов ТЕКУЩЕЙ темы. Раньше «Получено» красилось
    // плоским `secondary`, который в половине тем совпадал с фоном карточки,
    // и кнопка выглядела серой заглушкой.
    // Акцент — БРЕНДОВЫЙ АЛЫЙ, а не `cs.primary`: на дефолтной палитре
    // primary сиреневый, а в «Метели» — бирюзовый, и кнопка «Забрать» в
    // начале ивента читалась чужеродной синей/зелёной «заглушкой» посреди
    // кровавой карточки («в начале кнопка ваще синяя блевотная»). Тон темы
    // теперь лишь едва подмешивается (8% вместо 18%): кнопка остаётся
    // АЛОЙ в любой палитре, но не выпадает из характера светлой/тёмной темы.
    final brand = Color.lerp(BrandColors.red, cs.primary, 0.08)!;
    final base = widget.marked
        ? Color.lerp(cs.surfaceContainerHigh, cs.primary, dark ? 0.20 : 0.16)!
        : brand;
    final deep = widget.marked
        ? Color.lerp(cs.surfaceContainerHigh, cs.primary, dark ? 0.06 : 0.05)!
        : Color.lerp(BrandColors.red, const Color(0xFF5E0812), 0.55)!;
    final fg = widget.marked ? cs.onSurface : Colors.white;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedScale(
          // Зажатие — ровное и монотонное: одна и та же кривая на входе и на
          // отпускании, без «отскока» и без ускорения к концу. Прежние 150 мс
          // с `easeOutCubic` читались как щелчок: кнопка «прыгала» под палец
          // и так же резко возвращалась.
          scale: _pressed ? 0.955 : 1.0,
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeInOut,
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
              // «Забрать» — белый кант по алому (стеклянная кромка).
              // «Получено» — НЕ белый и НЕ серый `outlineVariant`: на светлой
              // поверхности серое кольцо читалось грубой молочной обводкой
              // («обводка ублюдская»). Теперь кромка — полупрозрачно-алая,
              // та же, что у капсулы подарка: обе плашки читаются одним
              // набором, а не двумя разными рамками.
              border: Border.all(
                color: widget.marked
                    ? Color.lerp(
                        BrandColors.red,
                        cs.outlineVariant,
                        0.35,
                      )!.withValues(alpha: dark ? 0.42 : 0.32)
                    : Colors.white.withValues(alpha: 0.34),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (widget.marked ? cs.primary : brand).withValues(
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
        layoutBuilder: (current, previous) =>
            Stack(alignment: align, children: <Widget>[...previous, ?current]),
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
/// ([_RollDigits]) — по цифрам, как очки рейтинга, а не «колесом».
class _HatSubtitle extends StatelessWidget {
  /// Шаблон подписи; `{1}` — число собранных шапок.
  final String template;

  /// Показанное сейчас число шапок, дробное во время волны.
  final double shown;
  final TextStyle style;
  final bool isFinalDay;
  final String finalText;

  const _HatSubtitle({
    required this.template,
    required this.shown,
    required this.style,
    required this.isFinalDay,
    required this.finalText,
  });

  @override
  Widget build(BuildContext context) {
    const tag = '{1}';
    final at = template.indexOf(tag);
    final head = at < 0 ? template : template.substring(0, at);
    final tail = at < 0 ? '' : template.substring(at + tag.length);
    return _SwapBox(
      // Одна и та же структура ветки в обоих режимах: если финальный день
      // возвращать другим виджетом, AnimatedSwitcher увидит смену типа и
      // перемонтирует строку одним кадром вместо перелистывания.
      swapKey: isFinalDay ? 'final' : 'day',
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
                _RollDigits(value: shown, style: style),
                if (tail.isNotEmpty) Text(tail, style: style, maxLines: 1),
              ],
            ),
    );
  }
}

/// Число, которое меняется ПО ЦИФРАМ — тем же приёмом, что «очки рейтинга»
/// ([SmoothDigits] в профиле): изменившийся разряд проявляется из
/// прозрачного и чуть увеличивается, старый так же мягко гаснет.
///
/// Это НЕ «колесо»: прежний [RollingCounter] крутил всё число одной лентой,
/// и на «3» читалось перекатывание целиком, хотя менялась одна цифра.
/// Здесь колонка оживает только если разряд реально меняется при +1
/// («9 → 10» — да, «3 → 4» — одна колонка), поэтому движение всегда
/// осмысленное и мелкое.
///
/// Значение ДРОБНОЕ: кроссфейд идёт за волной счётчика непрерывно, а не
/// скачком на смене целого, — поэтому даже быстрая волна 0→12 не «дёргает»
/// цифры. Слоёв ровно два на разряд: `AnimatedSwitcher` здесь не годится —
/// на двенадцать смен подряд он накладывал бы переходы друг на друга.
///
/// Ширина берётся у табличной цифры: без этого разряды «пляшут» по
/// горизонтали на каждом шаге.
class _RollDigits extends StatelessWidget {
  final double value;
  final TextStyle style;

  const _RollDigits({required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    final v = value.isFinite && value > 0 ? value : 0.0;
    final lo = v.floor();
    final f = (v - lo).clamp(0.0, 1.0);
    // Табличные цифры: все разряды одной ширины — колонки не дышат.
    final s = style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final chars = '$lo'.split('');
    final last = chars.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++)
          _DigitSlot(
            // Позиция от ПРАВОГО края: единицы остаются единицами, и при
            // «9 → 10» появляется ровно один новый разряд.
            position: last - i,
            lo: lo,
            fraction: f,
            style: s,
          ),
      ],
    );
  }
}

/// Один разряд: текущая цифра гаснет, следующая проявляется — доля
/// [fraction] задаёт ход кроссфейда. Если разряд при +1 не меняется,
/// слот статичен (никакого ложного оживания).
class _DigitSlot extends StatelessWidget {
  /// Габарит одной табличной цифры. Считается один раз на стиль: `TextPainter`
  /// на каждый разряд в каждом кадре волны стоил заметной работы, а стиль за
  /// анимацию не меняется.
  static final Map<TextStyle, Size> _sizes = {};

  final int position;
  final int lo;
  final double fraction;
  final TextStyle style;

  const _DigitSlot({
    required this.position,
    required this.lo,
    required this.fraction,
    required this.style,
  });

  Size _measure() {
    final cached = _sizes[style];
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final size = Size(tp.width, tp.height);
    _sizes[style] = size;
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final pow = math.pow(10, position).round();
    final d0 = (lo ~/ pow) % 10;
    final d1 = ((lo + 1) ~/ pow) % 10;
    // Разряд не меняется — слот статичен, никакого ложного перехода.
    final f = d0 == d1 ? 0.0 : fraction;
    final size = _measure();
    // Ход кроссфейда — по мягкой кривой: без неё последние кадры волны
    // выглядят рывком, как было с линейной дробной частью.
    final eased = Curves.easeOutCubic.transform(f);
    // Прозрачность задаётся ЦВЕТОМ, а не `Opacity`: `Opacity` с alpha между
    // 0 и 1 заводит `saveLayer` на каждый разряд в каждом кадре — на
    // raster-bound телефоне это и есть «лагающее событие». Цвет с альфой
    // рисуется тем же проходом, без слоя.
    final fade = style.color ?? const Color(0xFF000000);
    TextStyle at(double a) => style.copyWith(
      color: fade.withValues(alpha: fade.a * a.clamp(0.0, 1.0)),
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Уходящая цифра: гаснет и чуть уменьшается — «отходит» назад.
          if (eased < 1.0)
            Transform.scale(
              scale: 1 - 0.16 * eased,
              child: Text('$d0', style: at(1 - eased), maxLines: 1),
            ),
          // Приходящая: проявляется и надувается из 0.84 до полного.
          if (eased > 0.0)
            Transform.scale(
              scale: 0.84 + 0.16 * eased,
              child: Text('$d1', style: at(eased), maxLines: 1),
            ),
        ],
      ),
    );
  }
}

/// Окно подтверждения сброса ивента — своя «стеклянная» карточка вместо
/// системного [AlertDialog].
///
/// Вид тот же, что у окна обновления: полупрозрачный алый кант бренда,
/// подложка с красным отливом (сквозь неё просвечивает фон) и мягкие тени.
/// Системный `AlertDialog` на дефолтной палитре выходил плоской серой
/// плашкой и выбивался из «кровавой» семьи, а его кнопки не отдавали под
/// пальцем.
///
/// Раскладка нарочно простая: одна колонка, одинаковые поля, кнопки в общей
/// строке равной ширины — окно не «косит» ни на узком экране, ни при
/// увеличенном системном шрифте.
class _ResetEventDialog extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _ResetEventDialog({required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            padding: const EdgeInsets.all(0.9),
            decoration: BoxDecoration(
              // ОДНА ровная алая кромка вместо диагонального градиента: тот
              // по периметру давал разный тон на каждой стороне и читался
              // пёстрой кривой рамкой («окно криво»). Толщина — волосяная.
              borderRadius: BorderRadius.circular(Radii.xl),
              color: BrandColors.red.withValues(alpha: 0.34),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.18),
                  blurRadius: 34,
                  spreadRadius: -4,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              // Радиус подложки на толщину канта меньше внешнего: иначе кант
              // «съедается» и кромка читается неровной.
              borderRadius: BorderRadius.circular(Radii.xl - 0.9),
              child: Container(
                decoration: BoxDecoration(
                  // Полупрозрачная подложка с красным отливом, как у окна
                  // обновления: фон просвечивает, но под ней достаточно
                  // плотности, чтобы текст читался. Без `BackdropFilter` —
                  // размытие под анимацией всплытия мерцает.
                  color: Color.alphaBlend(
                    BrandColors.red.withValues(alpha: 0.20),
                    cs.surfaceContainerHigh.withValues(alpha: 0.86),
                  ),
                  borderRadius: BorderRadius.circular(Radii.xl - 0.9),
                ),
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BrandColors.red.withValues(alpha: 0.16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.restart_alt_rounded,
                              size: 20,
                              color: BrandColors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            Translations.t(
                              'nyResetTitle',
                              context,
                              'Сбросить ивент?',
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: Weights.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      Translations.t(
                        'nyResetBody',
                        context,
                        'Все собранные шапки и подарок исчезнут навсегда.',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: PressScale(
                            // Отдача нарочно СЛАБАЯ (0.97) и мягкая на
                            // отпускании: на окне сброса прежний заметный
                            // «провал» кнопки читался лишней суетой.
                            pressedScale: 0.97,
                            duration: const Duration(milliseconds: 180),
                            releaseDuration: const Duration(milliseconds: 300),
                            child: TextButton(
                              onPressed: onCancel,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: const StadiumBorder(),
                              ),
                              child: Text(Translations.cancelOf(context)),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: PressScale(
                            pressedScale: 0.97,
                            duration: const Duration(milliseconds: 180),
                            releaseDuration: const Duration(milliseconds: 300),
                            child: FilledButton(
                              onPressed: onConfirm,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 46),
                                shape: const StadiumBorder(),
                                // Кнопка подтверждения — в брендовом алом, а не
                                // в сиреневом `primary`: на дефолтной палитре
                                // она читалась чужеродной синей плашкой.
                                backgroundColor: Color.lerp(
                                  BrandColors.red,
                                  cs.primary,
                                  0.18,
                                ),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                Translations.t(
                                  'nyResetConfirm',
                                  context,
                                  'Сбросить',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
