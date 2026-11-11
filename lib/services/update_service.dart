import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'installer.dart';
import 'prefs.dart';
import '../models/changelog_entry.dart';

/// Репозиторий, из релизов которого приложение берёт обновления.
const String kUpdateRepoOwner = 'wxstdo-boop';
const String kUpdateRepoName = 'agysha';

/// Включено ли самообновление. F-Droid/IzzyOnDroid переподписывают APK своим
/// ключом, поэтому GitHub-APK поверх такой сборки не встанет — в этих сборках
/// самообновление выключено через `--dart-define=AGYSHA_NO_SELF_UPDATE=true`.
const bool kSelfUpdateEnabled = !bool.fromEnvironment(
  'AGYSHA_NO_SELF_UPDATE',
);

/// Описание доступного обновления из последнего GitHub-релиза.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final String downloadUrl;

  /// SHA-256 (hex, нижний регистр) — из поля `digest` ассета GitHub.
  final String sha256;
  final int size;
  final String notes;
}

/// Найденное обновление (или null): таблетка в Настройках слушает реактивно.
final ValueNotifier<UpdateInfo?> pendingUpdate = ValueNotifier<UpdateInfo?>(
  null,
);

/// Автообновление через GitHub Releases.
///
/// Источник истины — `releases/latest` публичного репозитория. GitHub сам
/// отдаёт aссеты, их размеры и SHA-256 (`digest`), поэтому отдельный манифест
/// не нужен. Тег релиза — `v<versionName>+<versionCode>` (как в pubspec).
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const Duration _minInterval = Duration(hours: 24);
  static const String _lastCheckKey = 'update_last_check_ms';

  /// Проверяет последний релиз на GitHub. Возвращает [UpdateInfo], только
  /// если версия в релизе строго новее установленной.
  ///
  /// Сравниваем в первую очередь `versionName` (1.6.61 → 1.6.62), а
  /// `versionCode` — только как арбитра при равных именах. Причина: Flutter
  /// при `--split-per-abi` прибавляет к номеру из `pubspec.yaml` индекс ABI
  /// (+2000 для arm64), поэтому «номер из тега» и «номер на телефоне» живут
  /// в разных системах координат. Раньше сравнивались именно они, и релиз с
  /// тегом `+45134` навсегда проигрывал установленному `47133` — обновление
  /// молча не приходило. Имя версии от ABI не зависит.
  Future<UpdateInfo?> check({
    required String abi,
    required int currentVersionCode,
    String currentVersionName = '',
  }) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$kUpdateRepoOwner/$kUpdateRepoName/releases/latest',
    );
    final res = await http
        .get(
          uri,
          headers: const {
            // GitHub требует User-Agent, иначе отдаёт 403.
            'User-Agent': 'Agysha',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        // Таймаут обязателен: без него зависшая сеть держит кнопку «Проверить
        // обновления» в состоянии загрузки бесконечно. Тот же подход, что и
        // в запросах к ИИ-провайдерам (см. ai_guide_service.dart).
        .timeout(const Duration(seconds: 14));
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    // Тег релиза: `v1.6.46+37120` (versionName + versionCode).
    final match = RegExp(r'v?(\d+(?:\.\d+)*)\+(\d+)').firstMatch(tag);
    if (match == null) return null;
    final versionCode = int.tryParse(match.group(2)!) ?? 0;
    final versionName = match.group(1) ?? tag;
    if (!isNewerVersion(
      releaseName: versionName,
      releaseCode: versionCode,
      currentName: currentVersionName,
      currentCode: currentVersionCode,
    )) {
      return null;
    }

    final assets =
        (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final abiLower = abi.toLowerCase();
    Map<String, dynamic>? apk;
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk') && name.contains(abiLower)) {
        apk = a;
        break;
      }
    }
    // Если точного ABI нет — берём первый APK (например, universal-сборку).
    apk ??= assets.firstWhere(
      (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
      orElse: () => const <String, dynamic>{},
    );
    final url = apk['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;

    final digest = (apk['digest'] as String? ?? '').toLowerCase();
    final sha = digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : '';

    return UpdateInfo(
      versionCode: versionCode,
      versionName: versionName,
      downloadUrl: url,
      sha256: sha,
      size: (apk['size'] as num?)?.toInt() ?? 0,
      notes: (json['body'] as String?) ?? '',
    );
  }

  /// Релиз новее установленного?
  ///
  /// Основной сигнал — `versionName` (сравнение по числам, не по строкам:
  /// «1.6.9» < «1.6.10»). Если имена совпали, решает `versionCode` — это
  /// случай пересборки той же версии, где оба номера уже в одной системе
  /// координат (одно и то же устройство, один и тот же ABI).
  @visibleForTesting
  static bool isNewerVersion({
    required String releaseName,
    required int releaseCode,
    required String currentName,
    required int currentCode,
  }) {
    if (currentName.trim().isEmpty) return releaseCode > currentCode;
    final cmp = _compareVersionNames(releaseName, currentName);
    if (cmp != 0) return cmp > 0;
    return releaseCode > currentCode;
  }

  /// Поразрядное сравнение «1.6.10» и «1.6.9» → 1. Хвосты вроде «-beta»
  /// отбрасываются: сравниваются только ведущие числа.
  static int compareVersionNames(String a, String b) =>
      _compareVersionNames(a, b);

  static int _compareVersionNames(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+-]'))
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList(growable: false);
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb ? 1 : -1;
    }
    return 0;
  }

  /// Скачивает APK во временный каталог. Возвращает путь к файлу или null.
  static bool hasValidSha256(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  // ── Живой журнал изменений ─────────────────────────────────────────────
  //
  // Экран «Что нового» берёт список прямо из GitHub-релизов, а не из
  // захардкоженного массива: раньше он застрял на 1.6.72, пока приложение
  // ушло на 1.6.104, и «элитная» мелочь — живой changelog — читалась как
  // брошенная. Источник тот же, что у автообновления: публичные релизы.

  /// Забирает последние релизы и превращает их в записи журнала.
  /// Возвращает null при любой сетевой/форматной ошибке — экран тогда
  /// показывает встроенный список, а не пустоту.
  ///
  /// Результат кэшируется в памяти на [_changelogTtl]: повторное открытие
  /// экрана не дёргает сеть и рисуется мгновенно.
  Future<List<ChangelogEntry>?> fetchChangelog({
    int limit = 50,
    bool force = false,
  }) async {
    final now = DateTime.now();
    final cachedAt = _changelogCacheAt;
    if (!force &&
        _changelogCache != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _changelogTtl) {
      return _changelogCache;
    }
    final uri = Uri.parse(
      'https://api.github.com/repos/$kUpdateRepoOwner/$kUpdateRepoName/'
      'releases?per_page=$limit',
    );
    try {
      final res = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'Agysha',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 14));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body);
      if (list is! List) return null;
      final entries = <ChangelogEntry>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final entry = parseRelease(raw.cast<String, dynamic>());
        if (entry != null) entries.add(entry);
      }
      if (entries.isEmpty) return null;
      // Свежие сверху: имена версий сравниваем по числам, а не строками.
      entries.sort(
        (a, b) => compareVersionNames(b.version, a.version),
      );
      _changelogCache = entries;
      _changelogCacheAt = now;
      return entries;
    } catch (_) {
      return null;
    }
  }

  static const Duration _changelogTtl = Duration(hours: 6);
  List<ChangelogEntry>? _changelogCache;
  DateTime? _changelogCacheAt;

  /// Разбор одного релиза GitHub в запись журнала. Вынесено отдельно, чтобы
  /// покрыть тестом без сети.
  @visibleForTesting
  static ChangelogEntry? parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?) ?? '';
    final match = RegExp(r'v?(\d+(?:\.\d+)*)\+(\d+)').firstMatch(tag);
    final version = match?.group(1) ?? tag.replaceFirst(RegExp(r'^v'), '');
    if (version.isEmpty) return null;
    final published = (json['published_at'] as String?) ?? '';
    // Время релиза показываем в ЛОКАЛЬНОЙ зоне: GitHub отдаёт UTC, и в
    // «Что нового» оно стояло на 3 часа раньше московского — читалось как
    // «время неверное». Разбираем в DateTime и переводим в локальное.
    final publishedAt = DateTime.tryParse(published)?.toLocal();
    final date = publishedAt != null
        ? '${publishedAt.year.toString().padLeft(4, '0')}-'
              '${publishedAt.month.toString().padLeft(2, '0')}-'
              '${publishedAt.day.toString().padLeft(2, '0')}'
        : (published.length >= 10 ? published.substring(0, 10) : '');
    // Точное время релиза (локальное, HH:MM:SS) — показывается рядом с датой
    // в «Что нового»: у авторелизов одной датой несколько выпусков подряд,
    // и по одному дню их не различить, а по минутам — можно. Секунды делают
    // метку по-настоящему точной.
    final time = publishedAt != null
        ? '${publishedAt.hour.toString().padLeft(2, '0')}:'
              '${publishedAt.minute.toString().padLeft(2, '0')}:'
              '${publishedAt.second.toString().padLeft(2, '0')}'
        : (published.length >= 19
              ? published.substring(11, 19)
              : (published.length >= 16 ? published.substring(11, 16) : ''));
    final changes = parseReleaseNotes((json['body'] as String?) ?? '');
    if (changes.isEmpty) {
      changes.add('Обновление $version');
    }
    return ChangelogEntry(
      version: version,
      date: date,
      time: time,
      changes: changes,
    );
  }

  /// Вытаскивает из тела релиза человекочитаемые пункты.
  ///
  /// Тело релиза — это авто-заметки GitHub («What's Changed» со списком
  /// `* текст by @автор in <ссылка>`) плюс наша таблица SHA-256. Таблицу,
  /// заголовки и служебную строку «Full Changelog» отбрасываем, из пунктов
  /// срезаем `by @… in …` и markdown-ссылки.
  ///
  /// «Умнее» здесь значит: пункты не повторяются (один и тот же текст мог
  /// приехать и из коммита, и из авто-заметок), служебные коммиты
  /// (`release:`, `Merge`, `ci:`, `chore:`, …) не показываются человеку, а
  /// markdown-акценты и хвостовая пунктуация снимаются — список читается
  /// как заметки, а не как сырой `git log`.
  @visibleForTesting
  static List<String> parseReleaseNotes(String body) {
    final out = <String>[];
    final seen = <String>{};
    for (var line in body.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;
      // Заголовки, таблицы SHA, служебные строки — не пункты.
      if (line.startsWith('#') || line.startsWith('|')) continue;
      if (line.toLowerCase().startsWith('**full changelog**')) continue;
      final bullet = RegExp(r'^[*-]\s+').firstMatch(line);
      if (bullet == null) continue;
      var text = line.substring(bullet.end).trim();
      // «… by @user in https://…» → «…»
      text = text.replaceFirst(
        RegExp(r'\s+by\s+@[\w-]+(\s+in\s+\S+)?$'),
        '',
      );
      // [текст](url) → текст
      text = text.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'),
        (m) => m.group(1)!,
      );
      // Markdown-акценты: **жирный**, *курсив*, `код` → чистый текст.
      text = text.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*'),
        (m) => m.group(1)!,
      );
      text = text.replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!);
      text = text.replaceAll('`', '');
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      // Технический «хвост» в скобках — это заметка для разработчика
      // («(каналы не late)», «(без обещаний про Play Protect)»), а не то,
      // что человеку важно в «Что нового». Срезаем её: пункт читается
      // живой фразой, а не протоколом.
      text = text.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
      // Префикс conventional-commit («feat:», «fix(scope):») — это машинная
      // метка для истории, а не то, что человеку важно в «Что нового».
      // Оставленный, он читается ровно как «иишный» сырой git log.
      //
      // Служебные типы (`ci:`, `chore(deps):`, `release:`, …) отсеиваем ДО
      // снятия префикса: после снятия от метки ничего не остаётся, и коммит
      // выглядел бы полезной заметкой.
      if (_isInternalNote(text)) continue;
      text = text.replaceFirst(
        RegExp(
          r'^(feat|fix|perf|refactor|style|docs|chore|build|ci|test|'
          r'polish|improve|tweak)(\([^)]*\))?!?:\s+',
          caseSensitive: false,
        ),
        '',
      ).trim();
      // Хвостовая точка/запятая/точка с запятой в списке лишняя.
      text = text.replaceAll(RegExp(r'[.;,]+$'), '').trim();
      if (text.isEmpty) continue;
      // Первая буква — заглавная: в списке изменений пункты с маленькой
      // буквы («поправил рывок…») читаются как обрывки сырого git log.
      text = _capitalize(text);
      // Дубликаты не показываем.
      if (!seen.add(text.toLowerCase())) continue;
      out.add(text);
    }
    return out;
  }

  /// Первая буква пункта — заглавная, остальное не трогаем (аббревиатуры,
  /// имена собственные и CamelCase-идентификаторы остаются как есть).
  static String _capitalize(String text) {
    if (text.isEmpty) return text;
    final first = text[0];
    final upper = first.toUpperCase();
    return upper == first ? text : upper + text.substring(1);
  }

  /// Служебный ли пункт: релизный бамп, мерж, CI, тесты, сборка, линт,
  /// зависимости. Такие коммиты полезны в истории, но в «Что нового» они
  /// только шумят.
  static bool _isInternalNote(String text) {
    return RegExp(
      r'^(release:|merge\b|revert\b|chore[:(]|ci[:(]|build[:(]|test[:(]|'
      r'docs[:(]|wip\b|fixup!|bump\b|deps[:(]|style[:(]|refactor[:(]|'
      r'lint\b|format\b)',
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  Future<String?> download(
    UpdateInfo info, {
    ValueChanged<double>? onProgress,
  }) async {
    if (!hasValidSha256(info.sha256)) {
      throw const FormatException(
        'Release digest is missing or invalid; update cancelled',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/agysha-${info.versionName}.apk');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final client = http.Client();
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(info.downloadUrl));
      req.headers['User-Agent'] = 'Agysha';
      final res = await client
          .send(req)
          // Таймаут на открытие соединения: сервер может принять запрос и
          // не ответить — без таймаута прогресс-бар зависает навсегда.
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final total = res.contentLength ?? info.size;
      var received = 0;
      sink = file.openWrite();
      // Общий дедлайн на ВЕСЬ скачивание, а не только на паузу между
      // пакетами: «капающее» соединение (пакет раз в ~30 с) иначе тянется
      // бесконечно — таблетка крутится вечно, а APK так и не скачался.
      // После дедлайна бросаем TimeoutException и уходим в catch → null.
      final startedAt = DateTime.now();
      const overall = Duration(minutes: 10);
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (DateTime.now().difference(startedAt) > overall) {
          throw TimeoutException('APK download exceeded overall deadline');
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return file.path;
    } catch (_) {
      // Любой сбой (дедлайн, обрыв, ошибка записи) — тихий отказ:
      // таблетка просто покажет «не удалось скачать» и вернётся в покой.
      return null;
    } finally {
      // Скачивание оборвалось — закрываем поток и убираем наполовину-скачанный
      // файл, чтобы он не занимал место и не попал в установщик.
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
        try {
          await file.delete();
        } catch (_) {}
      }
      client.close();
    }
  }

  /// Тихая проверка раз в сутки при старте: БЕЗ диалогов, только наполняет
  /// [pendingUpdate], чтобы таблетка в Настройках сразу знала про обновление.
  Future<void> silentDailyCheck() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = globalPrefs.getInt(_lastCheckKey) ?? 0;
      if (now - last < _minInterval.inMilliseconds) return;
      final info = await Installer.appInfo();
      if (info == null) return;
      final abi = await Installer.supportedAbi();
      final update = await check(
        abi: abi,
        currentVersionCode: info.versionCode,
        currentVersionName: info.versionName,
      );
      // Метку пишем даже при отсутствии обновления — иначе долбим API зря.
      await globalPrefs.setInt(_lastCheckKey, now);
      pendingUpdate.value = update;
    } catch (_) {
      // Нет сети / лимит API — молча выходим, повторим в следующий запуск.
    }
  }
}
