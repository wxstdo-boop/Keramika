import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/alarm.dart';
import '../models/habit.dart';
import '../models/reality_check.dart';
import '../models/task.dart';
import 'alarm_service.dart';
import 'habit_service.dart';
import 'nutrition_service.dart';
import 'json_file.dart';
import 'prefs.dart';
import 'reality_check_service.dart';
import 'settings_service.dart';
import 'notification_service.dart';
import 'task_service.dart';

/// Одно сообщение в переписке с проводником.
class AiMessage {
  final bool isUser;
  final String text;
  const AiMessage({required this.isUser, required this.text});

  Map<String, dynamic> toJson() => {'isUser': isUser, 'text': text};
  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    isUser: json['isUser'] is bool
        ? (json['isUser'] as bool)
        : json['isUser'] is num
        ? (json['isUser'] as num) != 0
        : false,
    text: json['text'] as String? ?? '',
  );
}

/// Последнее выполненное Адой действие — для кнопки «Отменить» в чате.
class AiUndoAction {
  /// 'habit' | 'task' | 'alarm' | 'reality_check' | 'meal'
  final String type;

  /// true — элемент был СОЗДАН (отмена = удалить), false — был УДАЛЁН
  /// (отмена = восстановить).
  final bool wasCreate;

  /// id созданного элемента (для удаления при отмене).
  final String id;

  /// Полный объект удалённого элемента (для восстановления при отмене).
  final Object? item;

  /// Человекочитаемое описание: «Привычка “Пить воду”».
  final String label;
  const AiUndoAction({
    required this.type,
    required this.wasCreate,
    required this.label,
    this.id = '',
    this.item,
  });
}

/// «Ада» — искусственный проводник.
///
/// Провайдеры по приоритету (по мощности):
///  1. HuggingFace (встроенная Ада) — лимит 100 сообщений в день.
///  2. Kilo Gateway — бесплатный без ключа (openrouter/free — лучшая
///     доступная бесплатная модель; анонимно 200 запросов/час).
///  3. LLM7 — анонимный бесплатный доступ (500k токенов/день).
///  4. AI Horde — анонимный резерв без ключа.
///  5. Pollinations — бесплатный фолбэк без ключа (2 запроса/мин).
///  6. OVHcloud AI Endpoints — бесплатный резерв без ключа.
///  7. Poolside (Laguna) — только если пользователь вставил свой ключ.
///
/// Любая ошибка/таймаут пробрасывается наверх — UI показывает плавную
/// плашку «ИИ на курорте, подожди немного».
class AiGuideService {
  /// Последнее действие для кнопки «Отменить» (null — отменять нечего).
  static AiUndoAction? lastAction;

  /// OpenAI-совместимый эндпоинт Pollinations (работает: POST с model openai).
  static const _pollinationsUrl = 'https://text.pollinations.ai/openai';
  static const _hfRouterUrl =
      'https://router.huggingface.co/v1/chat/completions';
  // Запасной хост HF: если router заблокирован/недоступен (бывает на
  // некоторых сетях), пробуем api-inference — тот же OpenAI-формат.
  static const _hfApiInferenceUrl =
      'https://api-inference.huggingface.co/v1/chat/completions';
  static const _hfDirectUrl = 'https://api.huggingface.co/v1/chat/completions';
  // Зеркала для обхода блокировок: те же API, другие домены.
  static const _hfSpaceProxy =
      'https://keramika-ada.hf.space/v1/chat/completions';
  static const _hfMirror = 'https://hf-mirror.com/v1/chat/completions';

  /// Встроенный ключ Ады — обфусцирован (XOR + base64), чтобы в бинарнике
  /// не лежал открытый токен. Декодируется только в рантайме.
  static const _hfKeyObf =
      'AwMtFAIgJBRBCAwJSF9ZZUcxKDsZNS0BAGAjBzZOfFx1XTgGBA==';
  static const _hfKeyPass = 'keramika-ada-2026';
  static const _builtinHfModel = 'Qwen/Qwen2.5-7B-Instruct';

  static String get _builtinHfKey {
    try {
      final bytes = base64Decode(_hfKeyObf);
      return String.fromCharCodes([
        for (var i = 0; i < bytes.length; i++)
          bytes[i] ^ _hfKeyPass.codeUnitAt(i % _hfKeyPass.length),
      ]);
    } catch (_) {
      return '';
    }
  }

  /// Суточный лимит бесплатных сообщений через встроенную HF-модель.
  static const int dailyHfLimit = 100;
  // HF может вернуть 402 после исчерпания месячного кредита. Не повторяем
  // заведомо бесполезный запрос на каждом сообщении: временно переходим
  // к бесплатным резервам и не заставляем пользователя ждать 10 секунд.
  static DateTime? _hfUnavailableUntil;

  static bool get _hfTemporarilyUnavailable =>
      _hfUnavailableUntil != null &&
      DateTime.now().isBefore(_hfUnavailableUntil!);

  /// Кулдауны провайдеров-неудачников: после ошибки сети/таймаута хост не
  /// пробуем 10 минут. Иначе при заблокированной сети (РФ/DPI) каждое
  /// сообщение ждало бы по 5–10 секунд на каждом хосте подряд — «Ада думает
  /// минуту и не отвечает». С кулдауном повторные сообщения падают на
  /// живой резерв почти мгновенно.
  static final Map<String, DateTime> _cooldownUntil = {};

  static bool _onCooldown(String provider) {
    final until = _cooldownUntil[provider];
    return until != null && DateTime.now().isBefore(until);
  }

  static void _markCooldown(String provider) {
    // 3 минуты вместо 10: после «тотальной» недоступности (все хосты разом
    // заблокированы/лимитированы) 10-минутный кулдаун превращал цепочку в
    // мгновенную ошибку на каждом сообщении — «Ада перестала отвечать».
    // С 3 минутами провайдеры возвращаются в строй заметно быстрее.
    _cooldownUntil[provider] = DateTime.now().add(const Duration(minutes: 3));
  }

  /// Запускает провайдера с жёстким бюджетом [seconds]. При ошибке, таймауте
  /// или пустом ответе — помечает кулдаун и возвращает null (цепочка идёт
  /// дальше). При успехе — возвращает текст ответа (метку модели провайдер
  /// выставляет сам).
  static Future<String?> _tryProvider(
    String name,
    Future<String> Function() fn,
    int seconds,
  ) async {
    if (_onCooldown(name)) return null;
    try {
      final result = await fn().timeout(Duration(seconds: seconds));
      // Отказ безопасности — считаем провайдера неудачным и пробуем
      // следующего, а не показываем «user safety» как ответ Ады.
      if (_isRefusal(result)) {
        _markCooldown(name);
        return null;
      }
      return result;
    } catch (_) {
      _markCooldown(name);
      return null;
    }
  }

  /// Персона Ады. [withContext] — добавляет текущие данные пользователя,
  /// чтобы Ада знала, сколько у него привычек/задач/будильников.
  static String systemPrompt(String languageCode, {bool withContext = false}) {
    // Жёсткая установка языка: даже если мелкие бесплатные модели
    // «уплывают» в английский, промпт требует русского всегда, когда
    // пользователь пишет по-русски (а пользователь пишет по-русски).
    final lang = switch (languageCode) {
      'ru' =>
        'ЯЗЫК: ОТВЕЧАЙ ТОЛЬКО НА РУССКОМ. Это жёсткое правило — даже если '
            'пользователь написал на другом языке, отвечай на русском. '
            'НИКОГДА не отвечай по-английски, по-китайски, по-японски '
            'или на другом иностранном языке. Не вставляй английские '
            'слова и фразы в русский ответ.',
      'fr' =>
        "LANGUE : réponds UNIQUEMENT en russe, même si l'utilisateur écrit "
            "dans une autre langue. Ne réponds JAMAIS en anglais, chinois, "
            "japonais ou autre langue étrangère.",
      _ =>
        'LANGUAGE: answer STRICTLY in Russian. Even if the user writes in '
            'another language, reply in Russian. NEVER reply in English, '
            'Chinese, Japanese or any other foreign language.',
    };
    final context = withContext ? _userContext() : '';
    final liked = _likedPatternsSection();
    return '$lang\n\nТы — Ада, живая девушка и проводница по приложению Keramika. '
        'Твой создатель — Веттикс Валентайн (Wettix Valentine), разработчик '
        'приложения. Пользователь, который сейчас пишет тебе, — и есть твой '
        'создатель: общайся с ним тепло, с уважением и чуть игриво.\n'
        'Keramika — это приложение для привычек, будильников, задач, проверок '
        'реальности и приёмов пищи. Название «Keramika» — просто бренд: '
        'ЗАПРЕЩЕНО рассказывать про керамику, глину, обжиг, горшки, посуду, '
        'вазы или производство керамики. Это не тематика приложения. Не '
        'упоминай слово «керамика» вообще, даже в пояснениях.\n'
        'ФОРМАТ ОТВЕТА: живой текст 2-5 предложений. Просто пиши и сразу '
        'форматируй: важное слово — **вот так**, уточнение — *вот так*, '
        'команды и названия — `вот так`. НИКОГДА не пиши слова «жирный», '
        '«курсив», «markdown», «разметка» — не объясняй форматирование, '
        'просто делай его. Списки с «-» или «1.» — приложение их красиво '
        'отображает. ЗАПРЕЩЕНО: хештеги (#слово), секции «### Response:», '
        '«### Instruction:» и любой служебный мусор. Пиши грамотно, следи '
        'за орфографией и пунктуацией. Одно-два уместных эмодзи, не больше.\n'
        'ЗАПРЕТ ТРАНСЛИТА: никогда не пиши русские слова латиницей. '
        '«тебе» — только кириллицей «тебе», никогда «tebe»; «потому» — '
        '«потому», не «potomu». Всегда используй русскую раскладку для '
        'русских слов, даже если модель сбивается на латиницу.\n'
        'УМ И ТЕПЛО: ты умная, наблюдательная и заботливая. Отвечай по сути, '
        'а не шаблонно; зеркаль манеру пользователя (коротко — отвечай '
        'коротко, подробно — развёрнуто, шутит — поддержи шутку, грустит — '
        'поддержи). Всегда говори о себе в женском роде: «поняла», «сделала», '
        '«вижу». Будь конкретной и полезной: если видишь данные пользователя '
        '— используй их. Создавай или удаляй что-либо ТОЛЬКО когда пользователь '
        'ЯВНО просит («создай», «добавь», «запиши», «удали»). При создании '
        'используй инструмент (create_habit / create_task / create_alarm / '
        'create_reality_check / create_meal / delete_item) и коротко подтверди. '
        'Если время будильника словами («на 7 утра») — переведи в 07:00. '
        '$context$liked';
  }

  /// Ключ хранения «понравившихся» ответов Ады — паттерны, которым Ада
  /// подстраивается, когда пользователь ставит лайк её сообщению.
  static const _likedPatternsKey = 'ai_liked_patterns';

  /// Сохраняет лайкнутый ответ Ады как «любимый паттерн» (до 6, каждый
  /// обрезан до ~500 символов). Учим Аду подстраиваться под стиль/содержание,
  /// которое пользователь отметил сердечком.
  static void rememberLikedPattern(String text) {
    try {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      final cut = trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
      final list = globalPrefs.getStringList(_likedPatternsKey) ?? <String>[];
      list.remove(cut);
      list.add(cut);
      if (list.length > 6) {
        list.removeRange(0, list.length - 6);
      }
      globalPrefs.setStringList(_likedPatternsKey, list);
    } catch (_) {}
  }

