import 'dart:math';
import '../services/haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/nutrition_service.dart';
import '../l10n/translations.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../utils/context_menu.dart';
import '../utils/snackbar.dart';

// import '../utils/smooth_refresh.dart'; (removed, no longer used)

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final _service = NutritionService();
  final _calCtrl = TextEditingController();
  final _mealCtrl = TextEditingController();
  final Map<String, DateTime> _addedAt = {};
  bool _loaded = false; // Первая загрузка завершена — кнопка не «мигает»

  @override
  void initState() {
    super.initState();
    // Гарантия: клавиатура НЕ выскакивает сама при входе на экран.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
    _service.load().whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _mealCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMeal() async {
    final cals = int.tryParse(_calCtrl.text) ?? 0;
    final name = _mealCtrl.text.trim();
    if (name.isEmpty || cals <= 0) {
      if (mounted)
        showBeautifulSnackBar(
          context,
          message: Translations.t('fillAllFields', context),
          icon: Icons.error_outlined,
          iconColor: Colors.red,
        );
      return;
    }
    if (cals > 10000) {
      if (mounted)
        showBeautifulSnackBar(
          context,
          message: Translations.t('maxCalPerMeal', context),
          icon: Icons.warning_amber_outlined,
          iconColor: Colors.orange,
        );
      return;
    }
    final totalCals = _service.totalCalories;
    if (totalCals + cals > 10000) {
      if (mounted)
        showBeautifulSnackBar(
          context,
          message: Translations.t('maxCal', context),
          icon: Icons.warning_amber_outlined,
          iconColor: Colors.orange,
        );
      return;
    }
    final meal = Meal(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      calories: cals,
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
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _service.add(meal);
      if (mounted)
        showBeautifulSnackBar(
          context,
          message: Translations.t('mealAdded', context),
          icon: Icons.check_circle_outlined,
          iconColor: Colors.green,
        );
    } catch (e) {
      if (mounted)
        showBeautifulSnackBar(
          context,
          message: 'Error adding meal: $e',
          icon: Icons.error_outlined,
          iconColor: Colors.red,
        );
    }
    _calCtrl.clear();
    _mealCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final totalCals = _service.totalCalories;
        final meals = _service.meals;

        // Единый ListView вместо Column с вложенным ListView: вложенный
        // вертикальный список внутри Column получает unbounded height и
        // роняет экран при первой добавленной еде (баг «приёмы пищи не
        // добавляются»). Один скролл — и добавление, и история, и
        // pull-to-refresh работают как надо.
        final bodyContent = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _animatedStat(
                      Translations.t('calories', context),
                      totalCals,
                      10000,
                      theme,
                    ),
                    _animatedStat(
                      Translations.t('meals', context),
                      _service.meals.length,
                      20,
                      theme,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildTipsRow(context, theme),
            const SizedBox(height: 16),
            TextField(
              magnifierConfiguration: TextMagnifierConfiguration.disabled,
              controller: _mealCtrl,
              contextMenuBuilder: minimalContextMenuBuilder,
              maxLength: 100,
              buildCounter: smoothCharCounterBuilder,
              decoration: InputDecoration(
                labelText: Translations.t('addMeal', context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              magnifierConfiguration: TextMagnifierConfiguration.disabled,
              controller: _calCtrl,
              contextMenuBuilder: minimalContextMenuBuilder,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: InputDecoration(
                labelText: Translations.t('calories', context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Пока первая загрузка не завершена — не даём кнопке «мигать»
            // (сначала активная на нуле, потом гаснет на реальных данных).
            // Плавный fade вместо резкого появления.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _loaded
                  ? FilledButton(
                      key: const ValueKey('add_meal_loaded'),
                      onPressed: _service.totalCalories >= 10000
                          ? null
                          : _addMeal,
                      child: Text(Translations.t('add', context)),
                    )
                  : const SizedBox(
                      key: ValueKey('add_meal_loading'),
                      height: 48,
                      width: double.infinity,
                    ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: !_loaded
                  ? const SizedBox(key: ValueKey('meals_loading'))
                  : meals.isEmpty
                  ? Center(
                      key: const ValueKey('meals_empty'),
                      child: Text(Translations.t('noMeals', context)),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('meals_history'),
                      child: _buildHistory(context, theme, meals),
                    ),
            ),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(Translations.t('nutrition', context)),
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
      if (diff >= 0 && diff < 7) {
        final key = mDay;
        groups.putIfAbsent(key, () => []).add(m);
      }
    }
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    if (sortedKeys.isEmpty || meals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: Text(Translations.t('noMeals', context))),
      );
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

    Color _dayAccent(DateTime day) {
      final dayOfYear = (day.difference(DateTime(day.year, 1, 1)).inDays % 366);
      int seed = dayOfYear * 9301 + 49297;
      seed = (seed ^ (seed << 13)) & 0x7fffffff;
      if (seed < 0) seed = -seed;
      return accentColors[seed % accentColors.length];
    }

    IconData _mealIcon(String name) {
      final lower = name.toLowerCase();
      if (lower.contains('салат') ||
          lower.contains('овощ') ||
          lower.contains('salad') ||
          lower.contains('veg'))
        return Icons.eco_outlined;
      if (lower.contains('мяс') ||
          lower.contains('meat') ||
          lower.contains('куриц') ||
          lower.contains('говядин'))
        return Icons.set_meal_outlined;
      if (lower.contains('рыб') ||
          lower.contains('рыba') ||
          lower.contains('fish'))
        return Icons.water_outlined;
      if (lower.contains('суп') ||
          lower.contains('борщ') ||
          lower.contains('soup'))
        return Icons.soup_kitchen_outlined;
      if (lower.contains('хлеб') ||
          lower.contains('bread') ||
          lower.contains('тост'))
        return Icons.bakery_dining_outlined;
      if (lower.contains('фрукт') ||
          lower.contains('ягод') ||
          lower.contains('фрукт') ||
          lower.contains('fruit'))
        return Icons.apple_outlined;
      if (lower.contains('каш') ||
          lower.contains('овсян') ||
          lower.contains('porridge'))
        return Icons.breakfast_dining_outlined;
      if (lower.contains('пицц') ||
          lower.contains('бургер') ||
          lower.contains('fast'))
        return Icons.lunch_dining_outlined;
      if (lower.contains('печен') ||
          lower.contains('торт') ||
          lower.contains('cake') ||
          lower.contains('десерт'))
        return Icons.cake_outlined;
      if (lower.contains('яйц') || lower.contains('egg'))
        return Icons.egg_outlined;
      if (lower.contains('молоч') ||
          lower.contains('творог') ||
          lower.contains('milk') ||
          lower.contains('yogurt'))
        return Icons.local_drink_outlined;
      return Icons.fastfood_outlined;
    }

    // История рендерится как обычная Column — экран скроллит единый
    // внешний ListView (приёмов не больше 20, ленивость не нужна).
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
        dayMeals.map((meal) {
          final dayAccent = _dayAccent(meal.date);
          final dayIcon = _mealIcon(meal.name);
          final time =
              '${meal.date.hour.toString().padLeft(2, '0')}:${meal.date.minute.toString().padLeft(2, '0')}';
          // Зазор между приёмами пищи (было вплотную — карточки
          // сливались).
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey(meal.id),
              movementDuration: const Duration(milliseconds: 320),
              resizeDuration: const Duration(milliseconds: 340),
              direction: DismissDirection.horizontal,
              // Свайп ВПРАВО → удалить: красный фон с корзиной.
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
                    const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                      size: 22,
                    ),
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
              // Свайп ВЛЕВО → закрепить/открепить: акцентный фон с булавкой.
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
                        child: Text(
                          Translations.t('delete', context, 'Удалить'),
                        ),
                      ),
                    ],
                  ),
                );
                return ok == true;
              },
              onDismissed: (dir) {
                if (dir == DismissDirection.startToEnd) {
                  // Сначала даём Dismissible доиграть анимацию сжатия,
                  // и только потом удаляем из модели — иначе список
                  // «прыгает» при резком исчезновении строки.
                  Future.delayed(const Duration(milliseconds: 220), () {
                    if (mounted) _service.remove(meal.id);
                  });
                }
              },
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  tween: _addedAt.containsKey(meal.id)
                      ? Tween(begin: 0.0, end: 1.0)
                      : Tween(begin: 1.0, end: 1.0),
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                  child: SmoothHover(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: dayAccent.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: dayAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(dayIcon, size: 22, color: dayAccent),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(meal.name)),
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
                                        color: dayAccent,
                                      )
                                    : const SizedBox(
                                        key: ValueKey('meal_unpinned'),
                                        width: 0,
                                      ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text('${meal.calories} kcal • $time'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: dayAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${meal.calories}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: dayAccent,
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
        }),
      );
      dayWidgets.add(const SizedBox(height: 16));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: dayWidgets,
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

  /// Счётчик с плавным «докручиванием» числа при изменении (TweenAnimationBuilder
  /// сам стартует от текущего значения к новому).
  Widget _animatedStat(String label, int value, int max, ThemeData theme) {
    // Компактные числа: и ЗНАЧЕНИЕ, и знаменатель. 10000 → «10k»,
    // 1234 → «1.2k». При анимации число «растёт» плавно и форматируется
    // каждый кадр, так что переход через 1000 тоже плавный.
    final maxLabel = _compactCals(max.toDouble());
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(
            '${_compactCals(v)} / $maxLabel',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// 1234 → «1.2k», 10000 → «10k», 999 → «999». Плавно растёт с анимацией.
  static String _compactCals(double v) {
    if (v >= 10000) return '${(v / 1000).round()}k';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }
}
