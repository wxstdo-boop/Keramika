import 'package:flutter/material.dart';

/// Лёгкий набор дефолтных иконок для привычек и задач.
/// Полный список строится в HabitTaskIconList ниже, чтобы не дублировать
/// константы MaterialIcons в нескольких местах.
const List<IconData> habitTaskIcons = <IconData>[];

class HabitTaskIconList {
  static List<IconData> get all => _cached ??= _build();
  static List<IconData>? _cached;

  /// Иконки для сетки выбора: без дублей. `all` остаётся полным — по нему
  /// `iconDataForCodePoint` находит сохранённые иконки старых привычек.
  /// В сетке же убираем точные дубли (один и тот же codePoint) и визуальные
  /// близнецы (та же форма, но новый codePoint у новых версий глифов).
  static List<IconData> get picker => _pickerCached ??= _buildPicker();
  static List<IconData>? _pickerCached;

  static List<IconData> _buildPicker() {
    final skip = <int>{
      // Визуальные дубли: та же форма, что и у соседа, но другой codePoint.
      Icons.electric_bolt_outlined.codePoint, // ~ bolt_outlined
      Icons.work_outlined.codePoint, // ~ work_outline
      Icons.favorite_border_outlined.codePoint, // ~ favorite_outline
    };
    final seen = <int>{};
    final out = <IconData>[];
    for (final i in all) {
      if (skip.contains(i.codePoint)) continue;
      if (!seen.add(i.codePoint)) continue;
      out.add(i);
    }
    return out;
  }