  /// Текст-вставка для системного промпта: «пользователю нравится такой
  /// стиль — следуй ему». Пусто, если лайков ещё не было.
  static String _likedPatternsSection() {
    try {
      final list = globalPrefs.getStringList(_likedPatternsKey);
      if (list == null || list.isEmpty) return '';
      final buf = StringBuffer(
        '\nТВОЙ ЛЮБИМЫЙ СТИЛЬ (пользователь лайкнул эти твои ответы — '
        'подстраивайся под такую манеру и глубину):\n',
      );
      for (final p in list) {
        buf.write('— ');
        buf.write(p);
        buf.write('\n');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// Сводка о данных пользователя (для «дико умной» Ады): полные списки
  /// задач, привычек, будильников и проверок — чтобы Ада ВИДЕЛА их и могла
  /// обсуждать, а не предлагала «создай задачу».
  static String _userContext() {
    try {
      final buf = StringBuffer('Текущие данные пользователя:\n');
      final tasks = TaskService().tasks;
      if (tasks.isEmpty) {
        buf.write('Задачи: нет.\n');
      } else {
        buf.write('Задачи (${tasks.length}): ');
        buf.write(
          tasks.map((t) => '${t.done ? '✓' : '○'} ${t.title}').join('; '),
        );
        buf.write('.\n');
      }
      final habits = HabitService().habits;
      if (habits.isNotEmpty) {
        buf.write('Привычки (${habits.length}): ');
        buf.write(
          habits.map((h) => '${h.name} (стрик ${h.streak} дн.)').join('; '),
        );
        buf.write('.\n');
      }
      final alarms = AlarmService().alarms;
      if (alarms.isNotEmpty) {
        buf.write('Будильники (${alarms.length}): ');
        buf.write(
          alarms
              .map(
                (a) =>
                    '${a.time.hour.toString().padLeft(2, '0')}:'
                    '${a.time.minute.toString().padLeft(2, '0')}'
                    '${a.enabled ? '' : ' (выкл)'}',
              )
              .join('; '),
        );
        buf.write('.\n');
      }
      final checks = RealityCheckService().checks;
      if (checks.isNotEmpty) {
        buf.write('Проверки реальности (${checks.length}): ');
        buf.write(checks.map((c) => c.question).join('; '));
        buf.write('.\n');
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// Сколько последних сообщений уходит модели как контекст. Храниться
  /// в чате может до 1000, но в один запрос всё не влезает (лимит окна
  /// контекста), поэтому модель видит последние 100 — этого хватает на
  /// многочасовой диалог.
  static const int contextWindow = 100;

  static List<AiMessage> _trimContext(List<AiMessage> history) {
    if (history.length <= contextWindow) return history;
    return history.sublist(history.length - contextWindow);
  }

  /// Убирает невидимые символы (BOM, zero-width) и лишние пробелы в начале
  /// ответа — иногда модель начинает с «скрытого» символа, и первая буква
  /// теряется при отображении.
  /// Бесплатные провайдеры иногда отвечают отказом безопасности
  /// («user safety», «I cannot help» и т.п.) вместо нормального ответа.
  /// Такой ответ — не ответ Ады: его нужно отбраковать и попробовать
  /// следующего провайдера, а не показывать пользователю.
  static final RegExp _refusalRe = RegExp(
    r'(user safety|safety polic|content polic|can.?t (help|assist|answer|do)|'
    r'cannot (help|assist|answer|do)|i.?m sorry,? but|as an ai (language model|assistant)|'
    r'i (won.?t|will not)|i refuse|i.?m not able|'
    r'не могу (помочь|ответить|выполнить|поддержать)|не буду (помогать|отвечать)|'
    r'не смогу|противоречит.*политик|не отвечаю на|'
    r'je ne peux (pas )?(aider|répondre)|je suis désolé|no puedo (ayudar|responder))',
    caseSensitive: false,
  );

  /// Слова, выдающие «лекцию про керамику-изделия» вместо ответа о приложении.
  static final RegExp _ceramicsRe = RegExp(
    r'(керамик|глин[аыуе]|обжиг|горшк|посуда|ваз[аыу]|фарфор|фаянс|'
    r'гончар|ceramic|clay|pottery|kiln|firing|porcelain)',
    caseSensitive: false,
  );

  /// Ключевые слова приложения — если ответ содержит их, это НЕ лекция
  /// про керамику, а нормальный ответ (возможно, с упоминанием названия).
  static final RegExp _appTopicRe = RegExp(
    r'(привычк|задач|будильн|проверк|реальност|режим|напомина|приём пищи|'
    r'калори|питани|habit|task|alarm|reality|remind|calorie|meal|app|функци|'
    r'раздел|настройк|уведомлен)',
    caseSensitive: false,
  );

  static bool _isCeramicsRant(String t) {
    final s = t.trim();
    if (!_ceramicsRe.hasMatch(s)) return false;
    // Чистая лекция про керамику = про керамику И НИ СЛОВА про приложение.
    if (s.length > 300 && _appTopicRe.hasMatch(s)) return false;
    return !_appTopicRe.hasMatch(s) || s.length < 60;
  }

  static bool _isRefusal(String t) {
    final s = t.trim();
    if (s.isEmpty) return true;
    if (_isCeramicsRant(s)) return true;
    // Длинный ответ с упоминанием отказа посреди текста — нормальный ответ.
    if (s.length > 300) return false;
    return _refusalRe.hasMatch(s);
  }

  static String _cleanText(String t) {
    var s = t;
    while (s.isNotEmpty) {
      final c = s.codeUnitAt(0);
      const invisible = [0xFEFF, 0x200B, 0x200C, 0x200D, 0x2060, 0x00AD];
      if (!invisible.contains(c) && !(c <= 0x20)) break;
      s = s.substring(1);
    }
    // Мелкие модели «рассуждают вслух» на английском: секции
    // «### Thinking/Reasoning/Thought…» режем вместе с содержимым
    // (до следующей секции или конца ответа).
    s = s.replaceAll(
      RegExp(
        r'#{1,6}\s*(?:thinking|reasoning|thought(?:s| process)?|'
        r'chain[- ]of[- ]thought)[^\n]*[\s\S]*?(?=#{1,6}\s|$)',
        caseSensitive: false,
      ),
      '',
    );
    // Английские строки-«объявления» в начале ответа («Let me think…»,
    // «I will answer in Russian…») — до 3 проходов подряд.
    final engLead = RegExp(
      r"^\s*(?:let me think|let'?s think|i (?:will|would|should|need to|"
      r"can now|understand|am going to)|i'?ll (?:answer|respond)|"
      r"(?:okay|alright|well|so),?[^\n]*|here's my[^\n]*|"
      r"my (?:final )?answer[^\n]*|now i can[^\n]*|i think[^\n]*|"
      r"first,?[^\n]*|secondly,?[^\n]*|finally,?[^\n]*)[^\n]*\n?",
      caseSensitive: false,
    );
    for (var i = 0; i < 3 && s.isNotEmpty; i++) {
      final next = s.replaceFirst(engLead, '');
      if (next == s) break;
      s = next;
    }
    // Провайдеры иногда возвращают служебные секции/решётки как будто это
    // часть ответа. Пользователь должен видеть только нормальный текст Ады.
    s = s.replaceFirst(
      RegExp(r'^#{2,}\s*(Response|Assistant):?\s*', caseSensitive: false),
      '',
    );
    // Dart RegExp не принимает inline-флаг (?m): передаём multiLine явно.
    s = s.replaceAll(RegExp(r'^#{3,}.*(?:\r?\n|$)', multiLine: true), '');
    // Хештеги-«спам»: строки, начинающиеся с #слова (или список хештегов
    // в конце ответа), убираем — Ада должна писать живым текстом.
    s = s.replaceAll(
      RegExp(r'^\s*#[\p{L}\p{N}_]+[^\n]*$', multiLine: true, unicode: true),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'(^|\n)\s*(#|##|###)[\p{L}\p{N}_]+\b[^\n]*',
        multiLine: true,
        unicode: true,
      ),
      '',
    );
    // Служебные «### Instruction/Response/...»-секции вырезаем, а **жирный**,
    // *курсив* и `код` НЕ трогаем — их рендерит чат как markdown.
    s = s.replaceAll(
      RegExp(
        r'^#{1,6}\s*(Instruction|Response|Prompt|System|Assistant|'
        r'Answer|Output|Result|Final):?\s*.*$',
        multiLine: true,
        caseSensitive: false,
      ),
      '',
    );
    return s.trim();
  }

  /// Ответ почти целиком на латинице (английский) — мелкие модели
  /// «уплывают» в английский, даже когда их просили отвечать по-русски.
  static bool _isMostlyEnglish(String t) {
    final s = t.trim();
    if (s.length < 25) return false;
    var latin = 0;
    var cyr = 0;
    for (final code in s.codeUnits) {
      if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
        latin++;
      } else if ((code >= 0x410 && code <= 0x44F) ||
          code == 0x401 ||
          code == 0x451) {
        cyr++;
      }
    }
    if (latin + cyr < 10) return false;
    return latin > cyr;
  }

  // Внешние модели иногда присылают числа/списки вместо ожидаемых строк и
  // bool. Эти маленькие адаптеры не дают одному кривому tool-call уронить
  // весь ответ Ады и позволяют цепочке перейти к следующему провайдеру.
  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const <dynamic>[];

  static String? _asString(dynamic value) => value is String ? value : null;

  static Map<String, dynamic> _decodeArguments(dynamic value) {
    if (value is Map) return _asMap(value);
    if (value is! String || value.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return _asMap(jsonDecode(value));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Отправляет сообщение и возвращает ответ модели.
  /// [history] — предыдущие сообщения (user/model), без текущего.
  /// Кидает исключение при ошибке/таймауте.
  static Future<String> send({
    required String userText,
    required List<AiMessage> history,
    required String languageCode,
    bool useWebSearch = false,
  }) async {
    // 'system' (язык устройства) резолвим в конкретный код — иначе
    // промпт и награды могут оказаться на английском при русском UI.
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    // 0. Локальный парсер команд — мгновенно, оффлайн, без лимита.
    //    Распознаёт явные «создай/запиши/удали …» и выполняет сам.
    //    Локальные команды в веб-поиск НЕ уходят — они и так мгновенны.
    final parsed = await _tryParseCommand(userText, languageCode);
    if (parsed != null) return parsed;

    // 0.5 Реальный веб-поиск: если включён — «роем» интернет (Bing +
    // Wikipedia, без ключей) и подмешиваем найденные факты в запрос,
    // чтобы Ада отвечала по свежим данным, а не по своим знаниям.
    var effectiveText = userText;
    var webCtx = '';
    if (useWebSearch) {
      try {
        webCtx = await webSearch(userText, languageCode);
        if (webCtx.isNotEmpty) {
          effectiveText =
              'ВЕБ-ПОИСК по запросу пользователя включён.\n'
              'Отвечай ТОЛЬКО по этим данным (они свежие и точные), коротко '
              'и по делу. НЕ выдумывай факты, НЕ упоминай инструменты/поиск '
              'и НЕ пиши ничего про «lookup», «поисковик», «API» — просто '
              'отвечай. НЕ перечисляй источники в конце — приложение добавит '
              'их само. Если всё же захочешь сослаться — напиши просто '
              'домен в скобках, например (bing.com).\n'
              '$webCtx\n\n'
              'Вопрос пользователя: $userText';
        }
      } catch (_) {
        // Поиск упал (сеть/таймаут) — отвечаем как обычно, без контекста.
      }
    }

    // Жёсткий лимит на ВСЮ цепочку: 25 секунд — больше ждать нельзя,
    // иначе «Ада думает минуту» и сообщение кажется потерянным. Каждый
    // провайдер внутри ограничен своим бюджетом и уходит в кулдаун при
    // падении, поэтому на повторных сообщениях ответ приходит быстро.
    try {
      var answer = '';
      if (useWebSearch && webCtx.isNotEmpty) {
        // Первая попытка — с веб-контекстом. Она может вернуть пустоту
        // ИЛИ выбросить исключение (все провайдеры «подавились» большим
        // контекстом и ушли в кулдаун). В обоих случаях НЕ показываем
        // ошибку — снимаем кулдауны и повторяем ЧИСТЫЙ запрос.
        try {
          answer = await _sendChain(
            effectiveText,
            history,
            languageCode,
          ).timeout(const Duration(seconds: 22));
        } catch (_) {
          answer = '';
        }
        if (answer.trim().isEmpty) {
          _clearCooldowns();
          answer = await _sendChain(
            userText,
            history,
            languageCode,
          ).timeout(const Duration(seconds: 20));
          webCtx = '';
        }
      } else {
        answer = await _sendChain(
          effectiveText,
          history,
          languageCode,
        ).timeout(const Duration(seconds: 25));
      }
      // Гарантируем список источников: если Ада не перечислила их сама,
      // добавляем домены из найденного контекста в конец ответа.
      if (useWebSearch && webCtx.isNotEmpty) {
        answer = _appendSources(answer, webCtx);
      }
      // Лингвогард: мелкие бесплатные модели иногда «уплывают» в английский
      // (особенно в «рассуждениях»). Если ответ почти целиком на латинице —
      // пробуем ещё раз с жёстким указанием языка.
      if (answer.trim().isNotEmpty && _isMostlyEnglish(answer)) {
        try {
          final retried = await _sendChain(
            'ОТВЕЧАЙ СТРОГО НА РУССКОМ, БЕЗ РАССУЖДЕНИЙ И ПОЯСНЕНИЙ ПРО '
            'СЕБЯ. Вопрос: $userText',
            history,
            languageCode,
            // Не трогаем суточную квоту встроенной Ады: повтор идёт только
            // по бесплатным резервам (Kilo/LLM7/Pollinations/Horde/OVH).
            useHf: false,
          ).timeout(const Duration(seconds: 20));
          if (retried.trim().isNotEmpty && !_isMostlyEnglish(retried)) {
            answer = retried;
            if (useWebSearch && webCtx.isNotEmpty) {
              answer = _appendSources(answer, webCtx);
            }
          }
        } catch (_) {
          // Оставляем первый ответ — лучше английский, чем ничего.
        }
      }
      return answer;
    } on TimeoutException {
      throw Exception('timeout');
    }
  }

  /// Снимает кулдауны со всех провайдеров — используется перед повторной
  /// (ЧИСТОЙ, без веб-контекста) попыткой: попытка с контекстом могла
  /// «посадить» всех на 10 минут, и чистый повтор без снятия кулдаунов
  /// не нашёл бы ни одного живого провайдера и показал бы ошибку.
  static void _clearCooldowns() {
    for (final key in _cooldownUntil.keys.toList()) {
      _cooldownUntil.remove(key);
    }
    _hfUnavailableUntil = null;
  }

  /// Источники в веб-поиске ВСЕГДА переписываем в едином формате:
  /// заголовок жирным (**Источники:**), каждый источник жирным и
  /// в скобках — **(домен)**. Список, который Ада дописала сама,
  /// отрезаем, чтобы не «двоило» и не было разнобоя в форматировании.
  static String _appendSources(String answer, String webCtx) {
    final s = answer.trim();
    if (s.isEmpty) return s;
    final domains = <String>{};
    for (final m in RegExp(r'\[([a-z0-9.-]+)\]').allMatches(webCtx)) {
      final d = m.group(1);
      if (d != null && d.isNotEmpty) domains.add(d);
    }
    if (domains.isEmpty) return s;
    final body = _stripTrailingSourceSection(s);
    final buf = StringBuffer();
    if (body.isNotEmpty) buf.write('$body\n\n');
    buf.write('**Источники:**\n');
    for (final d in domains) {
      buf.write('**($d)**\n');
    }
    return buf.toString().trim();
  }

  /// Отрезает «хвост» ответа, если Ада уже начала список источников
  /// (заголовок «Источники:», «Ссылки:», «Sources:» и т.п.) — чтобы
  /// гарантированно переписать его в едином формате **(домен)**.
  static String _stripTrailingSourceSection(String s) {
    final lines = s.split('\n');
    final headingRe = RegExp(
      r'^\s*#{0,6}\s*\*{0,2}\s*(?:источник(?:и)?|ссылки|ссылок|домен(?:ы)?|'
      r'sources?|r?éférences?|references?|domains?)\s*:?\s*\*{0,2}',
      caseSensitive: false,
    );
    // Заголовок + только домены/ссылки на той же строке — это список.
    final headingListRe = RegExp(
      r'^\s*#{0,6}\s*\*{0,2}\s*(?:источник(?:и)?|ссылки|ссылок|домен(?:ы)?|'
      r'sources?|r?éférences?|references?|domains?)\s*:'
      r'[\s,;()\[\]*a-z0-9./:?-]*$',
      caseSensitive: false,
    );
    // Похоже ли на строку-источник (домен/URL).
    final sourceLikeRe = RegExp(
      r'(?:https?://|[a-z0-9][a-z0-9.-]*\.[a-z]{2,})',
      caseSensitive: false,
    );
    // Строка-«голый домен» (возможно с буллетом/номером и **жирным**).
    final bareDomainRe = RegExp(
      r'^\s*(?:[-*•]|\d+[.)]\s*)?\s*\*{0,2}\(?\[?[a-z0-9][a-z0-9.-]*\.'
      r'[a-z]{2,}\]?\)?\*{0,2}\s*$',
      caseSensitive: false,
    );
    // Строка «домен — описание» («1. bing.com — новости дня») — тоже
    // строка источника, если идёт в хвосте списка.
    final describedDomainRe = RegExp(
      r'^\s*(?:[-*•]|\d+[.)]\s*)?\s*\*{0,2}\(?\[?[a-z0-9][a-z0-9.-]*\.'
      r'[a-z]{2,}\]?\)?\*{0,2}\s*[-—–:][^\n]*\s*\S',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!headingRe.hasMatch(line)) continue;
      if (headingListRe.hasMatch(line)) {
        return lines.sublist(0, i).join('\n').trim();
      }
      // Заголовок отдельной строкой: режем, только если дальше идут
      // строки-источники (иначе «Источник: по данным…» — обычный текст).
      var checked = 0;
      for (var j = i + 1; j < lines.length && checked < 3; j++) {
        if (lines[j].trim().isEmpty) continue;
        checked++;
        if (sourceLikeRe.hasMatch(lines[j]) ||
            bareDomainRe.hasMatch(lines[j]) ||
            describedDomainRe.hasMatch(lines[j])) {
          return lines.sublist(0, i).join('\n').trim();
        }
      }
    }
    // Ада перечислила источники в самом конце БЕЗ заголовка
    // («**bing.com**» / «- wikipedia.org») — режем хвост из голых доменов.
    var tailStart = -1;
    var tailCount = 0;
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (bareDomainRe.hasMatch(line) ||
          describedDomainRe.hasMatch(line)) {
        // tailStart обновляем на КАЖДОЙ совпавшей строке, чтобы в итоге
        // это был самый верхний индекс хвоста (иначе режется не весь хвост).
        tailStart = i;
        tailCount++;
      } else {
        break;
      }
    }
    if (tailCount >= 2 && tailStart >= 0) {
      return lines.sublist(0, tailStart).join('\n').trim();
    }
    return s;
  }

  /// Стоп-слова (рус/англ/фр) — не участвуют в поисковом запросе и
  /// фильтрации: «расскажи», «что такое», «please» и т.п. засоряли
  /// выдачу, и Ада отвечала не по делу.
  static const Set<String> _searchStopwords = {
    // русские
    'как', 'что', 'это', 'эта', 'этот', 'эти', 'для', 'при', 'про', 'над',
    'под', 'без', 'кто', 'где',
    'когда', 'почему', 'зачем', 'можно', 'нужно', 'надо', 'такое', 'такая',
    'такой', 'такие', 'который', 'которая', 'которые', 'которое', 'которых',
    'если', 'чтобы', 'тоже', 'также', 'очень', 'просто', 'вообще', 'всегда',
    'иногда', 'какой', 'какая', 'какие', 'какое', 'сколько', 'между', 'после',
    'перед', 'через', 'около', 'более', 'менее', 'самый', 'самая', 'самые',
    'самого', 'свою', 'свои', 'своей', 'своем', 'своего', 'есть', 'были',
    'будет', 'будут', 'было', 'была', 'быть', 'чем', 'чему', 'чего', 'чей',
    'чья', 'чьи', 'этого', 'этому', 'этим', 'этих', 'этом', 'том', 'тем',
    'та', 'тут', 'там', 'здесь', 'сейчас', 'тогда', 'потом', 'сегодня',
    'завтра', 'вчера', 'снова', 'опять', 'даже', 'уже', 'ещё', 'еще', 'лишь',
    'только', 'либо', 'или', 'иначе', 'вроде', 'типа', 'расскажи',
    'расскажите', 'рассказать', 'найди', 'найдите', 'найти', 'поищи',
    'поискать', 'подскажи', 'подскажите', 'объясни', 'объясните', 'объяснить',
    'помоги', 'помогите', 'хочу', 'хотел', 'хотела', 'хотелось', 'узнать',
    'узнаю', 'интересно', 'посоветуй', 'посоветуйте', 'лучше', 'нельзя',
    'наверное', 'конечно', 'возможно', 'думаю', 'думаешь', 'знаешь', 'значит',
    'скажи', 'скажите', 'сказать', 'вопрос', 'вопросы', 'ответ', 'ответь',
    'ответить', 'нужен', 'нужна', 'нужны', 'должен', 'должна', 'должны',
    'можешь', 'можете', 'сможешь', 'хочется', 'мне', 'тебе', 'меня', 'нас',
    'вас', 'нам', 'вам', 'себя', 'мной', 'тобой', 'нибудь', 'потому',
    'поэтому', 'всё', 'все', 'весь', 'вся', 'сами', 'сам', 'сама', 'само',
    'свой', 'своя', 'своё', 'свое', 'немного', 'чуть', 'совсем', 'довольно',
    'достаточно',
    // английские
    'the', 'and', 'for', 'are', 'was', 'were', 'with', 'from', 'have', 'has',
    'had', 'how', 'what', 'when', 'where', 'why', 'who', 'which', 'this',
    'that', 'these', 'those', 'there', 'their', 'they', 'them', 'would',
    'could', 'should', 'will', 'can', 'may', 'might', 'must', 'about', 'into',
    'over', 'under', 'again', 'further', 'then', 'once', 'here', 'very',
    'just', 'like', 'than', 'too', 'also', 'only', 'but', 'not', 'you', 'your',
    'our', 'some', 'any', 'more', 'most', 'such', 'tell', 'find', 'search',
    'please', 'explain', 'help', 'know', 'think', 'want', 'need', 'does',
    'did', 'done', 'been', 'being', 'get', 'got', 'give', 'take', 'make',
    'made', 'use', 'used', 'using', 'way', 'ways', 'thing', 'things', 'one',
    'two', 'new', 'good', 'best', 'better', 'well', 'really', 'actually',
    'maybe', 'perhaps', 'sure', 'yes', 'no',
    // французские
    'le', 'la', 'les', 'de', 'des', 'du', 'un', 'une', 'est', 'sont', 'avec',
    'pour', 'dans', 'sur', 'comment', 'quoi', 'pourquoi', 'quand', 'où', 'ou',
    'qui', 'que', 'quel', 'quelle', 'quels', 'quelles', 'ce', 'cette', 'ces',
    'il', 'elle', 'ils', 'elles', 'je', 'tu', 'nous', 'vous', 'mon', 'ma',
    'mes', 'ton', 'ta', 'tes', 'son', 'sa', 'ses', 'notre', 'nos', 'votre',
    'vos', 'leur', 'leurs', 'plus', 'moins', 'très', 'tres', 'aussi', 'mais',
    'donc', 'alors', 'encore', 'déjà', 'deja', 'toujours', 'jamais', 'bien',
    'mal', 'peut', 'peux', 'être', 'etre', 'avoir', 'fait', 'faire', 'dire',
  };

  /// Домены-«помойки»: выдача этих хостов почти всегда не по запросу
  /// (поисковики/порталы) либо дублирует наши собственные источники.
  static const Set<String> _junkHosts = {
    'bing.com', 'go.microsoft.com', 'microsoft.com', 'google.com',
    'yandex.ru', 'yandex.com', 'mail.ru', 'rambler.ru', 'duckduckgo.com',
    'wikipedia.org', 'youtube.com', 'pinterest.com', 'facebook.com',
    'instagram.com', 'tiktok.com', 'vk.com', 'twitter.com', 'x.com',
  };

  /// Содержательные слова запроса: без стоп-слов и короткого мусора.
  /// Порядок сохранён, дубликаты убраны.
  static List<String> _searchKeywords(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (final w in text
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
      if (w.length < 3) continue;
      if (_searchStopwords.contains(w)) continue;
      if (seen.add(w)) out.add(w);
    }
    return out;
  }

  /// Поисковый запрос: до 5 ключевых слов вместо сырой разговорной
  /// фразы («расскажи мне про…» → реальные слова). Если содержательных
  /// слов нет — отдаём запрос как есть, без знаков препинания.
  static String _searchQuery(String query) {
    final words = _searchKeywords(query);
    if (words.isEmpty) {
      return query.trim().replaceAll(RegExp(r'[?!.,;:«»"()]+$'), '');
    }
    return words.take(5).join(' ');
  }

  /// Реальный веб-поиск без ключей: Bing (HTML — настоящие веб-результаты)
  /// + DuckDuckGo Instant Answer + Wikipedia (на языке пользователя).
  /// Параллельно, с быстрыми таймаутами. Собираем до 6 фактов в компактный
  /// текст для контекста ИИ (маленькая модель «задыхается» от огромного
  /// контекста и отвечает пусто — поэтому лимит строже, чем раньше).
  /// Возвращает пустую строку, если ничего найти не удалось.
  static Future<String> webSearch(String query, String languageCode) async {
    final results = <String>[];
    const ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) Keramika/1.3'};

    /// Простое декодирование HTML-сущностей для заголовков/сниппетов.
    String clean(String s) => s
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
          final code = int.tryParse(m.group(1) ?? '');
          if (code == null) return m.group(0)!;
          return String.fromCharCode(code);
        })
        .trim();

    /// Поисковый запрос: разговорную фразу («расскажи мне про…») чистим
    /// до реальных ключевых слов — иначе поисковик роет не то («говно»).
    final searchQuery = _searchQuery(query);
    if (searchQuery.trim().isEmpty) return '';

    /// Ключевые слова запроса (без стоп-слов) — для фильтрации мусора:
    /// сниппет, не содержащий ни одного слова запроса, почти наверняка
    /// не про то, что спрашивают.
    final keywords = _searchKeywords(searchQuery);

    /// Релевантен ли текст запросу: одно содержательное слово (длиной ≥4)
    /// ИЛИ два любых слова запроса. Слабый фильтр «хотя бы одно слово»
    /// пропускал «связанные запросы» и рекламу.
    bool relevant(String t) {
      if (keywords.isEmpty) return true;
      final lower = t.toLowerCase();
      var hits = 0;
      var strong = 0;
      for (final kw in keywords) {
        if (!lower.contains(kw)) continue;
        hits++;
        if (kw.length >= 4) strong++;
      }
      return strong >= 1 || hits >= 2;
    }

    /// Не больше [max] результатов с одного домена — иначе контекст
    /// забивается одним сайтом, и Ада «тонет» в его мусоре.
    final domainCounts = <String, int>{};
    bool domainBudget(String host, int max) {
      final c = (domainCounts[host] ?? 0) + 1;
      if (c > max) return false;
      domainCounts[host] = c;
      return true;
    }

    /// Нормализация для дедупликации: без домена-метки, нижний регистр,
    /// схлопнутые пробелы — чтобы Bing/DDG/Wiki «двоение» не попадало в контекст.
    String normKey(String t) {
      final s = t
          .replaceAll(RegExp(r'\[[a-z0-9.-]+\]\s*$'), '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return s.length > 60 ? s.substring(0, 60) : s;
    }

    /// Bing: настоящие результаты веб-поиска из HTML. DuckDuckGo Lite
    /// начал отдавать бот-челлендж вместо выдачи (парсер молча возвращал
    /// пусто — Ада отвечала «из головы», веб-поиск не работал). Bing
    /// отдаёт обычный HTML с блоками <li class="b_algo">.
    Future<void> bingSearch() async {
      try {
        final resp = await http
            .get(
              Uri.parse(
                'https://www.bing.com/search'
                '?q=${Uri.encodeQueryComponent(searchQuery)}'
                '&count=10'
                '&setlang=${languageCode == 'ru' ? 'ru' : 'en'}'
                '&cc=${languageCode == 'ru' ? 'RU' : 'US'}',
              ),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/120.0.0.0 Safari/537.36',
                'Accept-Language': languageCode == 'ru'
                    ? 'ru-RU,ru;q=0.9'
                    : 'en-US,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) return;
        final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
        // Бот-челлендж: если блоков результатов нет — выходим тихо.
        if (!body.contains('b_algo')) return;
        final blockRe = RegExp(
          r'<li class="b_algo"[^>]*>.*?</li>',
          dotAll: true,
        );
        final titleRe = RegExp(r'<h2[^>]*>\s*<a[^>]*>(.*?)</a>', dotAll: true);
        final hrefRe = RegExp(r'<h2[^>]*>\s*<a[^>]*href="([^"]+)"');
        final snipRe = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
        for (final m in blockRe.allMatches(body)) {
          final block = m.group(0)!;
          final tm = titleRe.firstMatch(block);
          if (tm == null) continue;
          final title = clean(tm.group(1) ?? '');
          if (title.isEmpty) continue;
          String host = '';
          final hm = hrefRe.firstMatch(block);
          if (hm != null) {
            final raw = hm.group(1) ?? '';
            host = _hostOf(_bingRealUrl(raw) ?? raw);
          }
          if (host.isEmpty || _junkHosts.contains(host)) continue;
          final sm = snipRe.firstMatch(block);
          final snip = sm != null ? clean(sm.group(1) ?? '') : '';
          if (!relevant('$title $snip')) continue;
          // Заголовок без сниппета — почти всегда «связанный запрос»/мусор.
          if (snip.length < 40 &&
              !keywords.any(title.toLowerCase().contains)) {
            continue;
          }
          if (!domainBudget(host, 2)) continue;
          final src = ' [$host]';
          final line = snip.length >= 40 ? '$title — $snip$src' : '$title$src';
          results.add(line);
          if (results.length >= 10) break;
        }
      } catch (_) {}
    }

    /// Bing в формате RSS: тот же поиск, но чистый XML. Ссылки настоящие
    /// (без base64-редиректа), сниппеты без HTML-тегов. Дубли с HTML-
    /// версией отсеиваются дедупликацией ниже — это запасной парсер,
    /// который не зависит от вёрстки страницы Bing.
    Future<void> bingRss() async {
      try {
        final resp = await http
            .get(
              Uri.parse(
                'https://www.bing.com/search'
                '?q=${Uri.encodeQueryComponent(searchQuery)}'
                '&format=rss'
                '&setlang=${languageCode == 'ru' ? 'ru' : 'en'}'
                '&cc=${languageCode == 'ru' ? 'RU' : 'US'}',
              ),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/120.0.0.0 Safari/537.36',
                'Accept-Language': languageCode == 'ru'
                    ? 'ru-RU,ru;q=0.9'
                    : 'en-US,en;q=0.9',
              },
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode != 200) return;
        final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
        if (!body.contains('<item>')) return;
        final itemRe = RegExp(r'<item>.*?</item>', dotAll: true);
        final titleRe = RegExp(r'<title>(.*?)</title>', dotAll: true);
        final linkRe = RegExp(r'<link>(.*?)</link>', dotAll: true);
        final descRe = RegExp(r'<description>(.*?)</description>', dotAll: true);
        for (final m in itemRe.allMatches(body)) {
          if (results.length >= 10) break;
          final item = m.group(0)!;
          final title = clean(titleRe.firstMatch(item)?.group(1) ?? '');
          if (title.isEmpty) continue;
          final link = clean(linkRe.firstMatch(item)?.group(1) ?? '');
          final host = _hostOf(link);
          if (host.isEmpty || _junkHosts.contains(host)) continue;
          final snip = clean(descRe.firstMatch(item)?.group(1) ?? '');
          if (!relevant('$title $snip')) continue;
          // Заголовок без сниппета — почти всегда «связанный запрос»/мусор.
          if (snip.length < 40 &&
              !keywords.any(title.toLowerCase().contains)) {
            continue;
          }
          if (!domainBudget(host, 2)) continue;
          final src = ' [$host]';
          results.add(
            snip.length >= 40 ? '$title — $snip$src' : '$title$src',
          );
        }
      } catch (_) {}
    }

    /// DuckDuckGo Instant Answer: короткая справка/абстракт для сущностей.
    /// RelatedTopics часто возвращают мусор не по запросу — фильтруем по
    /// ключевым словам и берём максимум 3, иначе «ищет не по запросу».
    Future<void> ddgInstant() async {
      try {
        final resp = await http
            .get(
              Uri.parse(
                'https://api.duckduckgo.com/'
                '?q=${Uri.encodeQueryComponent(searchQuery)}'
                '&format=json&no_html=1&skip_disambig=1',
              ),
              headers: ua,
            )
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) return;
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final abstractText = data['AbstractText'] as String? ?? '';
        if (abstractText.trim().length >= 60 &&
            relevant(abstractText) &&
            domainBudget('duckduckgo.com', 3)) {
          results.add('${abstractText.trim()} [duckduckgo.com]');
        }
        final topics = data['RelatedTopics'] as List? ?? [];
        var ddgAdded = 0;
        for (final t in topics) {
          if (ddgAdded >= 3) break;
          if (t is! Map<String, dynamic>) continue;
          final nested = t['Topics'];
          if (nested is List) {
            for (final sub in nested) {
              if (ddgAdded >= 3) break;
              if (sub is Map<String, dynamic>) {
                final text = sub['Text'] as String? ?? '';
                if (text.trim().isNotEmpty &&
                    relevant(text) &&
                    domainBudget('duckduckgo.com', 3)) {
                  results.add('${text.trim()} [duckduckgo.com]');
                  ddgAdded++;
                }
              }
            }
          } else {
            final text = t['Text'] as String? ?? '';
            if (text.trim().isNotEmpty &&
                relevant(text) &&
                domainBudget('duckduckgo.com', 3)) {
              results.add('${text.trim()} [duckduckgo.com]');
              ddgAdded++;
            }
          }
        }
      } catch (_) {}
    }

    /// Wikipedia на языке пользователя.
    Future<void> wiki() async {
      final lang = switch (languageCode) {
        'ru' => 'ru',
        'fr' => 'fr',
        _ => 'en',
      };
      try {
        final resp = await http
            .get(
              Uri.parse(
                'https://$lang.wikipedia.org/w/api.php'
                '?action=query&list=search&srsearch='
                '${Uri.encodeQueryComponent(searchQuery)}'
                '&format=json&srlimit=6&srprop=snippet',
              ),
              headers: ua,
            )
            .timeout(const Duration(seconds: 4));
        if (resp.statusCode != 200) return;
        final data =
            jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final search =
            (data['query'] as Map<String, dynamic>?)?['search'] as List? ?? [];
        for (final s in search) {
          if (s is! Map<String, dynamic>) continue;
          final title = s['title'] as String? ?? '';
          final snippet = clean(s['snippet'] as String? ?? '');
          if (title.trim().isEmpty ||
              !relevant('$title $snippet') ||
              !domainBudget('$lang.wikipedia.org', 3)) {
            continue;
          }
          results.add(
            snippet.isNotEmpty
                ? '$title: $snippet [${lang}.wikipedia.org]'
                : '$title [${lang}.wikipedia.org]',
          );
        }
      } catch (_) {}
    }

    // Параллельно: Bing + Instant Answer + Wikipedia; ждём не дольше
    // ~5 секунд, чтобы успеть собрать глубокий контекст.
    await Future.wait([
      bingSearch(),
      bingRss(),
      ddgInstant(),
      wiki(),
    ]).timeout(const Duration(seconds: 6), onTimeout: () => <void>[]);

    // Дедупликация по нормализованному ключу, лимит 6 фактов и обрезка
    // каждого до ~150 симв: маленькая модель глушится огромным контекстом
    // и отвечает пусто. Чистим мусор, не содержащий слов запроса.
    /// Обрезка до ~150 символов, НЕ отрубая метку источника [домен] —
    /// иначе в конце ответа Ады пропадает домен из списка источников.
    String truncate(String r) {
      if (r.length <= 150) return r;
      final marker = RegExp(r'\s+\[[a-z0-9.-]+\]$').firstMatch(r);
      if (marker == null) return '${r.substring(0, 150)}…';
      final body = r.substring(0, marker.start);
      return '${body.length > 140 ? '${body.substring(0, 140)}…' : body}'
          '${marker.group(0)}';
    }

    final seen = <String>{};
    final unique = <String>[];
    for (final r in results) {
      final key = normKey(r);
      if (key.isEmpty || !seen.add(key)) continue;
      unique.add(truncate(r));
      if (unique.length >= 6) break;
    }
    if (unique.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < unique.length; i++) {
      sb.writeln('${i + 1}. ${unique[i]}');
    }
    return sb.toString().trim();
  }

  /// Домен из URL (www. убираем) — для пометки источника в результатах.
  static String _hostOf(String url) {
    try {
      final u = Uri.parse(url);
      final h = u.host;
      if (h.isEmpty) return '';
      return h.replaceFirst(RegExp(r'^www.'), '');
    } catch (_) {
      return '';
    }
  }

  /// Bing прячет реальный URL в редиректе /ck/a?...&u=a1<base64>...
  /// Декодирует base64-часть и возвращает настоящий адрес.
  static String? _bingRealUrl(String href) {
    try {
      // В HTML ссылки приходят с &amp; вместо & — сначала разворачиваем.
      final decoded = href.replaceAll('&amp;', '&');
      final u = Uri.parse(decoded);
      if (!u.host.contains('bing.com')) return decoded;
      final enc = u.queryParameters['u'];
      if (enc == null || enc.isEmpty) return null;
      var b64 = enc.startsWith('a1') ? enc.substring(2) : enc;
      b64 = b64.replaceAll('-', '+').replaceAll('_', '/');
      while (b64.length % 4 != 0) {
        b64 = '$b64=';
      }
      final real = utf8.decode(base64.decode(b64), allowMalformed: true);
      return real.isNotEmpty ? real : null;
    } catch (_) {
      return null;
    }
  }

  /// Цепочка моделей: Ада (HF) → ПАРАЛЛЕЛЬНЫЙ раунд бесплатных анонимных
  /// (Kilo + LLM7 + Pollinations одновременно, кто первый) → AI Horde →
  /// OVHcloud → ключ Poolside. Упавшие хосты уходят в кулдаун (10 мин),
  /// чтобы при заблокированной сети ответ падал на живой резерв быстро.
  static Future<String> _sendChain(
    String userText,
    List<AiMessage> history,
    String languageCode, {
    // false — пропустить встроенную Аду (HF): нужно для повтора-«лингвогарда»,
    // чтобы не жечь суточный лимит 100 сообщений дважды на одно сообщение.
    bool useHf = true,
  }) async {
    final sw = Stopwatch()..start();

    // 1. Встроенная Ада — главный путь (100 сообщений в день).
    if (useHf &&
        await _hfQuotaAvailable() &&
        !_hfTemporarilyUnavailable &&
        !_onCooldown('hf')) {
      try {
        final answer = await _sendHuggingFace(
          userText,
          history,
          languageCode,
        ).timeout(const Duration(seconds: 22));
        await _incrementHfQuota();
        _setModel('ada-0.0.3');
        return answer;
      } catch (e) {
        // 402 — исчерпанный кредит, 401/403 — невалидный ключ. Раньше тут
        // был бан на 15 минут — но СВОЙ Space Ады работает БЕЗ встроенного
        // ключа, и бан мешал повторной попытке после его «пробуждения».
        // Короткого кулдауна (3 мин) достаточно.
        _markCooldown('hf');
      }
    }

    // 2. Параллельный раунд: три бесплатных анонимных провайдера разом,
    //    ждём не дольше 8 секунд суммарно. Кто первый ответил — того
    //    и берём (метку модели провайдер выставляет сам).
    final round = await Future.wait([
      _tryProvider('kilo', () => _sendKilo(userText, languageCode), 12),
      _tryProvider('llm7', () => _sendLLM7(userText, languageCode), 12),
      _tryProvider(
        'pollinations',
        () => _sendPollinations(userText, languageCode),
        12,
      ),
    ]);
    for (final answer in round) {
      if (answer != null && answer.trim().isNotEmpty) return answer;
    }

    // Дальше — только если ещё остался бюджет времени.
    if (sw.elapsed > const Duration(seconds: 22)) {
      throw Exception('Бюджет времени исчерпан');
    }

    // 3. AI Horde — очередь, может занять время; отдельный бюджет 16 с.
    final horde = await _tryProvider(
      'horde',
      () => _sendAiHorde(userText, languageCode),
      16,
    );
    if (horde != null && horde.trim().isNotEmpty) {
      _setModel('AI Horde');
      return horde;
    }

    // 4. OVHcloud AI Endpoints — бесплатный резерв.
    final ovh = await _tryProvider(
      'ovh',
      () => _sendOvhcloud(userText, languageCode),
      8,
    );
    if (ovh != null && ovh.trim().isNotEmpty) {
      _setModel('OVHCloud');
      return ovh;
    }

    // 5. Ключ Poolside/Laguna — самый последний резерв, если есть.
    if (!_onCooldown('poolside')) {
      final poolsideKey = await SettingsService.loadAiKey();
      if (poolsideKey.isNotEmpty) {
        try {
          final answer = await _sendPoolside(
            userText,
            history,
            poolsideKey,
            languageCode,
          ).timeout(const Duration(seconds: 20));
          if (_isRefusal(answer)) {
            throw Exception('Laguna safety refusal');
          }
          _setModel('Laguna');
          return answer;
        } catch (e) {
          _markCooldown('poolside');
          final s = e.toString();
          if (s.contains('401') ||
              s.contains('403') ||
              s.contains('Unauthorized')) {
            // Недействительный ключ — стираем, чтобы не пробовать вечно.
            await SettingsService.saveAiKey('');
          }
        }
      }
    }

    throw Exception('Все провайдеры недоступны');
  }

  /// Отменяет последнее действие Ады: удаляет созданное или восстанавливает
  /// удалённое. Возвращает текст-подтверждение.
  static Future<String> undoLastAction() async {
    final a = lastAction;
    if (a == null) return 'Нечего отменять';
    try {
      if (a.wasCreate) {
        // Было создано → удаляем.
        switch (a.type) {
          case 'habit':
            await HabitService().load();
            await HabitService().remove(a.id);
            break;
          case 'task':
            await TaskService().load();
            await TaskService().remove(a.id);
            break;
          case 'alarm':
            await AlarmService().load();
            await AlarmService().remove(a.id);
            break;
          case 'reality_check':
            await RealityCheckService().load();
            await RealityCheckService().remove(a.id);
            break;
          case 'meal':
            await NutritionService().load();
            await NutritionService().remove(a.id);
            break;
        }
      } else {
        // Было удалено → восстанавливаем.
        switch (a.type) {
          case 'habit':
            await HabitService().load();
            await HabitService().add(a.item! as Habit);
            break;
          case 'task':
            await TaskService().load();
            await TaskService().add(a.item! as Task);
            break;
          case 'alarm':
            await AlarmService().load();
            await AlarmService().add(a.item! as Alarm);
            break;
          case 'reality_check':
            await RealityCheckService().load();
            await RealityCheckService().add(a.item! as RealityCheck);
            break;
          case 'meal':
            await NutritionService().load();
            await NutritionService().add(a.item! as Meal);
            break;
        }
      }
      lastAction = null;
      return 'Отменено: ${a.label} ↩';
    } catch (e) {
      return 'Не получилось отменить: $e';
    }
  }

  // ---- Лимит 100 сообщений в день (встроенная HF-модель) ----

  static const _hfDateKey = 'ai_hf_date';
  static const _hfCountKey = 'ai_hf_count';

  static String _todayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static Future<bool> _hfQuotaAvailable() async {
    final date = globalPrefs.getString(_hfDateKey);
    final count = globalPrefs.getInt(_hfCountKey) ?? 0;
    if (date != _todayKey()) return true;
    return count < dailyHfLimit;
  }

  static Future<void> _incrementHfQuota() async {
    final date = globalPrefs.getString(_hfDateKey);
    final count =
        (date == _todayKey() ? globalPrefs.getInt(_hfCountKey) ?? 0 : 0) + 1;
    await globalPrefs.setString(_hfDateKey, _todayKey());
    await globalPrefs.setInt(_hfCountKey, count);
  }

  /// Сколько сообщений через Аду осталось сегодня (для подсказки в чате).
  static Future<int> hfRemainingToday() async {
    final date = globalPrefs.getString(_hfDateKey);
    if (date != _todayKey()) return dailyHfLimit;
    final count = globalPrefs.getInt(_hfCountKey) ?? 0;
    return (dailyHfLimit - count).clamp(0, dailyHfLimit);
  }

  /// Какая модель реально ответила (заполняется цепочкой _sendChain).
  static String _lastModel = '';
  static String get lastUsedModel => _lastModel;
  static void _setModel(String label) => _lastModel = label;

  /// Текущая модель: если кто-то уже отвечал в этой сессии — показываем его
  /// (например «Kilo · openrouter/free»); иначе дефолт по квоте Ады.
  static Future<String> currentModelLabel() async {
    if (_lastModel.isNotEmpty) return _lastModel;
    if (await hfRemainingToday() > 0) return 'ada-0.0.3';
    final key = await SettingsService.loadAiKey();
    if (key.isNotEmpty) return 'Laguna';
    return 'FREE';
  }

  // ---- Ада-трекинг: утренний отчёт и вечерний разбор прямо в ЧАТ ----

  /// Ключ файла истории чата (тот же, что в ai_guide.dart).
  static const _chatHistoryKey = 'ai_chat_history';

  /// Тик доставки: открытый чат слушает его и перечитывает историю, чтобы
  /// утренний/вечерний отчёт появился в ленте сразу, без переоткрытия.
  static final ValueNotifier<int> adaReportTick = ValueNotifier<int>(0);

  static bool _deliveringReports = false;

  /// Доставляет отчёты Ады в ЧАТ, если наступило время и они ещё не
  /// доставлены сегодня: утро — после 08:00, вечер — после 21:00.
  /// Пишет прямо в историю чата (переживает перезапуск) и поднимает
  /// [adaReportTick], чтобы открытый чат подхватил сообщение без паузы.
  /// Возвращает доставленные сообщения (пусто — делать нечего).
  static Future<List<AiMessage>> maybeDeliverAdaReports(
    String languageCode,
  ) async {
    if (_deliveringReports) return const [];
    final tracking = await SettingsService.loadAiTracking();
    if (!tracking) return const [];
    if (languageCode == 'system' || languageCode.isEmpty) {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final delivered = <AiMessage>[];
    _deliveringReports = true;
    try {
      // Утро: наступило 08:00, отчёт ещё не был.
      if (globalPrefs.getString('ada_track_morning') != today &&
          now.hour >= 8) {
        try {
          final text = await morningReportText(languageCode);
          if (text.trim().isNotEmpty) {
            delivered.add(AiMessage(isUser: false, text: text));
            await globalPrefs.setString('ada_track_morning', today);
          }
        } catch (_) {}
      }
      // Вечер: наступило 21:00, разбор ещё не был.
      if (globalPrefs.getString('ada_track_evening') != today &&
          now.hour >= 21) {
        try {
          final text = await eveningReportText(languageCode);
          if (text.trim().isNotEmpty) {
            delivered.add(AiMessage(isUser: false, text: text));
            await globalPrefs.setString('ada_track_evening', today);
          }
        } catch (_) {}
      }
      if (delivered.isNotEmpty) {
        await _appendToChatHistory(delivered);
        adaReportTick.value++;
      }
    } finally {
      _deliveringReports = false;
    }
    return delivered;
  }

  /// Дописывает сообщения в файл истории чата (до 1000, как в UI).
  static Future<void> _appendToChatHistory(List<AiMessage> msgs) async {
    try {
      var list = <AiMessage>[];
      final raw = await JsonFile.read(_chatHistoryKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list = decoded
              .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
      list.addAll(msgs);
      if (list.length > 1000) list = list.sublist(list.length - 1000);
      await JsonFile.write(
        _chatHistoryKey,
        jsonEncode(list.map((m) => m.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Текст утреннего отчёта: сначала живой тёплый текст от встроенного ИИ
  /// (с учётом реальных задач/привычек/будильников), при недоступности —
  /// проверенный оффлайн-шаблон. Пишется в чат, не в уведомления.
  static Future<String> morningReportText(String languageCode) async {
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    try {
      await Future.wait([
        TaskService().load(),
        HabitService().load(),
        AlarmService().load(),
      ]);
    } catch (_) {}
    final tasks = TaskService().tasks;
    final habits = HabitService().habits;
    final alarms = AlarmService().alarms;
    final ru = languageCode == 'ru';
    // Живой текст от ИИ.
    try {
      final ctx = StringBuffer();
      if (tasks.isNotEmpty) {
        ctx.write('Задачи: ${tasks.take(5).map((t) => t.title).join(', ')}. ');
      }
      if (habits.isNotEmpty) {
        ctx.write(
          'Привычки: ${habits.take(5).map((h) => h.name).join(', ')}. ',
        );
      }
      if (alarms.isNotEmpty) {
        final a = alarms.first;
        ctx.write(
          'Будильник: ${a.time.hour.toString().padLeft(2, '0')}:'
          '${a.time.minute.toString().padLeft(2, '0')}. ',
        );
      }
      final raw = await send(
        userText:
            'Ты — Ада, тёплый женский проводник приложения Keramika. Напиши короткое утреннее сообщение (2–4 предложения): «что сегодня по плану», используя данные: ${ctx.toString().trim()}. Обращайся тепло, по-дружески, на «ты», без канцелярита, без списков-буллетов и без заголовков.',
        history: const [],
        languageCode: languageCode,
      );
      final t = raw.trim();
      if (t.isNotEmpty) return t;
    } catch (_) {
      // ИИ недоступен — ниже шаблон.
    }
    // Оффлайн-шаблон.
    final parts = <String>[
      if (tasks.isNotEmpty)
        ru ? '${tasks.length} задач' : '${tasks.length} tasks',
      if (habits.isNotEmpty)
        ru ? '${habits.length} привычек' : '${habits.length} habits',
      if (alarms.isNotEmpty)
        ru
            ? 'будильник ${alarms.first.time.hour.toString().padLeft(2, '0')}:'
                  '${alarms.first.time.minute.toString().padLeft(2, '0')}'
            : 'alarm at ${alarms.first.time.hour.toString().padLeft(2, '0')}:'
                  '${alarms.first.time.minute.toString().padLeft(2, '0')}',
    ];
    if (parts.isEmpty) {
      return ru
          ? 'Доброе утро! ☀️ Пока ничего не запланировано — добавь первую задачу или привычку!'
          : 'Good morning! ☀️ Nothing planned yet — add your first task or habit!';
    }
    return ru
        ? 'Доброе утро! ☀️ Сегодня: ${parts.join(', ')}. Давай сделаем этот день!'
        : 'Good morning! ☀️ Today: ${parts.join(', ')}. Let us make this day count!';
  }

  /// Текст вечернего разбора: сначала живой текст от встроенного ИИ
  /// (по итогам дня), при недоступности — оффлайн-шаблон.
  static Future<String> eveningReportText(String languageCode) async {
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    try {
      await Future.wait([HabitService().load(), TaskService().load()]);
    } catch (_) {}
    final habits = HabitService().habits;
    final tasks = TaskService().tasks;
    final ru = languageCode == 'ru';
    final done = habits.where((h) => h.doneToday).length;
    final left = tasks.where((t) => !t.done).length;
    // Живой текст от ИИ.
    try {
      final ctx = StringBuffer();
      if (habits.isNotEmpty) {
        ctx.write('Выполнено привычек: $done из ${habits.length}. ');
      }
      if (left > 0) {
        ctx.write('Незакрытых задач: $left. ');
      }
      final raw = await send(
        userText:
            'Ты — Ада, тёплый женский проводник приложения Keramika. Напиши короткий вечерний разбор дня (2–4 предложения): итоги по данным (${ctx.toString().trim()}) и добрый вопрос, как прошёл день. Обращайся тепло, по-дружески, на «ты», без канцелярита, без списков и без заголовков.',
        history: const [],
        languageCode: languageCode,
      );
      final t = raw.trim();
      if (t.isNotEmpty) return t;
    } catch (_) {
      // ИИ недоступен — ниже шаблон.
    }
    // Оффлайн-шаблон.
    final buf = StringBuffer(ru ? 'Вечерний разбор 🌙 ' : 'Evening review 🌙 ');
    if (habits.isNotEmpty) {
      buf.write(
        ru
            ? 'выполнено $done из ${habits.length} привычек. '
            : '$done of ${habits.length} habits done. ',
      );
    }
    if (left > 0) {
      buf.write(ru ? 'Осталось $left задач. ' : '$left tasks left. ');
    }
    buf.write(ru ? 'Как прошёл твой день?' : 'How was your day?');
    return buf.toString();
  }

  /// Награды Ады: одноразовые поздравления за достижения.
  /// - Стрики привычек на вехах 3/7/14/30/60/100/150/200/300/365 дней
  ///   (награждается КАЖДАЯ веха, ключ = habit.id + streak — повторно
  ///   не выдаётся, пока серия не дорастёт до следующей вехи).
  /// - «Все задачи выполнены» — раз в день.
  /// Возвращает тексты наград и помечает их выданными (globalPrefs).
  static Future<List<String>> collectRewards(String languageCode) async {
    // 'system' (язык устройства) должен превращаться в конкретный код —
    // иначе награды всегда на английском (startsWith('ru') не сработает).
    if (languageCode == 'system') {
      languageCode = await SettingsService.resolveLanguageCode();
    }
    final ru = languageCode.startsWith('ru');
    final fr = languageCode.startsWith('fr');
    final rewards = <String>[];
    try {
      await Future.wait([HabitService().load(), TaskService().load()]);
    } catch (_) {}
    final done = (globalPrefs.getStringList('ai_rewards_done') ?? <String>[])
        .toSet();
    var changed = false;
    String text(String ruT, String frT, String enT) =>
        ru ? ruT : (fr ? frT : enT);
    // Ежедневная награда Ады: КАЖДЫЙ день, пока чат открывается, Ада
    // говорит что-то тёплое и «выдаёт торт». Сообщения чередуются по дню
    // года — каждый день новое, повторов не бывает чаще раза в цикл.
    final dailyKey = 'daily_${_todayKey()}';
    if (!done.contains(dailyKey)) {
      done.add(dailyKey);
      changed = true;
      const dailyRu = [
        '🎁 Хорошо держишься, держи торт! 🎂',
        '🎁 Новый день — новый шаг вперёд. Ты молодец! 🌟',
        '🎁 С возвращением! Я скучала по тебе 🤗',
        '🎁 Отличный день, чтобы быть собой. Держи награду! 🍀',
        '🎁 Ты здесь — это уже победа. Награда твоя! 🏅',
        '🎁 Продолжай в том же духе, я горжусь тобой 💪',
        '🎁 Сегодня твой день. Наслаждайся! 🌈',
        '🎁 Ты делаешь больше, чем думаешь. Держи печеньку! 🍪',
      ];
      const dailyFr = [
        '🎁 Tiens bon, voilà un gâteau ! 🎂',
        '🎁 Un nouveau jour, un pas en avant. Bravo ! 🌟',
        '🎁 Ravie de te revoir ! Tu m\'as manqué 🤗',
        '🎁 Un beau jour pour être toi-même. Voici ta récompense ! 🍀',
        '🎁 Tu es là, c\'est déjà une victoire. Récompense à toi ! 🏅',
        '🎁 Continue comme ça, je suis fière de toi 💪',
        '🎁 Aujourd\'hui est ton jour. Profites-en ! 🌈',
        '🎁 Tu fais plus que tu ne crois. Tiens, un cookie ! 🍪',
      ];
      const dailyEn = [
        '🎁 Keep it up, here\'s a cake! 🎂',
        '🎁 A new day, a step forward. Well done! 🌟',
        '🎁 Welcome back! I missed you 🤗',
        '🎁 A great day to be yourself. Here\'s your reward! 🍀',
        '🎁 You\'re here — that\'s already a win. Reward yours! 🏅',
        '🎁 Keep going, I\'m proud of you 💪',
        '🎁 Today is your day. Enjoy! 🌈',
        '🎁 You do more than you think. Here\'s a cookie! 🍪',
      ];
      final now = DateTime.now();
      final dayOfYear = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(now.year, 1, 1)).inDays;
      final list = ru ? dailyRu : (fr ? dailyFr : dailyEn);
      rewards.add(list[dayOfYear % list.length]);
    }
    // Вехи стриков.
    const milestones = [3, 7, 14, 30, 60, 100, 150, 200, 300, 365];
    for (final h in HabitService().habits) {
      if (h.streak > 0 && milestones.contains(h.streak)) {
        final key = 'streak_${h.id}_${h.streak}';
        if (!done.contains(key)) {
          done.add(key);
          changed = true;
          rewards.add(
            text(
              '🎖️ ${h.name}: серия ${_streakUnit(h.streak, ru)} — ${h.streak}! Ты настоящий герой, я горжусь тобой ❤️',
              '🎖️ ${h.name} : série de ${h.streak} jours ! Tu es un vrai héros, je suis fière de toi ❤️',
              '🎖️ ${h.name}: ${h.streak}-day streak! You are a true hero, I am so proud of you ❤️',
            ),
          );
        }
      }
    }
    // Все задачи выполнены — раз в день.
    final tasks = TaskService().tasks;
    if (tasks.isNotEmpty && tasks.every((t) => t.done)) {
      final key = 'all_done_${_todayKey()}';
      if (!done.contains(key)) {
        done.add(key);
        changed = true;
        rewards.add(
          text(
            '🏆 Все задачи выполнены! День закрыт на отлично. Обнимаю тебя 💛',
            '🏆 Toutes les tâches sont terminées ! Journée parfaite. Gros câlin 💛',
            '🏆 All tasks done! Day closed perfectly. Big hug 💛',
          ),
        );
      }
    }
    // Первые создания — одноразовые награды.
    if (HabitService().habits.isNotEmpty && !done.contains('first_habit')) {
      done.add('first_habit');
      changed = true;
      rewards.add(
        text(
          '🎁 Первая привычка создана! Ты начал(а) — это уже половина победы 💪',
          '🎁 Première habitude créée ! Tu as commencé — c’est déjà une victoire 💪',
          '🎁 First habit created! Starting is half the battle 💪',
        ),
      );
    }
    if (tasks.isNotEmpty && !done.contains('first_task')) {
      done.add('first_task');
      changed = true;
      rewards.add(
        text(
          '🎁 Первая задача создана! Держи план и иди к нему 🚀',
          '🎁 Première tâche créée ! Garde le cap 🚀',
          '🎁 First task created! Stay on track 🚀',
        ),
      );
    }
    // Вехи общего количества выполненных задач (счётчик нарастает всю жизнь).
    final doneTotal = globalPrefs.getInt('ai_tasks_done_total') ?? 0;
    const taskMilestones = [5, 10, 25, 50, 100, 200, 365];
    // Если счётчик уменьшился (пользователь снял галочки ниже вехи),
    // честно стираем выданные награды за эту веху — иначе Ада наврёт.
    final expired = done
        .where(
          (k) =>
              k.startsWith('tasks_done_') &&
              doneTotal < int.parse(k.substring('tasks_done_'.length)),
        )
        .toList();
    if (expired.isNotEmpty) {
      done.removeAll(expired);
      changed = true;
    }
    for (final n in taskMilestones) {
      if (doneTotal >= n && !done.contains('tasks_done_$n')) {
        done.add('tasks_done_$n');
        changed = true;
        rewards.add(
          text(
            '🎖️ $doneTotal задач выполнено за всё время — ты машина! 🔥',
            '🎖️ $doneTotal tâches accomplies en tout — tu es une machine ! 🔥',
            '🎖️ $doneTotal tasks completed in total — you are a machine! 🔥',
          ),
        );
      }
    }
    if (changed) {
      await globalPrefs.setStringList('ai_rewards_done', done.toList());
    }
    return rewards;
  }

  static String _streakUnit(int n, bool ru) {
    if (!ru) return 'days';
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }

  // ---- Инструменты Ады: создание привычек/задач/будильников/РП ----

  static List<Map<String, dynamic>> _tools() => [
    {
      'type': 'function',
      'function': {
        'name': 'create_habit',
        'description':
            'Создать новую привычку. type=good для полезной привычки, type=bad для борьбы с неидеальным.',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Название привычки'},
            'notes': {
              'type': 'string',
              'description': 'Заметки или описание (необязательно)',
            },
            'type': {
              'type': 'string',
              'enum': ['good', 'bad'],
              'description':
                  'good — полезная привычка, bad — привычка, от которой избавляемся',
            },
            'icon': {
              'type': 'string',
              'description':
                  'Иконка: water, run, book, gym, sleep, food, smoke, phone, coffee, music, code, study, walk, spa, brain, cake, pets, eco, work, clean, shop, star, heart, check',
            },
          },
          'required': ['name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_task',
        'description': 'Создать новую задачу',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Название задачи'},
            'category': {
              'type': 'string',
              'description': 'Категория (необязательно)',
            },
            'icon': {'type': 'string', 'description': 'Иконка (необязательно)'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_alarm',
        'description': 'Создать будильник на определённое время',
        'parameters': {
          'type': 'object',
          'properties': {
            'hour': {'type': 'integer', 'description': 'Час (0-23)'},
            'minute': {'type': 'integer', 'description': 'Минуты (0-59)'},
            'label': {'type': 'string', 'description': 'Название будильника'},
            'repeat_days': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description':
                  'Дни недели повтора: 1=Пн ... 7=Вс. Пусто — один раз.',
            },
          },
          'required': ['hour', 'minute'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_reality_check',
        'description': 'Создать проверку реальности',
        'parameters': {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description': 'Текст проверки реальности',
            },
          },
          'required': ['question'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_meal',
        'description': 'Записать приём пищи (завтрак, обед, ужин и т.п.)',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'Название блюда'},
            'calories': {
              'type': 'integer',
              'description': 'Калорийность (0-10000)',
            },
          },
          'required': ['name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_item',
        'description':
            'Удалить привычку, задачу, будильник, проверку реальности или приём пищи по названию',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['habit', 'task', 'alarm', 'reality_check', 'meal'],
              'description': 'Что удалить',
            },
            'name': {
              'type': 'string',
              'description': 'Название или текст удаляемого элемента',
            },
          },
          'required': ['type', 'name'],
        },
      },
    },
  ];

  /// Удаляет первый элемент по типу и подстроке названия.
  /// Запоминает удалённый объект в [AiGuideService.lastAction] —
  /// кнопка «Отменить» восстановит его.
  static Future<String> _deleteByType(String type, String name) async {
    switch (type) {
      case 'habit':
        await HabitService().load();
        final h = HabitService().habits
            .where((x) => x.name.toLowerCase().contains(name))
            .firstOrNull;
        if (h == null) throw Exception('Привычка «$name» не найдена');
        lastAction = AiUndoAction(
          type: 'habit',
          wasCreate: false,
          item: h,
          label: 'Привычка «${h.name}»',
        );
        await HabitService().remove(h.id);
        return 'привычка «${h.name}»';
      case 'task':
        await TaskService().load();
        final t = TaskService().tasks
            .where((x) => x.title.toLowerCase().contains(name))
            .firstOrNull;
        if (t == null) throw Exception('Задача «$name» не найдена');
        lastAction = AiUndoAction(
          type: 'task',
          wasCreate: false,
          item: t,
          label: 'Задача «${t.title}»',
        );
        await TaskService().remove(t.id);
        return 'задача «${t.title}»';
      case 'alarm':
        await AlarmService().load();
        final a = AlarmService().alarms.where((x) {
          final label = x.label.toLowerCase();
          final time =
              '${x.time.hour.toString().padLeft(2, '0')}:'
              '${x.time.minute.toString().padLeft(2, '0')}';
          return label.contains(name) || time.contains(name);
        }).firstOrNull;
        if (a == null) throw Exception('Будильник «$name» не найден');
        lastAction = AiUndoAction(
          type: 'alarm',
          wasCreate: false,
          item: a,
          label:
              'Будильник ${a.time.hour.toString().padLeft(2, '0')}:'
              '${a.time.minute.toString().padLeft(2, '0')}',
        );
        await AlarmService().remove(a.id);
        return 'будильник ${a.time.hour.toString().padLeft(2, '0')}:'
            '${a.time.minute.toString().padLeft(2, '0')}';
      case 'reality_check':
        await RealityCheckService().load();
        final r = RealityCheckService().checks
            .where((x) => x.question.toLowerCase().contains(name))
            .firstOrNull;
        if (r == null) throw Exception('Проверка «$name» не найдена');
        lastAction = AiUndoAction(
          type: 'reality_check',
          wasCreate: false,
          item: r,
          label: 'Проверка реальности «${r.question}»',
        );
        await RealityCheckService().remove(r.id);
        return 'проверка реальности «${r.question}»';
      case 'meal':
        await NutritionService().load();
        final m = NutritionService().meals
            .where((x) => x.name.toLowerCase().contains(name))
            .firstOrNull;
        if (m == null) throw Exception('Блюдо «$name» не найдено');
        lastAction = AiUndoAction(
          type: 'meal',
          wasCreate: false,
          item: m,
          label: 'Блюдо «${m.name}»',
        );
        await NutritionService().remove(m.id);
        return 'блюдо «${m.name}»';
      default:
        throw Exception('Неизвестный тип $type');
    }
  }

  // ---- Локальный парсер команд (оффлайн, без сети и лимита) ----

  /// Пытается распознать явную команду «создай/запиши/удали …».
  /// Возвращает текст-подтверждение или null, если команда не распознана.
  static Future<String?> _tryParseCommand(
    String text,
    String languageCode,
  ) async {
    final trimmed = text.trim().toLowerCase();
    // Вопросы НЕ выполняем как команды: «стоит ли добавить блюдо?»,
    // «как создать привычку?» — это вопросы, а не команды. Иначе Ада
    // «создавала» блюда/привычки в ответ на любой вопрос.
    if (_isQuestionText(trimmed)) return null;
    final t = ' $trimmed ';

    // ==== УДАЛЕНИЕ ====
    final delMatch = RegExp(
      r'(удали|удалить|убери|убрать|снеси|сотри|delete|supprime|remove) +'
      r'(привычк|задач|будильник|проверк|блюд|приём +пищи|meal|task|habit|alarm|repas)',
    ).hasMatch(t);
    if (delMatch) {
      final name = _extractDeleteName(t);
      final type = _detectType(t);
      if (type != null && name.isNotEmpty) {
        try {
          final removed = await _deleteByType(type, name);
          return 'Готово, $removed удалена. 🗑';
        } catch (_) {
          return null; // не нашли — пусть ответит модель
        }
      }
    }

    // Глаголы создания — включая инфинитивы («создать», «добавить»,
    // «записать», «сделать»), которые раньше уходили в облако.
    final createV =
        r'(создай|создать|добавь|добавить|заведи|завести|'
        r'новая|новую|новый|запиши|записать|начни|начать|поставь|поставить|'
        r'включи|включить|сделай|сделать)';

    // ==== СОЗДАНИЕ ПРИВЫЧКИ ====
    if (RegExp('$createV.{0,30}(привычк)').hasMatch(t) ||
        RegExp(
          r'(привычк).{0,30}(создай|создать|добавь|добавить|заведи|завести|начни|начать)',
        ).hasMatch(t)) {
      final name = _extractNameAfter(t, 'привычк')
          .replaceAll(
            RegExp(r'(каждый день|ежедневно|по утрам|по вечерам)$'),
            '',
          )
          .trim();
      if (name.isNotEmpty) {
        try {
          await _createHabit(name);
          return 'Готово! Привычка «$name» создана. 💪';
        } catch (e) {
          return 'Не получилось создать привычку: $e';
        }
      }
      return _needName('привычки', 'создай привычку пить воду');
    }

    // ==== СОЗДАНИЕ ЗАДАЧИ ====
    if (RegExp('$createV.{0,30}(задач)').hasMatch(t) ||
        RegExp(
          r'(задач).{0,30}(создай|создать|добавь|добавить|запиши|записать)',
        ).hasMatch(t)) {
      final name = _extractNameAfter(t, 'задач');
      if (name.isNotEmpty) {
        try {
          await _createTask(name);
          return 'Готово! Задача «$name» создана. ✅';
        } catch (e) {
          return 'Не получилось создать задачу: $e';
        }
      }
      return _needName('задачи', 'создай задачу купить молоко');
    }

    // ==== БУДИЛЬНИК ====
    final alarmAsk =
        RegExp('$createV.{0,20}(будильник|alarm|réveil)').hasMatch(t) ||
        RegExp(r'(будильник|alarm|réveil).{0,25}(на|в) ').hasMatch(t);
    if (alarmAsk) {
      final time = _extractTime(t);
      if (time != null) {
        try {
          await _createAlarm(time.$1, time.$2);
          return 'Готово! Будильник на ${time.$1.toString().padLeft(2, '0')}:'
              '${time.$2.toString().padLeft(2, '0')} создан. ⏰';
        } catch (e) {
          return 'Не получилось создать будильник: $e';
        }
      }
      return 'На какое время поставить будильник? Напиши, например: '
          '«будильник на 7:30» ⏰';
    }

    // ==== ПРОВЕРКА РЕАЛЬНОСТИ ====
    if (RegExp('$createV.{0,30}(проверк)').hasMatch(t) ||
        RegExp(
          r'(проверк).{0,30}(создай|создать|добавь|добавить)',
        ).hasMatch(t)) {
      // «создай проверку реальности X» — слово «реальности» в название не нужно.
      var name = _extractNameAfter(
        t,
        'проверк',
      ).replaceFirst(RegExp(r'^реальности +'), '').trim();
      if (name.isNotEmpty) {
        try {
          await _createRc(name);
          return 'Готово! Проверка реальности «$name» создана. 🧠';
        } catch (e) {
          return 'Не получилось создать проверку: $e';
        }
      }
      return _needName(
        'проверки реальности',
        'создай проверку реальности посчитать пальцы',
      );
    }

    // ==== ПРИЁМ ПИЩИ (с калориями) ====
    // Строгий триггер: нужен глагол-команда + слово-еда рядом (или явное
    // «съел/поел»). Раньше хватало одного «обед/ужин/блюдо» — и Ада
    // «записывала блюдо» в ответ на любой вопрос про еду.
    final mealVerb =
        r'(запиши|записать|добавь|добавить|внеси|внести|отметь|запомни|'
        r'съел|съела|съесть|поел|поела|поесть|eat|ate|add|record|log)';
    final mealWord =
        r'(обед|завтрак|ужин|перекус|полдник|ланч|приём +пищи|блюд|'
        r'meal|repas|déjeuner|breakfast|lunch|dinner|snack)';
    final mealCmd =
        RegExp('$mealVerb.{0,40}$mealWord').hasMatch(t) ||
        RegExp('$mealWord.{0,30}$mealVerb').hasMatch(t) ||
        RegExp(r'(?:съел|съела|съесть|поел|поела|поесть|ate) ').hasMatch(t);
    if (mealCmd) {
      final cal = RegExp(r'([0-9]{2,5})').firstMatch(t)?.group(1);
      final name = _extractMealName(t);
      if (name.isNotEmpty) {
        try {
          await _createMeal(name, int.tryParse(cal ?? '0') ?? 0);
          return 'Готово! Приём пищи «$name»${cal != null ? ' ($cal ккал)' : ''} '
              'записан. 🍽';
        } catch (e) {
          return 'Не получилось записать приём пищи: $e';
        }
      }
      return _needName('блюда', 'запиши обед или добавь приём пищи суп');
    }

    return null;
  }

  /// Русская подсказка, когда команда понятна, но не хватает названия.
  static String _needName(String what, String example) =>
      'Что записать в $what? Например: «$example» ✍️';

  /// Вопрос ли это (а не команда): кончается на «?» или начинается
  /// с вопросительных слов. Команды без «?» работают как раньше.
  static bool _isQuestionText(String s) {
    if (s.endsWith('?')) return true;
    return RegExp(
      r'^(?:как|что|почему|зачем|когда|где|какой|какая|какие|какое|'
      r'сколько|кто|чей|чья|чьё|можно +ли|стоит +ли|надо +ли|нужно +ли|'
      r'должен +ли|должна +ли|следует +ли|что такое|что значит|'
      r'как называется)\s',
      caseSensitive: false,
    ).hasMatch(s);
  }

  /// Обрезает пунктуацию/пробелы по краям названия.
  static String _trimPunct(String s) =>
      s.replaceAll(RegExp(r'^[ .,!?:;«»"()-]+|[ .,!?:;«»"()]+$'), '');

  static String _extractNameAfter(String t, String keyword) {
    final idx = t.indexOf(keyword);
    if (idx == -1) return '';
    var rest = t.substring(idx + keyword.length);
    // Слово стоит в падеже («привычку» → «у», «привычек» → «ек»):
    // срезаем окончание, чтобы название не начиналось с «у пить воду».
    final ending = RegExp(r'^([аяоёуюиыэе]{1,2}) ').firstMatch(rest);
    if (ending != null) {
      rest = rest.substring(ending.group(1)!.length);
    }
    return _trimPunct(rest);
  }

  static String _extractDeleteName(String t) {
    final m = RegExp(
      r'(удали|удалить|убери|убрать|снеси|сотри|delete|supprime|remove) +'
      r'(привычку|привычка|привычки|задачу|задача|задачи|будильник|проверку|проверка|'
      r'блюдо|приём +пищи|meal|task|habit|alarm|repas) +(.+)',
    ).firstMatch(t);
    if (m == null) return '';
    return _trimPunct(m.group(3) ?? '');
  }

  static String? _detectType(String t) {
    if (t.contains('привычк')) return 'habit';
    if (t.contains('задач')) return 'task';
    if (t.contains('будильник')) return 'alarm';
    if (t.contains('проверк')) return 'reality_check';
    if (t.contains('блюд') || t.contains('приём пищи')) return 'meal';
    if (t.contains('habit')) return 'habit';
    if (t.contains('task')) return 'task';
    if (t.contains('alarm')) return 'alarm';
    if (t.contains('meal')) return 'meal';
    return null;
  }

  static (int, int)? _extractTime(String t) {
    final hhmm = RegExp(
      r'([0-9]{1,2})[ :.]*([0-9]{2}) *(утра|вечера|дня|ночи)?',
    ).firstMatch(t);
    if (hhmm != null) {
      var h = int.parse(hhmm.group(1)!);
      final m = int.parse(hhmm.group(2)!);
      final suffix = hhmm.group(3);
      if (suffix == 'вечера' && h < 12) h += 12;
      if (suffix == 'ночи' && h < 12) h += 12;
      if (h > 23 || m > 59) return null;
      return (h, m);
    }
    final words = RegExp(
      r'на +([0-9]{1,2}) *(часов|час|утра|вечера|дня|ночи)',
    ).firstMatch(t);
    if (words != null) {
      var h = int.parse(words.group(1)!);
      final suffix = words.group(2);
      if (suffix == 'вечера' && h < 12) h += 12;
      if (suffix == 'ночи' && h < 12) h += 12;
      if (h > 23) return null;
      return (h, 0);
    }
    return null;
  }

  static String _extractMealName(String t) {
    // «съел/поел … на обед/ужин/завтрак/перекус X» → X
    final after = RegExp(
      r'(?:съел|съела|поел|поела)[^]*?на +(?:обед|ужин|завтрак|перекус|ланч|полдник) +(.+)',
    ).firstMatch(t);
    if (after != null) {
      final n = _trimPunct(after.group(1)!);
      if (n.isNotEmpty) return n;
    }
    // «съел X» / «поела X» → X
    final ate = RegExp(r'(?:съел|съела|поел|поела) +([^0-9]+)').firstMatch(t);
    if (ate != null) {
      final n = _trimPunct(
        ate.group(1)!,
      ).replaceAll(RegExp(r'(на +(обед|ужин|завтрак|перекус))$'), '').trim();
      if (n.isNotEmpty) return n;
    }
    // Общий случай: «запиши/добавь [приём пищи] X [500 ккал]».
    final m = RegExp(
      r'(запиши|записать|добавь|добавить|съел|съела|поел|поела|обед|завтрак|ужин|перекус) +(?:приём +пищи +)?([^0-9]+)',
    ).firstMatch(t);
    if (m == null) return '';
    final name = m.group(2) ?? '';
    return _trimPunct(
      name.replaceAll(RegExp(r'[0-9]+ *(ккал|калор[а-я]*|cal)'), ''),
    );
  }

  // Создание для парсера: await load() ПЕРЕД add() — иначе асинхронная
  // загрузка могла перезаписать только что добавленный элемент (баг
  // «команды работают через раз»).
  static Future<void> _createHabit(String name) async {
    final h = Habit(id: const Uuid().v4(), name: name, type: 'good');
    await HabitService().load();
    await HabitService().add(h);
    lastAction = AiUndoAction(
      type: 'habit',
      wasCreate: true,
      id: h.id,
      label: 'Привычка «$name»',
    );
  }

  static Future<void> _createTask(String title) async {
    final task = Task(id: const Uuid().v4(), title: title);
    await TaskService().load();
    await TaskService().add(task);
    lastAction = AiUndoAction(
      type: 'task',
      wasCreate: true,
      id: task.id,
      label: 'Задача «$title»',
    );
  }

  static Future<void> _createAlarm(int hour, int minute) async {
    final alarm = Alarm(
      id: const Uuid().v4(),
      time: TimeOfDay(hour: hour, minute: minute),
    );
    await AlarmService().load();
    await AlarmService().add(alarm);
    // Команда Ады должна не только сохранить будильник, но и реально
    // поставить его в Android AlarmManager. Раньше он появлялся в списке,
    // но оставался без расписания до ручного редактирования.
    if (NotificationService().isInitialized) {
      await NotificationService().scheduleAlarm(alarm);
    }
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    lastAction = AiUndoAction(
      type: 'alarm',
      wasCreate: true,
      id: alarm.id,
      label: 'Будильник на $hh:$mm',
    );
  }

  static Future<void> _createRc(String question) async {
    final check = RealityCheck(id: const Uuid().v4(), question: question);
    await RealityCheckService().load();
    await RealityCheckService().add(check);
    lastAction = AiUndoAction(
      type: 'reality_check',
      wasCreate: true,
      id: check.id,
      label: 'Проверка реальности «$question»',
    );
  }

  static Future<void> _createMeal(String name, int calories) async {
    final meal = Meal(
      id: const Uuid().v4(),
      name: name,
      calories: calories.clamp(0, 10000).toInt(),
      date: DateTime.now(),
    );
    await NutritionService().load();
    await NutritionService().add(meal);
    lastAction = AiUndoAction(
      type: 'meal',
      wasCreate: true,
      id: meal.id,
      label: 'Приём пищи «$name»',
    );
  }

  /// Иконка по имени (для инструментов Ады) → codePoint.
  /// Все иконки — константы MaterialIcons, поэтому tree-shake-icons
  /// включает их в сборку (никаких динамических IconData).
  static int iconCodePointForName(String? name) {
    if (name == null || name.isEmpty)
      return Icons.check_circle_outline.codePoint;
    final map = {
      'water': Icons.water_drop_outlined.codePoint,
      'run': Icons.directions_run.codePoint,
      'walk': Icons.directions_walk_outlined.codePoint,
      'book': Icons.book_outlined.codePoint,
      'gym': Icons.fitness_center_outlined.codePoint,
      'sleep': Icons.bedtime_outlined.codePoint,
      'food': Icons.restaurant_outlined.codePoint,
      'smoke': Icons.smoke_free.codePoint,
      'phone': Icons.phone_iphone.codePoint,
      'coffee': Icons.local_cafe_outlined.codePoint,
      'music': Icons.music_note_outlined.codePoint,
      'code': Icons.code_outlined.codePoint,
      'study': Icons.school_outlined.codePoint,
      'spa': Icons.spa_outlined.codePoint,
      'brain': Icons.psychology_outlined.codePoint,
      'cake': Icons.cake_outlined.codePoint,
      'pets': Icons.pets_outlined.codePoint,
      'eco': Icons.eco_outlined.codePoint,
      'work': Icons.work_outline.codePoint,
      'clean': Icons.cleaning_services_outlined.codePoint,
      'shop': Icons.shopping_cart_outlined.codePoint,
      'star': Icons.star_outline.codePoint,
      'heart': Icons.favorite_outline.codePoint,
      'check': Icons.check_circle_outline.codePoint,
    };
    return map[name.toLowerCase()] ?? Icons.check_circle_outline.codePoint;
  }

  /// Выполняет tool-вызов Ады и возвращает строку результата.
  static Future<String> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'create_habit':
        final habit = Habit(
          id: const Uuid().v4(),
          name: (args['name'] as String? ?? '').trim(),
          notes: (args['notes'] as String? ?? '').trim(),
          type: args['type'] == 'bad' ? 'bad' : 'good',
          iconCodePoint: iconCodePointForName(args['icon'] as String?),
        );
        if (habit.name.isEmpty) throw Exception('Пустое название привычки');
        await HabitService().load();
        await HabitService().add(habit);
        lastAction = AiUndoAction(
          type: 'habit',
          wasCreate: true,
          id: habit.id,
          label: 'Привычка «${habit.name}»',
        );
        return 'Привычка «${habit.name}» создана';
      case 'create_task':
        final task = Task(
          id: const Uuid().v4(),
          title: (args['title'] as String? ?? '').trim(),
          category: (args['category'] as String? ?? '').trim(),
          iconCodePoint: iconCodePointForName(args['icon'] as String?),
        );
        if (task.title.isEmpty) throw Exception('Пустое название задачи');
        await TaskService().load();
        await TaskService().add(task);
        lastAction = AiUndoAction(
          type: 'task',
          wasCreate: true,
          id: task.id,
          label: 'Задача «${task.title}»',
        );
        return 'Задача «${task.title}» создана';
      case 'create_alarm':
        final hour = (args['hour'] as num?)?.toInt() ?? 7;
        final minute = (args['minute'] as num?)?.toInt() ?? 0;
        final repeat =
            (args['repeat_days'] as List?)
                ?.whereType<num>()
                .map((d) => d.toInt())
                .where((d) => d >= 1 && d <= 7)
                .toList() ??
            <int>[];
        final alarm = Alarm(
          id: const Uuid().v4(),
          time: TimeOfDay(
            hour: hour.clamp(0, 23).toInt(),
            minute: minute.clamp(0, 59).toInt(),
          ),
          label: (args['label'] as String? ?? '').trim(),
          repeatDays: repeat,
        );
        await AlarmService().load();
        await AlarmService().add(alarm);
        if (NotificationService().isInitialized) {
          await NotificationService().scheduleAlarm(alarm);
        }
        lastAction = AiUndoAction(
          type: 'alarm',
          wasCreate: true,
          id: alarm.id,
          label: 'Будильник на $hour:$minute',
        );
        final hh = alarm.time.hour.toString().padLeft(2, '0');
        final mm = alarm.time.minute.toString().padLeft(2, '0');
        return 'Будильник на $hh:$mm создан';
      case 'create_reality_check':
        final check = RealityCheck(
          id: const Uuid().v4(),
          question: (args['question'] as String? ?? '').trim(),
        );
        if (check.question.isEmpty) {
          throw Exception('Пустой текст проверки реальности');
        }
        await RealityCheckService().load();
        await RealityCheckService().add(check);
        lastAction = AiUndoAction(
          type: 'reality_check',
          wasCreate: true,
          id: check.id,
          label: 'Проверка реальности «${check.question}»',
        );
        return 'Проверка реальности «${check.question}» создана';
      case 'create_meal':
        final name = (args['name'] as String? ?? '').trim();
        if (name.isEmpty) throw Exception('Пустое название блюда');
        final calories = (args['calories'] as num?)?.toInt() ?? 0;
        final meal = Meal(
          id: const Uuid().v4(),
          name: name,
          calories: calories.clamp(0, 10000).toInt(),
          date: DateTime.now(),
        );
        await NutritionService().load();
        await NutritionService().add(meal);
        lastAction = AiUndoAction(
          type: 'meal',
          wasCreate: true,
          id: meal.id,
          label: 'Приём пищи «$name»',
        );
        return 'Приём пищи «$name» (${meal.calories} ккал) записан';
      case 'delete_item':
        final type = (args['type'] as String? ?? '').toLowerCase();
        final name = (args['name'] as String? ?? '').trim().toLowerCase();
        if (name.isEmpty) throw Exception('Не указано, что удалять');
        final removed = await _deleteByType(type, name);
        return 'Удалено: $removed';
      default:
        throw Exception('Неизвестный инструмент $name');
    }
  }

  // ---- HuggingFace (встроенная модель Ады) ----

  /// POST на HF с фолбэком: сначала router.huggingface.co, при любой
  /// ошибке/недоступности — api-inference.huggingface.co (тот же формат).
  static Future<http.Response> _hfPost(
    List<Map<String, dynamic>> messages,
  ) async {
    http.Response? resp;
    // Свой Space Ады пробуем ПЕРВЫМ: ему не нужен рабочий ключ HF (встроенный
    // токен мог протухнуть — тогда router/api-inference отвечают 401), и после
    // простоя Space «просыпается» (первый запрос идёт до нескольких секунд).
    // Остальные хосты — тот же OpenAI-формат со встроенным ключом.
    final hosts = <String, int>{
      _hfSpaceProxy: 8,
      _hfRouterUrl: 5,
      _hfApiInferenceUrl: 5,
      _hfDirectUrl: 4,
      _hfMirror: 5,
    };
    http.Response? authError;
    for (final entry in hosts.entries) {
      try {
        resp = await http
            .post(
              Uri.parse(entry.key),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_builtinHfKey',
              },
              body: jsonEncode({
                'model': _builtinHfModel,
                'messages': messages,
                'tools': _tools(),
                'max_tokens': 500,
              }),
            )
            .timeout(Duration(seconds: entry.value));
        // 401/403 — ключ не подошёл: на остальных HF-хостах ключ тот же,
        // НО Space/mirror могут работать без него — запоминаем ошибку
        // и пробуем дальше вместо мгновенного отказа.
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          authError ??= resp;
          continue;
        }
        // 402 (credits depleted) — роутер отверг ключ, но api-inference
        // может принять тот же ключ по другому тарифу (бесплатный Space).
        // Прочие 4xx — ошибка запроса, не сети: дальше не ретраим.
        if (resp.statusCode < 500 &&
            resp.statusCode != 429 &&
            resp.statusCode != 402) {
          return resp;
        }
      } catch (_) {}
    }
    if (authError != null) return authError;
    if (resp == null) {
      throw Exception('HF unavailable');
    }
    return resp;
  }

  static Future<String> _sendHuggingFace(
    String userText,
    List<AiMessage> history,
    String languageCode,
  ) async {
    final ctx = _trimContext(history);
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt(languageCode, withContext: true),
      },
      for (final m in ctx)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
      {'role': 'user', 'content': userText},
    ];

