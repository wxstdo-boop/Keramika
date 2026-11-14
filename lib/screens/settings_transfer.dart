part of 'settings_screen.dart';

/// Экспорт и импорт данных: зашифрованный бэкап, слияние списков по id,
/// строковых списков и данных проверок реальности.
extension _SettingsTransfer on _SettingsScreenState {
  Future<void> _exportData() async {
    final exportTitle = Translations.t('export', context);
    final exportDoneText = Translations.t('exportDone', context);
    final out = await buildBackupPayload();
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(out));
    systemUiActive = true;
    // file_picker 13: статический `saveFile` возвращает `Uri?`, а не путь
    // строкой — нам нужен только факт успешного сохранения.
    final savedUri = await FilePicker.saveFile(
      dialogTitle: exportTitle,
      fileName: 'agysha-backup.json',
      bytes: Uint8List.fromList(bytes),
    );
    systemUiActive = false;
    if (savedUri != null && mounted) {
      showBeautifulSnackBar(context, message: exportDoneText);
    }
  }

  Future<void> _mergeJsonListById(String key, String importedRaw) async {
    try {
      final existingRaw = await JsonFile.read(key);
      final existing = _parseJsonList(existingRaw);
      final imported = _parseJsonList(importedRaw);
      final merged = <String, Map<String, dynamic>>{};
      final order = <String>[];
      for (final item in existing) {
        final id = item['id']?.toString();
        if (id != null) {
          merged[id] = item;
          if (!order.contains(id)) order.add(id);
        }
      }
      for (final item in imported) {
        final id = item['id']?.toString();
        if (id != null) {
          merged[id] = item;
          if (!order.contains(id)) order.add(id);
        }
      }
      await JsonFile.write(
        key,
        jsonEncode(order.map((id) => merged[id]).toList()),
      );
    } catch (_) {
      await JsonFile.write(key, importedRaw);
    }
  }

  List<Map<String, dynamic>> _parseJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> _mergeStringList(String key, String importedRaw) async {
    try {
      final existingRaw = await JsonFile.read(key);
      List<String> existing = <String>[];
      if (existingRaw != null && existingRaw.isNotEmpty) {
        final decoded = jsonDecode(existingRaw);
        if (decoded is List) {
          existing = decoded.whereType<String>().toList();
        }
      }
      final importedDecoded = jsonDecode(importedRaw);
      List<String> imported = <String>[];
      if (importedDecoded is List) {
        imported = importedDecoded.whereType<String>().toList();
      }
      final seen = <String>{};
      final merged = <String>[];
      for (final item in [...existing, ...imported]) {
        if (seen.add(item)) merged.add(item);
      }
      await JsonFile.write(key, jsonEncode(merged));
    } catch (_) {
      await JsonFile.write(key, importedRaw);
    }
  }

  Future<void> _mergeRealityCheckData(String importedRaw) async {
    try {
      Map<String, dynamic> existing = <String, dynamic>{};
      final existingRaw = await JsonFile.read('reality_check_data');
      if (existingRaw != null && existingRaw.isNotEmpty) {
        final decoded = jsonDecode(existingRaw);
        if (decoded is Map<String, dynamic>) {
          existing = decoded;
        }
      }
      final imported = jsonDecode(importedRaw) as Map<String, dynamic>;
      final merged = <String, dynamic>{...existing, ...imported};
      final existingChecksRaw = existing['checks']?.toString() ?? '';
      final importedChecksRaw = imported['checks']?.toString() ?? '';
      final existingChecks = _parseJsonList(existingChecksRaw);
      final importedChecks = _parseJsonList(importedChecksRaw);
      final mergedChecks = <String, Map<String, dynamic>>{};
      final order = <String>[];
      for (final item in [...existingChecks, ...importedChecks]) {
        final id = item['id']?.toString();
        if (id != null) {
          mergedChecks[id] = item;
          if (!order.contains(id)) order.add(id);
        }
      }
      merged['checks'] = jsonEncode(
        order.map((id) => mergedChecks[id]).toList(),
      );
      await JsonFile.write('reality_check_data', jsonEncode(merged));
    } catch (_) {
      await JsonFile.write('reality_check_data', importedRaw);
    }
  }

  Future<void> _importData() async {
    systemUiActive = true;
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    systemUiActive = false;
    if (picked?.path == null || !mounted) return;
    if (!picked!.name.toLowerCase().endsWith('.json')) {
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t(
            'importWrongFile',
            context,
            'Please select a .json file',
          ),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
      return;
    }
    try {
      final content = await File(picked.path!).readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final serviceKeys = <String>{
        'habits',
        'tasks',
        'task_categories',
        'alarms',
        'app_timers',
        'reality_check_data',
        'nutrition_meals',
        'ai_chat_history',
        'ai_pinned_messages',
        'ada_sync_state',
        'completion_log',
        'ny_event_2027',
      };
      final listServiceKeys = <String>{
        'habits',
        'tasks',
        'alarms',
        'app_timers',
        'nutrition_meals',
      };
      final settingsKeys = <String>{
        'app_settings',
        'setting_theme',
        'setting_locale',
        'setting_font_family',
        'setting_peach_dark',
        'setting_experimental',
        'setting_auto_save',
        'setting_dev_mode',
        'developer_prompt',
        'setting_auto_export',
        'setting_ai_guide',
        'setting_ai_key',
        'setting_ada_proactive',
        'setting_ai_tracking',
        'setting_agnes_key',
        'setting_zen_key',
        'setting_gemini_key',
        'setting_modal_url',
        'setting_modal_key',
        'perfectionism_mode',
        'berserk_mode',
        'task_quick_notes_mode',
      };
      for (final entry in decoded.entries) {
        if (entry.value == null) continue;
        final key = entry.key;
        final v = entry.value;
        if (key == 'app_settings' && v is Map) {
          final settingsRaw = await JsonFile.read('app_settings');
          final settings = settingsRaw != null
              ? Map<String, dynamic>.from(jsonDecode(settingsRaw))
              : <String, dynamic>{};
          settings.addAll(Map<String, dynamic>.from(v));
          await JsonFile.write('app_settings', jsonEncode(settings));
        } else if (serviceKeys.contains(key) && v is String) {
          if (listServiceKeys.contains(key)) {
            await _mergeJsonListById(key, v);
          } else if (key == 'task_categories') {
            await _mergeStringList(key, v);
          } else if (key == 'reality_check_data') {
            await _mergeRealityCheckData(v);
          } else {
            await JsonFile.write(key, v);
          }
        } else if (settingsKeys.contains(key)) {
          if (key == 'developer_prompt') {
            if (v is! String) {
              throw const FormatException(
                'The developer prompt in this backup is invalid',
              );
            }
            await SettingsService.saveDeveloperPrompt(v);
            continue;
          }
          final settingsRaw = await JsonFile.read('app_settings');
          final settings = settingsRaw != null
              ? Map<String, dynamic>.from(jsonDecode(settingsRaw))
              : <String, dynamic>{};
          settings[key] = v;
          await JsonFile.write('app_settings', jsonEncode(settings));
        } else if (key == 'app_pin' && v is String) {
          await PinService.importBackupValue(v);
        } else {
          if (v is String) {
            await globalPrefs.setString(key, v);
          } else if (v is bool) {
            await globalPrefs.setBool(key, v);
          } else if (v is int) {
            await globalPrefs.setInt(key, v);
          } else if (v is double) {
            await globalPrefs.setDouble(key, v);
          } else if (v is List) {
            await globalPrefs.setStringList(key, v.cast<String>());
          }
        }
      }
      await HabitService().load();
      await TaskService().load();
      await AlarmService().load();
      await RealityCheckService().load();
      await TimerService().load();
      await NutritionService().load();
      await rescheduleAllNotifications();
      if (await SettingsService.loadAutoSave()) {
        stopAutoSave();
        startAutoSave();
      } else {
        stopAutoSave();
      }
      if (await SettingsService.loadAutoExport()) {
        stopAutoExport();
        startAutoExport();
      } else {
        stopAutoExport();
      }
      // refreshApp() пересоздаёт всё дерево (новый UniqueKey) и уходит на
      // сплэш — контекст настроек после этого мёртв, а OverlayEntry снекбара
      // был бы уничтожен вместе со старым деревом ДО появления. Поэтому
      // снекбар «Настройки импортированы» показываем через корневой
      // navigatorKey уже ПОСЛЕ пересоздания — он плавно выезжает и плавно
      // уходит на новом дереве.
      if (!mounted) return;
      await AgyshaApp.of(context).refreshApp();
      final rootCtx = navigatorKey.currentContext;
      if (rootCtx != null && rootCtx.mounted) {
        // Небольшая пауза: новый Overlay успевает построиться после
        // пересоздания дерева, и снекбар появляется на нём плавно.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (rootCtx.mounted) {
          showBeautifulSnackBar(
            rootCtx,
            message: Translations.t('importDone', rootCtx),
          );
        }
      }
    } catch (_) {
      final ctx = navigatorKey.currentContext ?? context;
      if (ctx.mounted) {
        showBeautifulSnackBar(
          ctx,
          message: Translations.t('importError', ctx),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
    }
  }
}