  static List<IconData> _build() => <IconData>[
    Icons.check_circle_outline,
    Icons.star_outline,
    Icons.favorite_outline,
    Icons.favorite_border_outlined,
    Icons.bolt_outlined,
    Icons.book_outlined,
    Icons.fitness_center_outlined,
    Icons.self_improvement_outlined,
    Icons.water_drop_outlined,
    Icons.brush_outlined,
    Icons.music_note_outlined,
    Icons.code_outlined,
    Icons.school_outlined,
    Icons.restaurant_outlined,
    Icons.nightlight_outlined,
    Icons.directions_walk_outlined,
    Icons.spa_outlined,
    Icons.psychology_outlined,
    Icons.cake_outlined,
    Icons.pets_outlined,
    Icons.eco_outlined,
    Icons.work_outline,
    Icons.cleaning_services_outlined,
    Icons.shopping_cart_outlined,
    Icons.local_cafe_outlined,
    Icons.alarm_outlined,
    Icons.accessibility_new_outlined,
    Icons.ac_unit_outlined,
    Icons.air_outlined,
    Icons.anchor_outlined,
    Icons.architecture_outlined,
    Icons.article_outlined,
    Icons.assessment_outlined,
    Icons.auto_awesome_outlined,
    Icons.backpack_outlined,
    Icons.beach_access_outlined,
    Icons.bedtime_outlined,
    Icons.bike_scooter_outlined,
    Icons.biotech_outlined,
    Icons.bubble_chart_outlined,
    Icons.build_outlined,
    Icons.calculate_outlined,
    Icons.campaign_outlined,
    Icons.casino_outlined,
    Icons.castle_outlined,
    Icons.celebration_outlined,
    Icons.chat_bubble_outline,
    Icons.cloud_outlined,
    Icons.color_lens_outlined,
    Icons.computer_outlined,
    Icons.construction_outlined,
    Icons.cookie_outlined,
    Icons.coffee_outlined,
    Icons.credit_card_outlined,
    Icons.dashboard_outlined,
    Icons.data_object_outlined,
    Icons.dataset_outlined,
    Icons.deck_outlined,
    Icons.directions_boat_outlined,
    Icons.directions_bus_outlined,
    Icons.directions_car_outlined,
    Icons.directions_subway_outlined,
    Icons.dry_cleaning_outlined,
    Icons.dynamic_feed_outlined,
    Icons.east_outlined,
    Icons.directions_train_outlined,
    Icons.diversity_3_outlined,
    Icons.drafts_outlined,
    Icons.drag_indicator_outlined,
    Icons.draw_outlined,
    Icons.edit_outlined,
    Icons.edit_notifications_outlined,
    Icons.edit_calendar_outlined,
    Icons.electric_bolt_outlined,
    Icons.emoji_emotions_outlined,
    Icons.emoji_events_outlined,
    Icons.emoji_flags_outlined,
    Icons.emoji_food_beverage_outlined,
    Icons.emoji_nature_outlined,
    Icons.emoji_objects_outlined,
    Icons.emoji_people_outlined,
    Icons.emoji_symbols_outlined,
    Icons.emoji_transportation_outlined,
    Icons.engineering_outlined,
    Icons.event_outlined,
    Icons.explore_outlined,
    Icons.fastfood_outlined,
    Icons.flag_outlined,
    Icons.flight_outlined,
    Icons.food_bank_outlined,
    Icons.format_paint_outlined,
    Icons.forum_outlined,
    Icons.gavel_outlined,
    Icons.gesture_outlined,
    Icons.gif_outlined,
    Icons.gpp_good_outlined,
    Icons.headphones_outlined,
    Icons.health_and_safety_outlined,
    Icons.hiking_outlined,
    Icons.history_edu_outlined,
    Icons.history_outlined,
    Icons.home_work_outlined,
    Icons.hotel_outlined,
    Icons.handshake_outlined,
    Icons.icecream_outlined,
    Icons.image_outlined,
    Icons.key_outlined,
    Icons.label_outline,
    Icons.language_outlined,
    Icons.lightbulb_outline,
    Icons.local_bar_outlined,
    Icons.local_dining_outlined,
    Icons.local_drink_outlined,
    Icons.local_fire_department_outlined,
    Icons.local_florist_outlined,
    Icons.local_gas_station_outlined,
    Icons.local_grocery_store_outlined,
    Icons.local_hospital_outlined,
    Icons.local_laundry_service_outlined,
    Icons.local_library_outlined,
    Icons.local_mall_outlined,
    Icons.local_parking_outlined,
    Icons.local_pizza_outlined,
    Icons.local_play_outlined,
    Icons.local_police_outlined,
    Icons.local_post_office_outlined,
    Icons.local_printshop_outlined,
    Icons.local_see_outlined,
    Icons.local_shipping_outlined,
    Icons.local_taxi_outlined,
    Icons.lock_outline,
    Icons.lunch_dining_outlined,
    Icons.mail_outline,
    Icons.map_outlined,
    Icons.mediation_outlined,
    Icons.medical_services_outlined,
    Icons.menu_book_outlined,
    Icons.monitor_heart_outlined,
    Icons.movie_outlined,
    Icons.nature_outlined,
    Icons.palette_outlined,
    Icons.park_outlined,
    Icons.phone_iphone_outlined,
    Icons.phone_outlined,
    Icons.photo_camera_outlined,
    Icons.public_outlined,
    Icons.push_pin_outlined,
    Icons.receipt_long_outlined,
    Icons.recycling_outlined,
    Icons.rocket_launch_outlined,
    Icons.run_circle_outlined,
    Icons.save_outlined,
    Icons.savings_outlined,
    Icons.schedule_outlined,
    Icons.science_outlined,
    Icons.search_outlined,
    Icons.security_outlined,
    Icons.shape_line_outlined,
    Icons.share_outlined,
    Icons.shopping_bag_outlined,
    Icons.shopping_basket_outlined,
    Icons.smoke_free_outlined,
    Icons.sports_esports_outlined,
    Icons.sports_gymnastics_outlined,
    Icons.sports_handball_outlined,
    Icons.sports_mma_outlined,
    Icons.sports_rugby_outlined,
    Icons.sports_soccer_outlined,
    Icons.sports_tennis_outlined,
    Icons.stairs_outlined,
    Icons.storefront_outlined,
    Icons.wb_sunny_outlined,
    Icons.task_alt_outlined,
    Icons.theater_comedy_outlined,
    Icons.timer_outlined,
    Icons.tornado_outlined,
    Icons.toys_outlined,
    Icons.translate_outlined,
    Icons.travel_explore_outlined,
    Icons.trending_up_outlined,
    Icons.umbrella_outlined,
    Icons.upcoming_outlined,
    Icons.update_outlined,
    Icons.verified_outlined,
    Icons.video_call_outlined,
    Icons.visibility_off_outlined,
    Icons.visibility_outlined,
    Icons.voice_over_off_outlined,
    Icons.volunteer_activism_outlined,
    Icons.watch_later_outlined,
    Icons.waves_outlined,
    Icons.wb_twilight_outlined,
    Icons.wc_outlined,
    Icons.weekend_outlined,
    Icons.waterfall_chart_outlined,
    Icons.whatshot_outlined,
    Icons.where_to_vote_outlined,
    Icons.wifi_outlined,
    Icons.work_off_outlined,
    Icons.work_outlined,
    Icons.workspace_premium_outlined,
    Icons.yard_outlined,
    Icons.zoom_in_outlined,
    Icons.zoom_out_outlined,
    Icons.thumb_up_outlined,
  ];
}

/// Совместимость с прежним API: глобальная переменная habitTaskIcons пере-
/// адресует на HabitTaskIconList без миграции всех вызовов.
final List<IconData> _legacyHabitTaskIcons = HabitTaskIconList.all;

/// Возвращает константную иконку по её codePoint.
/// Используется вместо динамического `IconData(codePoint, ...)`,
/// который ломает tree-shake-icons в release-сборке для web.
IconData iconDataForCodePoint(int codePoint) {
  for (final i in _legacyHabitTaskIcons) {
    if (i.codePoint == codePoint) return i;
  }
  return Icons.check_circle_outline;
}