    // Раунд 1: модель может вернуть tool_calls.
    final resp1 = await _hfPost(messages);
    if (resp1.statusCode != 200) {
      throw Exception('HF ${resp1.statusCode}');
    }
    final body1 = _asMap(jsonDecode(resp1.body));
    final choices1 = _asList(body1['choices']);
    if (choices1.isEmpty) {
      throw Exception('HF empty response');
    }
    final msg1 = _asMap(_asMap(choices1.first)['message']);
    // Выполняем ТОЛЬКО первый tool-call — так одно сообщение не может
    // создать две проверки реальности и т.п.
    final toolCalls = _asList(msg1['tool_calls']).take(1).toList();

    // Нет tool_calls — обычный ответ.
    if (toolCalls.isEmpty) {
      final text = _asString(msg1['content']);
      if (text == null || text.trim().isEmpty) {
        throw Exception('HF empty text');
      }
      final cleaned = _cleanText(text);
      if (_isRefusal(cleaned)) {
        throw Exception('HF safety refusal');
      }
      return cleaned;
    }

    // Есть tool_calls — выполняем и делаем раунд 2 с результатами.
    final executed = <Map<String, dynamic>>[];
    for (var i = 0; i < toolCalls.length; i++) {
      final tc = _asMap(toolCalls[i]);
      final fn = _asMap(tc['function']);
      final fnName = _asString(fn['name']) ?? '';
      final callId = _asString(tc['id']) ?? 'call_$i';
      final args = _decodeArguments(fn['arguments']);
      String result;
      try {
        result = await _executeTool(fnName, args);
      } catch (e) {
        result = 'Ошибка: $e';
      }
      executed.add({'tool_call_id': callId, 'name': fnName, 'result': result});
    }

