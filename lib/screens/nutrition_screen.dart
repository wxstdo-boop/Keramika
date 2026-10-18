import 'dart:math';
import '../services/haptics.dart';
import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../services/nutrition_service.dart';
import '../l10n/translations.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../utils/context_menu.dart';
import '../utils/snackbar.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/number_pad.dart';
import '../widgets/norm_sheet.dart';
import '../widgets/progress_ring.dart';
import '../widgets/nutrition_trends.dart';
import '../widgets/press_scale.dart';
import '../widgets/rolling_counter.dart';

// import '../utils/smooth_refresh.dart'; (removed, no longer used)

/// Какое из числовых полей редактирует встроенная клавиатура.
enum _PadField { calories, water }

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen>
    with SingleTickerProviderStateMixin {
  final _service = NutritionService();
  final _calCtrl = WideDashController();
  final _mealCtrl = WideDashController();
  final _waterCtrl = WideDashController();
  final Map<String, DateTime> _addedAt = {};
  bool _loaded = false; // Первая загрузка завершена — кнопка не «мигает»

  /// Поле, открытое под встроенной клавиатурой, и сама открыта ли панель.
  /// `_pad` переживает закрытие: за 260 мс сложения панели её содержимое
  /// обязано оставаться валидным, иначе на половине анимации контроллер
  /// поменялся бы на чужой.
  _PadField _pad = _PadField.calories;
  bool _padOpen = false;

  /// Единый драйвер «въезда» экрана: карточки проявляются и опускаются на
  /// место ОДНОЙ волной с общим контроллером, а не набором конкурирующих
  /// анимаций высоты. Раньше над блоком истории висели Column+ClipRect+
  /// heightFactor СВЕРХУ AnimatedSize — две анимации высоты гонялись друг за
  /// другом, и при входе/добавлении приёма блок дёргался. Теперь высоту
  /// меняет только AnimatedSize, а въезд — это opacity+сдвиг, высоту не
  /// трогает вообще.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void initState() {
    super.initState();
    // Гарантия: клавиатура НЕ выскакивает сама при входе на экран.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      // «Въезд» экрана: запускаем после первого кадра, чтобы элементы уже
      // были в дереве и сдвиг читался как движение, а не как скачок.
      if (mounted) _enter.forward();
    });
    _service.load().whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _calCtrl.dispose();
    _mealCtrl.dispose();
    _waterCtrl.dispose();
    super.dispose();
  }

  /// Обёртка «въезда»: [slot] — порядковый номер карточки. Каждый следующий
  /// элемент стартует чуть позже предыдущего (общее окно 320 мс), проявляется
  /// из прозрачного и опускается на место. Высоту не меняет — только paint,
  /// поэтому AnimatedSize истории остаётся единственным хозяином layout.
  Widget _reveal(int slot, Widget child) {
    return AnimatedBuilder(
      animation: _enter,
      builder: (context, _) {
        // Окно старта: первые 55% прогресса раздает старты по слотам.
        final total = 10;
        final start = (slot / total).clamp(0.0, 0.55);
        final t = ((_enter.value - start) / 0.45).clamp(0.0, 1.0);
        if (t <= 0.0) {
          return Opacity(opacity: 0, child: child);
        }
        final eased = Curves.easeOutCubic.transform(t);
        return Opacity(
          opacity: eased,
          child: Transform.translate(
            // 12 px хода: заметно, но без «прыжка» на слабом GPU.
            offset: Offset(0, (1 - eased) * 12),
            child: child,
          ),
        );
      },
    );
  }

  /// Открыть/закрыть встроенную клавиатуру над нужным полем.
  void _showPad(_PadField field) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_padOpen && _pad == field) {
      setState(() => _padOpen = false);
      return;
    }
    Haptics.select();
    setState(() {
      _pad = field;
      _padOpen = true;
    });
  }

  void _hidePad() {
    if (!_padOpen) return;
    setState(() => _padOpen = false);
  }

  TextEditingController _padController() =>
      _pad == _PadField.water ? _waterCtrl : _calCtrl;

  int get _padMaxDigits => _pad == _PadField.water ? 4 : 5;

  Future<void> _addMeal() async {
    final cals = int.tryParse(_calCtrl.text) ?? 0;
    final water = int.tryParse(_waterCtrl.text) ?? 0;
    final name = _mealCtrl.text.trim();
    // Название нужно для калорийной записи (по нему считается категория и БЖУ).
    // Отдельная запись без калорий и есть «выпил воды».
    if (cals > 0 && name.isEmpty) {
      _complain(Translations.t('fillAllFields', context), Icons.error_outlined);
      return;
    }
    if (name.isEmpty && water <= 0) {
      _complain(
        Translations.t('needNameOrWater', context, 'Укажите блюдо или воду'),
        Icons.error_outlined,
      );
      return;
    }
    if (cals > 10000) {
      _complain(Translations.t('maxCalPerMeal', context), Icons.warning_amber);
      return;
    }
    if (water > kMaxWaterPerMeal) {
      _complain(
        Translations.t('maxWaterPerMeal', context),
        Icons.warning_amber,
      );
      return;
    }
    // Потолок считается ПО СЕГОДНЯШНЕМУ дню: суточная норма суточная, а не
    // накопленная за всё окно истории.
    if (_service.todayCalories + cals > kMaxCalorieNorm) {
      _complain(Translations.t('maxCal', context), Icons.warning_amber);
      return;
    }
    final meal = Meal(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      calories: cals,
      water: water,
      date: DateTime.now(),
    );
    _addedAt[meal.id] = DateTime.now();
    // Автоматически убираем метку анимации через секунду.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _addedAt.remove(meal.id));
      }
    });
    // Клавиатура не должна оставаться открытой после добавления —
    // убираем фокус с полей ввода сразу после успешного сохранения.
    _hidePad();
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _service.add(meal);
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('mealAdded', context),
          icon: Icons.check_circle_outlined,
          iconColor: Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: 'Error adding meal: $e',
          icon: Icons.error_outlined,
          iconColor: Colors.red,
        );
      }
    }
    _calCtrl.clear();
    _mealCtrl.clear();
    _waterCtrl.clear();
  }

  void _complain(String message, IconData icon) {
    if (!mounted) return;
    showBeautifulSnackBar(
      context,
      message: message,
      icon: icon,
      iconColor: icon == Icons.error_outlined ? Colors.red : Colors.orange,
    );
  }

  /// Лист настройки личной суточной нормы. Открывается тапом по кольцу.
  Future<void> _openNormSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _hidePad();
    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => NormSheet(service: _service),
    );
    if (saved == null || !mounted) return;
    showBeautifulSnackBar(
      context,
      message: Translations.t('normSaved', context, 'Норма сохранена'),
      icon: Icons.check_circle_outline,
      iconColor: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final meals = _service.meals;

        // Единый ListView вместо Column с вложенным ListView: вложенный
        // вертикальный список внутри Column получает unbounded height и
        // роняет экран при первой добавленной еде (баг «приёмы пищи не
        // добавляются»). Один скролл — и добавление, и история, и
        // pull-to-refresh работают как надо.
        //
        // «Въезд» карточек — общий [_reveal] по слоту. Он меняет только paint
        // (opacity+сдвиг), а высоту блока истории по-прежнему владеет
        // единственный AnimatedSize ниже.
        final bodyContent = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _reveal(0, _goalCard(context, theme)),
            const SizedBox(height: 16),
            _reveal(1, _buildTipsRow(context, theme)),
            const SizedBox(height: 16),
            _reveal(2, _nameField(theme)),
            const SizedBox(height: 8),
            _reveal(
              3,
              _numberField(
                theme,
                controller: _calCtrl,
                field: _PadField.calories,
                label: Translations.t('calories', context),
                unit: Translations.t('kcalShort', context, 'ккал'),
              ),
            ),
            const SizedBox(height: 8),
            _reveal(
              4,
              _numberField(
                theme,
                controller: _waterCtrl,
                field: _PadField.water,
                label: Translations.t('waterField', context, 'Вода'),
                unit: Translations.t('mlShort', context, 'мл'),
              ),
            ),
            _reveal(5, _padPanel(theme)),
            const SizedBox(height: 16),
            // Пока первая загрузка не завершена — не даём кнопке «мигать»
            // (сначала активная на нуле, потом гаснет на реальных данных).
            // Плавный fade вместо резкого появления.
            _reveal(
              6,
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _loaded
                    // Кнопка всегда активна: при потолке калорий за день нельзя
                    // было записать и воду, а это отдельная запись без калорий.
                    // Проверка дня живёт в [_addMeal] и объясняет отказ вслух.
                    ? PressScale(
                        key: const ValueKey('add_meal_loaded'),
                        // Мягкое вдавливание вместо мгновенного «щелчка»
                        // встроенного splash: палец чувствует кнопку, а
                        // действие остаётся у самой кнопки. Нажатие медленнее
                        // (300 мс) и отпускание ещё мягче (360 мс) — кнопка
                        // «уходит» под палец, а не щёлкает.
                        pressedScale: 0.97,
                        duration: const Duration(milliseconds: 300),
                        releaseDuration: const Duration(milliseconds: 360),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: _addMeal,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: Text(Translations.t('add', context)),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('add_meal_loading'),
                        height: 52,
                        width: double.infinity,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            // AnimatedSize — ЕДИНСТВЕННЫЙ механизм, который меняет высоту
            // блока истории. Так добавление приёма пищи, удаление и уход
            // заголовка «Сегодня» (вместе с последней записью дня) идут
            // одной плавной волной, а не двумя спорящими анимациями.
            _reveal(
              7,
              AnimatedSize(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  // Свое расположение: уходящий ребёнок кладём Positioned.
                  // У обычного AnimatedSwitcher оба ребёнка лежат в Stack как
                  // обычные дети — стек раздувается до МАКСИМАЛЬНОЙ высоты, и
                  // AnimatedSize над ним не видит промежуточных значений:
                  // высота прыгала к финальной, а текст «Пока нет приёмов пищи»
                  // дёргался вниз/вверх. Positioned не участвует в размере стека,
                  // поэтому высота = текущему ребёнку, и её ведёт AnimatedSize.
                  layoutBuilder: (child, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      for (final c in previous)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(child: c),
                        ),
                      ?child,
                    ],
                  ),
                  child: !_loaded
                      ? const SizedBox(key: ValueKey('meals_loading'))
                      : meals.isEmpty
                      ? const _EmptyMeals()
                      : KeyedSubtree(
                          key: const ValueKey('meals_history'),
                          child: _buildHistory(context, theme, meals),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _reveal(8, _trendsCard(theme)),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(Translations.t('nutrition', context)),
            leading: const BackButtonTooltip(),
            centerTitle: true,
          ),
          resizeToAvoidBottomInset: false,
          body: SmoothKeyboardBody(
            child: RefreshIndicator(
              onRefresh: () async {
                await _service.load();
              },
              child: bodyContent,
            ),
          ),
        );
      },
    );
  }

  /// Красивая обводка-кольцо вокруг карточки: тонкий градиент от акцента к
  /// третичному цвету темы.
  ///
  /// Именно кольцо, а не `BorderSide`: у рамки один цвет на все четыре
  /// стороны, и на большой карточке она читается как «наклейка». Градиент
  /// даёт мягкий перелив по краю, который не спорит с содержимым.
  /// Тень тоже здесь: две тени (своя у Card и у кольца) давали грязный
  /// ореол по периметру.
  Widget _ringed({
    required Widget child,
    required Color accent,
    double radius = 20,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: dark ? 0.60 : 0.42),
            accent.withValues(alpha: dark ? 0.12 : 0.10),
            cs.tertiary.withValues(alpha: dark ? 0.45 : 0.28),
          ],
          stops: const <double>[0, 0.55, 1],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.34 : 0.07),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1.3),
      child: child,
    );
  }

  /// Радиус внутренней карточки: на толщину кольца меньше внешнего, иначе
  /// углы не совпадают и в стыке видна щель.
  static const double _ringInner = 20 - 1.3;

  /// Карточка цели: кольцо «сегодня / моя норма» + приёмы, вода и полосы
  /// БЖУ. Тап по ней открывает настройку нормы.
  Widget _goalCard(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final today = _service.todayCalories;
    final norm = _service.norm;
    final macros = _service.todayMacros;
    final over = today > norm;
    return _ringed(
      accent: cs.primary,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_ringInner),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openNormSheet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ProgressRing(
                      value: today.toDouble(),
                      target: norm.toDouble(),
                      color: cs.primary,
                      trackColor: cs.surfaceContainerHighest,
                      overColor: cs.tertiary,
                      size: 112,
                      thickness: 10,
                      centerBuilder: (context, shown) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Число внутри кольца строится от промежуточного
                          // значения анимации кольца, поэтому оно крутится
                          // синхронно с дугой. Ширина закреплена под пять
                          // разрядов: без этого при переходе «999 → 1000»
                          // центрированное число съезжало в сторону.
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: over ? 1 : 0,
                              end: over ? 1 : 0,
                            ),
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            builder: (context, overT, _) => RollingCounter(
                              value: shown,
                              sample: '99999',
                              alignment: Alignment.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Color.lerp(
                                  cs.primary,
                                  cs.tertiary,
                                  overT,
                                ),
                                height: 1,
                              ),
                            ),
                          ),
                          // Лимит под числом тоже «докручивается»: при смене
                          // нормы цифра перетекает, а не перескакивает.
                          // Префикс «из» — обычный текст, число — барабан.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${Translations.t('ofPrefix', context, 'из')} ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: norm.toDouble(),
                                  end: norm.toDouble(),
                                ),
                                duration: const Duration(milliseconds: 700),
                                curve: Curves.easeOutCubic,
                                builder: (context, shownNorm, _) =>
                                    RollingCounter(
                                      value: shownNorm,
                                      sample: '99999',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Translations.t(
                              'calorieNorm',
                              context,
                              'Суточная норма',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            Translations.tapToChangeOf(context),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _statLine(
                            theme,
                            Translations.t(
                              'mealsToday',
                              context,
                              'Приёмы сегодня',
                            ),
                            _service.todayMealsCount,
                            '',
                          ),
                          _statLine(
                            theme,
                            Translations.t('water', context, 'Вода'),
                            _service.todayWater,
                            Translations.t('mlShort', context, 'мл'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _macroRow(theme, macros, today),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Строка «подпись — число — единица». Невидимый «самый широкий» текст
  /// держит ширину, поэтому счётчик не толкает соседей при смене значения.
  Widget _statLine(ThemeData theme, String label, int value, String unit) {
    final style = (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              Opacity(opacity: 0, child: Text('99999', style: style)),
              // Значение приходит из сервиса рывком (добавили приём пищи) —
              // счётчик докручивается до него сам, длиннее обычного: цифры
              // должны перетекать, а не успевать «щёлкнуть».
              AnimatedCounter(
                value: value.toDouble(),
                duration: const Duration(milliseconds: 640),
                style: style,
              ),
            ],
          ),
          if (unit.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              unit,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Три полосы макросов: доля каждого нутриента в сегодняшних калориях.
  Widget _macroRow(ThemeData theme, MealMacros macros, int kcal) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: _macroBar(
            theme,
            Translations.t('macroP', context, 'Белки'),
            macros.protein,
            4,
            kcal,
            cs.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _macroBar(
            theme,
            Translations.t('macroF', context, 'Жиры'),
            macros.fat,
            9,
            kcal,
            cs.tertiary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _macroBar(
            theme,
            Translations.t('macroC', context, 'Углеводы'),
            macros.carbs,
            4,
            kcal,
            cs.secondary,
          ),
        ),
      ],
    );
  }

  Widget _macroBar(
    ThemeData theme,
    String label,
    int grams,
    double kcalPerGram,
    int totalKcal,
    Color color,
  ) {
    final cs = theme.colorScheme;
    final fraction = totalKcal <= 0
        ? 0.0
        : (grams * kcalPerGram / totalKcal).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            AnimatedCounter(
              value: grams.toDouble(),
              duration: const Duration(milliseconds: 640),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              ' г',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: fraction),
          duration: const Duration(milliseconds: 560),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Поле названия блюда — обычное, с системной клавиатурой.
  Widget _nameField(ThemeData theme) {
    return SmoothTyping(
      controller: _mealCtrl,
      builder: (style) => TextField(
        style: style,
        cursorOpacityAnimates: true,
        magnifierConfiguration: TextMagnifierConfiguration.disabled,
        controller: _mealCtrl,
        contextMenuBuilder: minimalContextMenuBuilder,
        maxLength: 100,
        inputFormatters: [WideDashFormatter()],
        enableSuggestions: false,
        autocorrect: false,
        buildCounter: smoothCharCounterBuilder,
        // Системная клавиатура текста и встроенная панель цифр на одном экране
        // выглядят как две клавиатуры: при фокусе на названии панель сворачиваем.
        onTap: _hidePad,
        decoration: InputDecoration(
          labelText: Translations.t('addMeal', context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  /// Числовое поле: readOnly, по тапу открывает встроенную клавиатуру.
  /// Потолок цифр держит [NumberPad] (`_padMaxDigits`), а не `maxLength`
  /// поля: `maxLength` рисовал под каждым полем счётчик «0/5» и добавлял
  /// два лишних ряда высоты.
  Widget _numberField(
    ThemeData theme, {
    required TextEditingController controller,
    required _PadField field,
    required String label,
    required String unit,
  }) {
    final cs = theme.colorScheme;
    final active = _padOpen && _pad == field;
    return SmoothTyping(
      // Плавность цифр ВЕРНУЛИ: отключили только «призраков» (гаснущие копии
      // удалённых цифр). Заедание было именно на них — при зажатом бэкспейсе
      // значения летят ~20 раз в секунду, и на каждый кадр троился десяток
      // новых TextPainter-ов. Появление цифр по-прежнему плавное, а удаление
      // мгновенное и ровное.
      enabled: true,
      ghosts: false,
      controller: controller,
      builder: (style) => TextField(
        style: style,
        cursorOpacityAnimates: true,
        magnifierConfiguration: TextMagnifierConfiguration.disabled,
        controller: controller,
        readOnly: true,
        showCursor: false,
        contextMenuBuilder: minimalContextMenuBuilder,
        onTap: () => _showPad(field),
        decoration: InputDecoration(
          labelText: label,
          // Единица и иконка — в ОДНОМ слоте суффикса. Раньше единица жила в
          // `suffixText`, а иконка в `suffixIcon`, и InputDecorator на части
          // кадров перестраивал их порознь — «ккал»/«мл» то появлялись, то
          // пропадали. Теперь это один Row с фиксированными ограничениями:
          // слот всегда одной ширины, обе части видны всегда.
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unit,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.dialpad_rounded,
                  size: 22,
                  color: active
                      ? cs.primary
                      : cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 40,
            maxWidth: 140,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: active ? cs.primary : cs.outline.withValues(alpha: 0.6),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: cs.primary, width: 1.6),
          ),
        ),
      ),
    );
  }

  /// Встроенная цифровая панель. Раскрывается `Align(heightFactor:)` — это
  /// анимация высоты, которая честно участвует в layout, поэтому поля и
  /// кнопка под ней расходятся плавно, а не перескакивают.
  Widget _padPanel(ThemeData theme) {
    final cs = theme.colorScheme;
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _padOpen ? 1 : 0),
          // Раскрытие панели: высота и прозрачность идут одной волной с
          // мягким входом и выходом. 260 мс «easeOut» начинались рывком и
          // обрывались на конце; easeInOut заметно спокойнее.
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOutCubic,
          builder: (context, v, child) => Align(
            alignment: Alignment.topCenter,
            heightFactor: v,
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
              ),
              child: NumberPad(
                // `_pad` живёт и во время сложения панели, поэтому
                // контроллер всегда валиден.
                controller: _padController(),
                maxDigits: _padMaxDigits,
                onAppendLimit: () => _complain(
                  Translations.t('maxDigitsHit', context, 'Дальше нельзя'),
                  Icons.warning_amber_rounded,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Карточка трендов. Значение сегодняшнего столбика приходит уже
  /// «докрученным», чтобы не плодить тикеров на каждый день графика.
  Widget _trendsCard(ThemeData theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _service.todayCalories.toDouble()),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => _ringed(
        accent: theme.colorScheme.secondary,
        child: NutritionTrends(
          days: _service.days,
          norm: _service.norm,
          todayCalories: shown,
          elevation: 0,
          radius: _ringInner,
        ),
      ),
    );
  }

  Widget _buildHistory(
    BuildContext context,
    ThemeData theme,
    List<Meal> meals,
  ) {
    final today = DateTime.now();
    final groups = <DateTime, List<Meal>>{};
    for (final m in meals) {
      final day = DateTime(today.year, today.month, today.day);
      final mDay = DateTime(m.date.year, m.date.month, m.date.day);
      final diff = day.difference(mDay).inDays;
      // Окно задаёт сервис: с подарком 12-го дня оно шире базового.
      if (diff >= 0 && diff < _service.historyDays) {
        groups.putIfAbsent(mDay, () => []).add(m);
      }
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    if (sortedKeys.isEmpty || meals.isEmpty) {
      return const _EmptyMeals();
    }

    final accentColors = <Color>[
      Colors.deepOrange,
      Colors.purple,
      Colors.blue,
      Colors.teal,
      Colors.indigo,
      Colors.green,
      Colors.orange,
      Colors.pink,
      Colors.cyan,
      Colors.amber,
    ];

    Color dayAccent(DateTime day) {
      final dayOfYear = (day.difference(DateTime(day.year, 1, 1)).inDays % 366);
      int seed = dayOfYear * 9301 + 49297;
      seed = (seed ^ (seed << 13)) & 0x7fffffff;
      if (seed < 0) seed = -seed;
      return accentColors[seed % accentColors.length];
    }

    // История рендерится как обычная Column — экран скроллит единый
    // внешний ListView (ленивость не нужна).
    final dayWidgets = <Widget>[];
    for (final day in sortedKeys) {
      final dayMeals = groups[day]!
        ..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.date.compareTo(a.date);
        });
      final diff = today.difference(day).inDays;
      final label = diff == 0
          ? Translations.t('today', context)
          : diff == 1
          ? Translations.t('yesterday', context)
          : '${day.day}/${day.month}/${day.year}';

      dayWidgets.add(
        Padding(
          key: ValueKey('day_$diff'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
      dayWidgets.addAll(
        dayMeals.map((meal) => _mealCard(context, theme, meal, dayAccent)),
      );
      dayWidgets.add(const SizedBox(height: 16));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: dayWidgets,
    );
  }

  /// Одна карточка приёма пищи со свайпами «удалить» и «закрепить».
  Widget _mealCard(
    BuildContext context,
    ThemeData theme,
    Meal meal,
    Color Function(DateTime) dayAccent,
  ) {
    final accent = dayAccent(meal.date);
    final time =
        '${meal.date.hour.toString().padLeft(2, '0')}:${meal.date.minute.toString().padLeft(2, '0')}';
    final macros = meal.macros;
    final water = meal.water;
    final subtitle = meal.isWaterOnly
        ? '$water ${Translations.t('mlShort', context, 'мл')} • $time'
        : '${Translations.t('macroPSingle', context, 'Б')} ${macros.protein}'
              ' · ${Translations.t('macroFSingle', context, 'Ж')} ${macros.fat}'
              ' · ${Translations.t('macroCSingle', context, 'У')} ${macros.carbs}'
              '${water > 0 ? ' · $water мл' : ''}'
              ' • ${meal.calories} ${Translations.t('kcalShort', context, 'ккал')}'
              ' • $time';
    final isJustAdded = _addedAt.containsKey(meal.id);
    // Зазор между приёмами пищи живёт ВНУТРИ Dismissible: `resizeDuration`
    // анимирует только собственное дитя, и раньше на месте удалённой строки
    // оставались эти 10 px, которые снимались одним кадром после конца
    // сжатия — «следующий чуть дёргается вверх».
    // Ключ на ВСЕЙ ячейке, а не только на Dismissible: иначе при вставке
    // новой карточки соседи сдвигаются по позиции, их состояние анимации
    // переезжает на чужой приём пищи, и «раскрытие» ловили уже добавленные
    // карточки.
    return Dismissible(
      key: ValueKey('slot_${meal.id}'),
      movementDuration: const Duration(milliseconds: 320),
      // Своё сжатие строки выключено намеренно. Пока оно было, высоту
      // анимировали ДВА механизма сразу — Dismissible и AnimatedSize над
      // блоком истории. Место освобождалось рывком после того, как оба
      // доиграют. Теперь карточка уезжает за край, а её место схлопывает
      // только AnimatedSize — одна анимация высоты на экране.
      resizeDuration: null,
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              Translations.deleteOf(context),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 190),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Text(
                meal.pinned
                    ? Translations.t('unpinMeal', context)
                    : Translations.t('pinMeal', context),
                key: ValueKey('pin_status_${meal.pinned}'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 190),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                meal.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                key: ValueKey('pin_icon_${meal.pinned}'),
                color: Colors.white,
                size: 22,
              ),
            ),
          ],
        ),
      ),
      // Перед удалением приёма пищи — мягкий диалог
      // «Удалить приём пищи? Отменить / Удалить».
      confirmDismiss: (dir) async {
        // Свайп — это жест, клавиатура после него возвращаться не должна.
        FocusManager.instance.primaryFocus?.unfocus();
        _hidePad();
        if (dir == DismissDirection.endToStart) {
          Haptics.medium();
          _service.togglePin(meal.id);
          return false;
        }
        // Защита от случайного удаления жестом: требуем явного подтверждения.
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Translations.t(
                      'deleteMealConfirmTitle',
                      context,
                      'Удалить приём пищи?',
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              Translations.t(
                'deleteMealConfirmBody',
                context,
                'Этот приём пищи будет удалён. Действие нельзя отменить.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(Translations.cancelOf(context)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(Translations.t('delete', context, 'Удалить')),
              ),
            ],
          ),
        );
        return ok == true;
      },
      onDismissed: (dir) {
        if (dir == DismissDirection.startToEnd) {
          // Убираем приём пищи СРАЗУ: карточка уже уехала за край, а её
          // место схлопывает AnimatedSize — плавно и в том же кадре, где
          // модель перестала о ней знать. Раньше удаление откладывалось на
          // 360 мс «до конца сжатия»; место при этом снималось одним кадром
          // уже после того, как сжатие отыграло, — это и был прыжок.
          _service.remove(meal.id);
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            // Только новая запись анимируется 380 мс. У истории начальное и
            // конечное значения равны, поэтому долгий ticker ей не нужен.
            duration: isJustAdded
                ? const Duration(milliseconds: 380)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            tween: isJustAdded
                ? Tween(begin: 0.0, end: 1.0)
                : Tween(begin: 1.0, end: 1.0),
            // Высоту карточки здесь НЕ анимируем: её ведёт единственный
            // AnimatedSize над всем блоком истории. Две анимации высоты
            // одновременно (эта и AnimatedSize) гонялись друг за другом:
            // блок «догонял» раскрывающуюся карточку, и экран подрагивал.
            // Остались проявление и мягкий подъём — они не влияют на layout.
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 12),
                child: child,
              ),
            ),
            child: PressScale(
              // Приём пищи «вдавливается» — уменьшается, а не растёт:
              // раньше карточка на зажатии увеличивалась, и на плотном
              // списке это читалось как «наезд» на соседей.
              pressedScale: 0.982,
              duration: const Duration(milliseconds: 240),
              releaseDuration: const Duration(milliseconds: 340),
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: accent.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      meal.isWaterOnly
                          ? Icons.water_drop_outlined
                          : meal.kind.icon,
                      size: 22,
                      color: accent,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          meal.name.isEmpty
                              ? Translations.t('water', context, 'Вода')
                              : meal.name,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 210),
                        curve: Curves.easeOutCubic,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 190),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: animation,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                          child: meal.pinned
                              ? Icon(
                                  Icons.push_pin,
                                  key: const ValueKey('meal_pinned'),
                                  size: 16,
                                  color: accent,
                                )
                              : const SizedBox(
                                  key: ValueKey('meal_unpinned'),
                                  width: 0,
                                ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(subtitle),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      meal.isWaterOnly
                          ? '$water ${Translations.t('mlShort', context, 'мл')}'
                          : '${meal.calories}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: accent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTipsRow(BuildContext context, ThemeData theme) {
    final allTips = <Map<String, dynamic>>[
      {
        'icon': Icons.water_drop_outlined,
        'title': Translations.t('tipWaterTitle', context, 'Water first'),
        'body': Translations.t(
          'tipWaterBody',
          context,
          'Often thirst wears a hunger mask. Drink a glass of water and wait 10 minutes before refilling your plate.',
        ),
        'color': Colors.blue,
      },
      {
        'icon': Icons.cookie_outlined,
        'title': Translations.t('tipSugarTitle', context, 'Sugar shield'),
        'body': Translations.t(
          'tipSugarBody',
          context,
          'If it is sweet and packaged, it wants to stay in the store. Choose fruit, dark chocolate or water first.',
        ),
        'color': Colors.purple,
      },
      {
        'icon': Icons.apple_outlined,
        'title': Translations.t(
          'tipFruitCravingTitle',
          context,
          'Fruit > Sugar',
        ),
        'body': Translations.t(
          'tipFruitCravingBody',
          context,
          'An apple or berries satisfy the sweet tooth without the sugar spike.',
        ),
        'color': Colors.red,
      },
      {
        'icon': Icons.hourglass_top,
        'title': Translations.t('tipWaitTitle', context, '10-minute rule'),
        'body': Translations.t(
          'tipWaitBody',
          context,
          'Wait 10 minutes before giving in — in 70% of cases the craving passes.',
        ),
        'color': Colors.indigo,
      },
      {
        'icon': Icons.icecream_outlined,
        'title': Translations.t(
          'tipDarkChocolateTitle',
          context,
          'Dark chocolate',
        ),
        'body': Translations.t(
          'tipDarkChocolateBody',
          context,
          'Two squares of 85% dark chocolate satisfy the temptation without the guilt.',
        ),
        'color': Colors.brown,
      },
      {
        'icon': Icons.dining_outlined,
        'title': Translations.t(
          'tipYogurtTitle',
          context,
          'Yogurt with berries',
        ),
        'body': Translations.t(
          'tipYogurtBody',
          context,
          'Plain yogurt with berries is a dessert without false shame that feels indulgent.',
        ),
        'color': Colors.teal,
      },
      {
        'icon': Icons.soup_kitchen_outlined,
        'title': Translations.t('tipWarmDrinkTitle', context, 'Hot drink'),
        'body': Translations.t(
          'tipWarmDrinkBody',
          context,
          'A warm sugar-free drink calms sweet cravings.',
        ),
        'color': Colors.orange,
      },
      {
        'icon': Icons.favorite_outline,
        'title': Translations.t(
          'tipReplaceTitle',
          context,
          'Replace, do not ban',
        ),
        'body': Translations.t(
          'tipReplaceBody',
          context,
          'The brain resists bans; it reacts better to replacement.',
        ),
        'color': Colors.pink,
      },
      {
        'icon': Icons.fastfood_outlined,
        'title': Translations.t(
          'tipOvereatTitle',
          context,
          'Do not eat to the max',
        ),
        'body': Translations.t(
          'tipOvereatBody',
          context,
          'Stop when you are 80% full. Your body needs comfort, not a second plate of leftovers.',
        ),
        'color': Colors.deepOrange,
      },
      {
        'icon': Icons.fitness_center_outlined,
        'title': Translations.t('tipProteinTitle', context, 'Protein anchor'),
        'body': Translations.t(
          'tipProteinBody',
          context,
          'Protein keeps you full longer. Add an egg, yogurt, or nuts to every meal and snacks will stop haunting you.',
        ),
        'color': Colors.teal,
      },
      {
        'icon': Icons.self_improvement_outlined,
        'title': Translations.t(
          'tipMindfulTitle',
          context,
          'Eat with awareness',
        ),
        'body': Translations.t(
          'tipMindfulBody',
          context,
          'Put the phone down and chew slowly. In 20 minutes your brain finally catches up with your stomach.',
        ),
        'color': Colors.indigo,
      },
      {
        'icon': Icons.bedtime_outlined,
        'title': Translations.t(
          'tipSleepTitle',
          context,
          'Sleep controls appetite',
        ),
        'body': Translations.t(
          'tipSleepBody',
          context,
          'Less than 7 hours spikes hunger hormones. Protect your sleep schedule and late-night cravings weaken.',
        ),
        'color': Colors.indigoAccent,
      },
      {
        'icon': Icons.eco_outlined,
        'title': Translations.t('tipVeggiesTitle', context, 'Veggies first'),
        'body': Translations.t(
          'tipVeggiesBody',
          context,
          'Start every meal with vegetables or salad. Fiber fills you up before the heavier food even reaches the table.',
        ),
        'color': Colors.green,
      },
      {
        'icon': Icons.restaurant_menu_outlined,
        'title': Translations.t('tipChewTitle', context, 'Chew count'),
        'body': Translations.t(
          'tipChewBody',
          context,
          'Try 20 chews per bite. It slows you down, improves digestion and naturally cuts portion size without suffering.',
        ),
        'color': Colors.orangeAccent,
      },
      {
        'icon': Icons.grass_outlined,
        'title': Translations.t('tipFiberTitle', context, 'Fiber beats hunger'),
        'body': Translations.t(
          'tipFiberBody',
          context,
          'Whole grains and vegetables keep you satisfied longer than refined carbs.',
        ),
        'color': Colors.lightGreen,
      },
      {
        'icon': Icons.shopping_cart_outlined,
        'title': Translations.t(
          'tipNoSnackTitle',
          context,
          'Skip the snack aisle',
        ),
        'body': Translations.t(
          'tipNoSnackBody',
          context,
          'If you are not hungry enough to eat an apple, you are probably bored or thirsty.',
        ),
        'color': Colors.orange,
      },
      {
        'icon': Icons.local_fire_department_outlined,
        'title': Translations.t('tipSpicesTitle', context, 'Spice it up'),
        'body': Translations.t(
          'tipSpicesBody',
          context,
          'Strong flavors signal satisfaction faster. Add herbs, chili, or citrus to slow down eating.',
        ),
        'color': Colors.redAccent,
      },
      {
        'icon': Icons.breakfast_dining_outlined,
        'title': Translations.t(
          'tipBreakfastTitle',
          context,
          'Breakfast anchor',
        ),
        'body': Translations.t(
          'tipBreakfastBody',
          context,
          'A protein-rich start prevents mid-morning crashes and random snacking.',
        ),
        'color': Colors.amber,
      },
      {
        'icon': Icons.dinner_dining_outlined,
        'title': Translations.t(
          'tipPortionTitle',
          context,
          'Smaller plate, same meal',
        ),
        'body': Translations.t(
          'tipPortionBody',
          context,
          'Visual cues trick the brain. Use a smaller plate and you will feel full with less food.',
        ),
        'color': Colors.deepPurpleAccent,
      },
      {
        'icon': Icons.wine_bar_outlined,
        'title': Translations.t(
          'tipAlcoholTitle',
          context,
          'Alcohol lowers brakes',
        ),
        'body': Translations.t(
          'tipAlcoholBody',
          context,
          'Even one drink reduces self-control and increases late-night food cravings.',
        ),
        'color': Colors.brown,
      },
      {
        'icon': Icons.psychology_outlined,
        'title': Translations.t(
          'tipMindfulHungerTitle',
          context,
          'Name your hunger',
        ),
        'body': Translations.t(
          'tipMindfulHungerBody',
          context,
          'Ask: is this real hunger, a craving, or emotional eating? Labeling it reduces the impulse.',
        ),
        'color': Colors.cyan,
      },
      {
        'icon': Icons.schedule_outlined,
        'title': Translations.t('tipConsistencyTitle', context, 'Same rhythm'),
        'body': Translations.t(
          'tipConsistencyBody',
          context,
          'Eating at regular times stabilizes blood sugar. Random meals confuse your metabolism.',
        ),
        'color': Colors.blueGrey,
      },
      {
        'icon': Icons.monitor_heart,
        'title': Translations.t(
          'tipStressSugarTitle',
          context,
          'Sweet vs Stress',
        ),
        'body': Translations.t(
          'tipStressSugarBody',
          context,
          'Stress spikes sugar cravings. Walk it off instead.',
        ),
        'color': Colors.cyan,
      },
      {
        'icon': Icons.directions_run,
        'title': Translations.t('tipWalkTitle', context, 'Take a walk'),
        'body': Translations.t(
          'tipWalkBody',
          context,
          'A 10-minute walk kills a craving faster than willpower.',
        ),
        'color': Colors.lime,
      },
      {
        'icon': Icons.coffee_outlined,
        'title': Translations.t('tipCoffeeTitle', context, 'Black coffee'),
        'body': Translations.t(
          'tipCoffeeBody',
          context,
          'One black coffee can kill sugar craving for 30-40 minutes.',
        ),
        'color': Colors.brown,
      },
      {
        'icon': Icons.ice_skating,
        'title': Translations.t('tipColdWaterTitle', context, 'Ice-cold water'),
        'body': Translations.t(
          'tipColdWaterBody',
          context,
          'A glass of ice water instantly resets mind and body — the cold shock breaks the craving loop.',
        ),
        'color': Colors.cyan,
      },
    ];

    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    final seed = dayOfYear * 9301 + 49297 + now.hour;
    final rng = Random(seed % 0x7fffffff);
    allTips.shuffle(rng);
    final tips = allTips.sublist(0, 8);

    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tips.length,
        padding: const EdgeInsets.only(right: 8),
        itemBuilder: (context, index) {
          final tip = tips[index];
          final tipIcon = tip['icon'] as IconData;
          final tipTitle = tip['title'] as String;
          final tipBody = tip['body'] as String;
          final tipColor = tip['color'] as Color;
          return Container(
            width: 300,
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.surface,
                  theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                ],
              ),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(tipIcon, size: 22, color: tipColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tipTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Text(
                      tipBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
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

/// Пустое состояние истории. Фиксированная высота нужна, чтобы переход
/// «список → пусто» был сложением высоты, а не телепортом текста.
class _EmptyMeals extends StatelessWidget {
  const _EmptyMeals();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Center(child: Text(Translations.t('noMeals', context))),
    );
  }
}