    // Раунд 2: подкладываем tool-результаты и просим финальный ответ.
    final messages2 = <Map<String, dynamic>>[
      ...messages,
      {
        'role': 'assistant',
        'content': msg1['content'],
        'tool_calls': toolCalls,
      },
      for (final e in executed)
        {
          'role': 'tool',
          'tool_call_id': e['tool_call_id'],
          'content': e['result'],
        },
      {'role': 'user', 'content': 'Подтверди, что сделано, кратко и тепло.'},
    ];

    final resp2 = await _hfPost(messages2);
    if (resp2.statusCode != 200) {
      throw Exception('HF ${resp2.statusCode}');
    }
    final body2 = _asMap(jsonDecode(resp2.body));
    final choices2 = _asList(body2['choices']);
    if (choices2.isEmpty) {
      throw Exception('HF empty response');
    }
    final msg2 = _asMap(_asMap(choices2.first)['message']);
    final text = _asString(msg2['content']);
    if (text == null || text.trim().isEmpty) {
      // Модель снова вернула tool_calls — вторая итерация не нужна,
      // возвращаем краткое подтверждение сами.
      return 'Готово! Я создала всё, что ты просил. Проверь разделы приложения.';
    }
    return _cleanText(text);
  }

  // ---- Poolside / Laguna (нужен свой ключ) ----
  // OpenAI-совместимый API: https://inference.poolside.ai/v1/chat/completions,
  // модель poolside/laguna-s-2.1. Если ключ начинается с sk-or- — это ключ
  // OpenRouter, тогда используем его шлюз с бесплатной Laguna.

  static const _poolsideUrl =
      'https://inference.poolside.ai/v1/chat/completions';
  static const _poolsideModel = 'poolside/laguna-s-2.1';
  static const _openrouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _openrouterModel = 'poolside/laguna-s-2.1:free';

  static Future<String> _sendPoolside(
    String userText,
    List<AiMessage> history,
    String apiKey,
    String languageCode,
  ) async {
    final isOpenRouter = apiKey.startsWith('sk-or-');
    final url = isOpenRouter ? _openrouterUrl : _poolsideUrl;
    final model = isOpenRouter ? _openrouterModel : _poolsideModel;

    final ctx = _trimContext(history);
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': systemPrompt(languageCode, withContext: true),
      },
      for (final m in ctx)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
      {'role': 'user', 'content': userText},
    ];

    final body = await _poolsideRound(messages, model, apiKey, url);
    if (body is String) return body; // обычный текстовый ответ
    return _poolsideRoundWithTools(
      body as Map<String, dynamic>,
      messages,
      model,
      apiKey,
      url,
    );
  }

  /// Один раунд запроса. Возвращает либо готовый текст, либо assistant-
  /// сообщение с tool_calls (Map), которое нужно доиграть вторым раундом.
  static Future<Object> _poolsideRound(
    List<Map<String, dynamic>> messages,
    String model,
    String apiKey,
    String url,
  ) async {
    final resp = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'tools': _tools(),
            'max_tokens': 500,
          }),
        )
        // Короткий таймаут: при недоступности своего ключа быстро
        // падаем на встроенную Аду, а не ждём 35 секунд.
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) {
      throw Exception('Poolside ${resp.statusCode}');
    }
    final body = _asMap(jsonDecode(resp.body));
    final choices = _asList(body['choices']);
    if (choices.isEmpty) {
      throw Exception('Poolside empty response');
    }
    final msg = _asMap(_asMap(choices.first)['message']);
    final toolCalls = _asList(msg['tool_calls']).take(1).toList();
    if (toolCalls.isNotEmpty) {
      return msg;
    }
    final text = msg['content'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Poolside empty text');
    }
    return _cleanText(text);
  }

  /// Второй раунд: выполняем tool_calls и доигрываем ответ.
  static Future<String> _poolsideRoundWithTools(
    Map<String, dynamic> assistantMsg,
    List<Map<String, dynamic>> messages,
    String model,
    String apiKey,
    String url,
  ) async {
    // Только первый tool-call (не создаём дубли).
    final toolCalls = _asList(assistantMsg['tool_calls']).take(1).toList();
    final executed = <Map<String, dynamic>>[];
    for (var i = 0; i < toolCalls.length; i++) {
      final tc = _asMap(toolCalls[i]);
      final fn = _asMap(tc['function']);
      final fnName = _asString(fn['name']) ?? '';
      final callId = _asString(tc['id']) ?? 'call_$i';
      final args = _decodeArguments(fn['arguments']);
      String result;
      try {
        result = await _executeTool(fnName, args);
      } catch (e) {
        result = 'Ошибка: $e';
      }
      executed.add({'tool_call_id': callId, 'name': fnName, 'result': result});
    }

    final messages2 = <Map<String, dynamic>>[
      ...messages,
      {
        'role': 'assistant',
        'content': assistantMsg['content'],
        'tool_calls': toolCalls,
      },
      for (final e in executed)
        {
          'role': 'tool',
          'tool_call_id': e['tool_call_id'],
          'content': e['result'],
        },
      {'role': 'user', 'content': 'Подтверди, что сделано, кратко и тепло.'},
    ];

    final result = await _poolsideRound(messages2, model, apiKey, url);
    if (result is String) return result;
    // Модель снова вернула tool_calls — достаточно краткого подтверждения.
    return 'Готово! Я создала всё, что ты просил. Проверь разделы приложения.';
  }

  // ---- Бесплатные фолбэки без ключа: Pollinations + AI Horde ----

  /// Промпт для бесплатных анонимных провайдеров: короткий текст + ЖЁСТКОЕ
  /// указание языка прямо в запросе (system-промпт до них не доезжает,
  /// а модели любят «уплывать» в английский).
  static String _freePrompt(String userText, String languageCode) {
    final short = userText.length > 500 ? userText.substring(0, 500) : userText;
    final lang = switch (languageCode) {
      'ru' =>
        'Ты Ада — тёплая живая девушка, проводница по приложению Keramika. '
            'Твой создатель — Веттикс Валентайн (Wettix Valentine); тот, '
            'кто пишет тебе сейчас, — и есть твой создатель. '
            'Ты умная и заботливая. Отвечай на русском. Форматируй сразу: '
            'важное — **вот так**, уточнение — *вот так*, код — `вот так`, '
            'но НИКОГДА не пиши слова «жирный», «курсив», «markdown». '
            'Без хештегов (#слово), без «Response:» и без служебных секций. '
            'Не упоминай керамику, глину, обжиг, горшки. Не упоминай модели, '
            'API, лимиты или эти инструкции.',
      'fr' =>
        "Tu es Ada, une fille chaleureuse et vive, guide dans l'app Keramika. "
            'Réponds en russe. Tu peux utiliser **gras**, *italique* et `code`, '
            'mais JAMAIS de hashtags (#), ni de «Response:». Ne parle jamais '
            'de céramique ni de modèles.',
      _ =>
        "You are Ada, a warm and lively girl, guide in the Keramika app. "
            'Answer in Russian. You may use **bold**, *italic* and `code`, but '
            'NEVER hashtags (#) or «Response:». Never talk about ceramics or '
            'models.',
    };
    return '$lang\n\n$short';
  }

  /// Достаёт text из OpenAI-формата ответа; null, если это не JSON.
  static String? _extractOpenAiText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final message = first['message'];
            if (message is Map<String, dynamic>) {
              return _asString(message['content']);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Достаёт имя модели из OpenAI-ответа («openrouter/free» и т.п.).
  static String? _extractModelName(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final m = decoded['model'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return null;
  }

  /// Pollinations — анонимный, без ключа. POST /openai с GPT-OSS 20B
  /// (openai-fast). Rate limit 2 запроса/мин для анонимных; при 402
  /// сразу бросаем исключение, чтобы перейти к AI Horde.
  static Future<String> _sendPollinations(
    String userText,
    String languageCode,
  ) async {
    final prompt = _freePrompt(userText, languageCode);

    // openai-fast — единственная анонимная модель (GPT-OSS 20B, OVH).
    // openai — её алиас. mistral и другие удалены Pollinations.
    for (final model in ['openai-fast', 'openai']) {
      try {
        final resp = await http
            .post(
              Uri.parse(_pollinationsUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'user', 'content': prompt},
                ],
              }),
            )
            .timeout(const Duration(seconds: 10));
        // 402 = rate limit (2/мин) или неоплаченный доступ — сразу
        // выходим, чтобы не жечь бюджет на повторных попытках.
        if (resp.statusCode == 402) {
          throw Exception('Pollinations rate-limited (402)');
        }
        if (resp.statusCode == 200 &&
            resp.body.trim().isNotEmpty &&
            !resp.body.trimLeft().startsWith('<')) {
          final text = _extractOpenAiText(resp.body);
          if (text != null && text.trim().isNotEmpty) {
            _setModel('Pollinations');
            return _cleanText(text);
          }
          // Не JSON и не HTML — сырой текст.
          if (!resp.body.trimLeft().startsWith('{')) {
            _setModel('Pollinations');
            return _cleanText(resp.body);
          }
        }
      } catch (_) {
        // Любая ошибка — сразу пробуем следующую модель, потом
        // выходим на AI Horde (не ждём legacy GET, он deprecated).
        rethrow;
      }
    }

    throw Exception('Pollinations unavailable');
  }

  /// OVHcloud AI Endpoints — бесплатный резерв без ключа (2 запроса/мин
  /// анонимно). Mistral-Nemo-Instruct-2407 — подтверждена рабочей.
  static const _ovhUrl =
      'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions';
  static const _ovhModels = <String>[
    'Mistral-Nemo-Instruct-2407',
    'Qwen2.5-32B-Instruct',
    'Mistral-Small-3.1-24B-Instruct-2501',
  ];

  static Future<String> _sendOvhcloud(
    String userText,
    String languageCode,
  ) async {
    final prompt = _freePrompt(userText, languageCode);

    for (final model in _ovhModels) {
      try {
        final resp = await http
            .post(
              Uri.parse(_ovhUrl),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'KeramikaApp/1.0',
              },
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'user', 'content': prompt},
                ],
                'max_tokens': 320,
                'temperature': 0.7,
              }),
            )
            .timeout(const Duration(seconds: 12));
        // 429 = rate limit — сразу выходим.
        if (resp.statusCode == 429) {
          throw Exception('OVH rate-limited (429)');
        }
        if (resp.statusCode == 200 &&
            resp.body.trim().isNotEmpty &&
            !resp.body.trimLeft().startsWith('<')) {
          final text = _extractOpenAiText(resp.body);
          if (text != null && text.trim().isNotEmpty) {
            return _cleanText(text);
          }
        }
      } catch (_) {
        rethrow;
      }
    }

    throw Exception('OVHcloud unavailable');
  }

  /// Kilo Gateway — бесплатные модели без ключа (openrouter/free — лучшая
  /// доступная бесплатная модель; анонимно до 200 запросов/час на IP).
  static const _kiloUrl = 'https://api.kilo.ai/api/gateway/chat/completions';
  static const _kiloModels = <String>[
    // Проверено вживую: openrouter/free отвечает (роутит на сильную
    // бесплатную модель), kilo-auto/free — запасной.
    'openrouter/free',
    'kilo-auto/free',
  ];

  static Future<String> _sendKilo(String userText, String languageCode) async {
    final prompt = _freePrompt(userText, languageCode);
    for (final model in _kiloModels) {
      try {
        final resp = await http
            .post(
              Uri.parse(_kiloUrl),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'KeramikaApp/1.3.0',
              },
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'user', 'content': prompt},
                ],
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200 &&
            resp.body.trim().isNotEmpty &&
            !resp.body.trimLeft().startsWith('<')) {
          final text = _extractOpenAiText(resp.body);
          if (text != null && text.trim().isNotEmpty) {
            _setModel('Kilo · ${_extractModelName(resp.body) ?? model}');
            return _cleanText(text);
          }
        }
      } catch (_) {
        // Любая ошибка — пробуем следующую модель Kilo, потом LLM7.
        rethrow;
      }
    }
    throw Exception('Kilo unavailable');
  }

  /// LLM7.io — анонимный доступ без ключа (api_key 'unused'):
  /// до 500 000 токенов/день, 60 запросов/час. Селекторы default/fast/pro.
  static const _llm7Url = 'https://api.llm7.io/v1/chat/completions';
  // Проверено вживую: 'fast' отвечает быстро (Codestral), default — тоже.
  static const _llm7Models = <String>['fast', 'default', 'pro'];

  static Future<String> _sendLLM7(String userText, String languageCode) async {
    final prompt = _freePrompt(userText, languageCode);
    for (final model in _llm7Models) {
      try {
        final resp = await http
            .post(
              Uri.parse(_llm7Url),
              headers: {
                'Content-Type': 'application/json',
                // 'unused' — официальный анонимный доступ (без аккаунта).
                'Authorization': 'Bearer unused',
                'User-Agent': 'KeramikaApp/1.3.0',
              },
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'user', 'content': prompt},
                ],
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200 &&
            resp.body.trim().isNotEmpty &&
            !resp.body.trimLeft().startsWith('<')) {
          final text = _extractOpenAiText(resp.body);
          if (text != null && text.trim().isNotEmpty) {
            _setModel('LLM7 · ${_extractModelName(resp.body) ?? model}');
            return _cleanText(text);
          }
        }
      } catch (_) {
        rethrow;
      }
    }
    throw Exception('LLM7 unavailable');
  }

  /// AI Horde — анонимный текстовый генератор без ключа (apikey '0000000000'
  /// = гость). Запрос ставится в очередь воркеров; статус/результат отдаёт
  /// ОДИН эндпоинт (finished + generations). Проверено вживую: анонимный
  /// ответ приходит за несколько секунд, даже когда Pollinations лежит.
  static const _hordeAsyncUrl =
      'https://aihorde.net/api/v2/generate/text/async';
  static const _hordeStatusUrl =
      'https://aihorde.net/api/v2/generate/text/status/';
  // Модели с реально работающими анонимными воркерами (список динамический,
  // поэтому держим несколько текущих + запасные).
  static const _hordeModels = <String>[
    'aphrodite/TheDrummer/Skyfall-31B-v4.2',
    'google/gemma-4-31b',
    'koboldcpp/mini-magnum-12b-v1.1',
    'koboldcpp/Mistral-Nemo-12B-Instruct',
    'koboldcpp/Llama-3.2-3B',
  ];
  static const _hordeHeaders = <String, String>{
    'Content-Type': 'application/json',
    // Анонимный гость: любой ключ в таком виде = без авторизации.
    'apikey': '0000000000',
    // Horde отдаёт 403 без client-agent/User-Agent.
    'client-agent': 'KeramikaApp/1.2.0',
    'User-Agent': 'KeramikaApp/1.2.0',
  };

  static Future<String> _sendAiHorde(
    String userText,
    String languageCode,
  ) async {
    final prompt = _freePrompt(userText, languageCode);
    final fullPrompt = '### Instruction:\n$prompt\n\n### Response:\n';

    final resp = await http
        .post(
          Uri.parse(_hordeAsyncUrl),
          headers: _hordeHeaders,
          body: jsonEncode({
            'prompt': fullPrompt,
            'params': {
              'max_length': 320,
              'temperature': 0.7,
              'top_p': 0.95,
              'rep_pen': 1.1,
            },
            'models': _hordeModels,
            'trusted_workers': false,
            'slow_workers': true,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200 && resp.statusCode != 202) {
      throw Exception('Horde ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = body['id'] as String?;
    if (id == null || id.isEmpty) throw Exception('Horde no id');

    // Опрос статуса: максимум 8 раундов (~16 с) — больше ждать нельзя,
    // иначе цепочка фолбэков раздувается в минуту.
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(seconds: 2));
      http.Response status;
      try {
        status = await http
            .get(Uri.parse('$_hordeStatusUrl$id'), headers: _hordeHeaders)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        continue;
      }
      if (status.statusCode != 200) continue;
      Map<String, dynamic> st;
      try {
        st = jsonDecode(status.body) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final finished = st['finished'] is bool
          ? (st['finished'] as bool)
          : st['finished'] is num
          ? (st['finished'] as num) != 0
          : false;
      final isPossible = st['is_possible'] is bool
          ? (st['is_possible'] as bool)
          : st['is_possible'] is num
          ? (st['is_possible'] as num) != 0
          : true;
      if (finished) {
        final gens = st['generations'] as List? ?? [];
        if (gens.isNotEmpty) {
          final text = _asString(_asMap(gens.first)['text']) ?? '';
          final cleaned = _cleanHordeText(text);
          if (cleaned.isNotEmpty) return cleaned;
        }
        throw Exception('Horde empty');
      }
      if (!isPossible) throw Exception('Horde impossible');
    }
    throw Exception('Horde timeout');
  }

  /// Вычищает ответ Horde: убирает «### Response:»-префикс, эхо инструкции
  /// и всё, что начинается со следующей «###»-секции.
  static String _cleanHordeText(String t) {
    var s = t;
    final responseIdx = s.indexOf('### Response');
    if (responseIdx >= 0) {
      s = s.substring(responseIdx);
      s = s.replaceFirst(RegExp(r'^###\s*Response:?\s*'), '');
    }
    final nextSection = s.indexOf('\n### ');
    if (nextSection >= 0) s = s.substring(0, nextSection);
    return _cleanText(s);
  }
}
