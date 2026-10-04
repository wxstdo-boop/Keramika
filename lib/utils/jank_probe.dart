import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Счётчик «где именно подтормаживает», который работает в RELEASE-сборке на
/// телефоне.
///
/// Зачем он нужен: глазами на слабом GPU (Adreno 610, 1080×2400) видно только
/// «тормозит», а не что именно. `addTimingsCallback` даёт ровно те числа, по
/// которым принимается решение:
///   * `build`  — работа Dart'а: пересборка виджетов, layout. Большое =
///     виноваты rebuild'ы (нет `child`-хоистинга, `setState` на весь экран).
///   * `raster` — работа растрового потока (Skia/GL): blur, слои, заливка
///     пикселей. Большое = виноват fill-rate (BackdropFilter, MaskFilter.blur,
///     полноэкранные перерисовки).
/// Кадр дольше 16.6мс не успевает в 60 Гц — такие и пишутся.
///
/// Файл падает в подкаталог `perf/`, читается без root:
/// `adb shell cat /sdcard/Android/data/com.wetidom.keramika/files/perf/keramika_jank.txt`
class JankProbe {
  JankProbe._();

  static bool _started = false;
  static bool _stopped = false;

  /// Бюджет кадра при 60 Гц. Кадр, где BOTH build и raster ниже этого, в лог
  /// не попадает.
  static const double _kBudgetMs = 16.6;

  /// Потолок строк: за час теста файл не должен разрастись до мегабайт.
  static const int _maxLines = 900;

  static int _written = 0;
  static int _errors = 0;
  static final List<String> _buffer = <String>[];
  static bool _flushing = false;
  static File? _file;

  static String _label = 'app';
  static String _base = 'app';

  /// Текущий экран — подпись к каждой строке лога.
  static String get label => _label;

  /// «Экран под роутами»: главный экран и его раздел. Откатная метка для
  /// [JankRouteObserver], когда стек сворачивается до корневого роута (его
  /// имя `'/'` ничего не говорит). Без неё кадры главного экрана после
  /// закрытия диалога оставались подписаны именем уже несуществующего диалога.
  static String get baseLabel => _base;

  static void setBaseLabel(String label) {
    _base = label;
    _label = label;
  }

  static void setLabel(String label) {
    _label = label;
  }

  /// Включает запись. Безопасно вызывать несколько раз. На не-Android не
  /// работает вовсе: там нет ни каталога из `getExternalStorageDirectory`, ни
  /// смысла (тесты и десктоп-сборки не являются целью замера).
  static void start() {
    if (_started || _stopped) return;
    if (kIsWeb || !Platform.isAndroid) return;
    _started = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (_stopped) return;
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      final overhead = t.vsyncOverhead.inMicroseconds / 1000.0;
      if (build < _kBudgetMs && raster < _kBudgetMs) continue;
      if (_written + _buffer.length >= _maxLines) {
        _stopped = true;
        WidgetsBinding.instance.removeTimingsCallback(_onTimings);
        return;
      }
      final now = DateTime.now();
      _buffer.add(
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)} '
        '$_label build=${build.toStringAsFixed(1)} '
        'raster=${raster.toStringAsFixed(1)} '
        'vsync=${overhead.toStringAsFixed(1)}',
      );
    }
    if (_buffer.isNotEmpty) _scheduleFlush();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static void _scheduleFlush() {
    if (_flushing) return;
    _flushing = true;
    unawaited(_flush());
  }

  static Future<void> _flush() async {
    try {
      _file ??= await _openFile();
      final f = _file;
      if (f == null || _buffer.isEmpty) return;
      final lines = _buffer.length;
      final chunk = _buffer.join('\n');
      _buffer.clear();
      _written += lines;
      await f.writeAsString('$chunk\n', mode: FileMode.append);
      _errors = 0;
    } catch (_) {
      _file = null;
      _buffer.clear();
      // Три неудачи подряд — проба мешается, выключаем её совсем.
      if (++_errors >= 3) {
        _stopped = true;
        WidgetsBinding.instance.removeTimingsCallback(_onTimings);
      }
    } finally {
      _flushing = false;
      if (_buffer.isNotEmpty && !_stopped) _scheduleFlush();
    }
  }

  static Future<File?> _openFile() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext == null) return null;
      final dir = Directory('${ext.path}${Platform.pathSeparator}perf');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}keramika_jank.txt',
      );
      // Новый замер = новый файл: иначе старые кадры смешиваются с новыми и
      // цифры врут после каждой пересборки.
      if (await file.exists()) await file.delete();
      final now = DateTime.now();
      await file.writeAsString(
        '# build/raster в мс, бюджет 16.6мс (60Гц)\n'
        '# старт замера: ${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}\n',
      );
      return file;
    } catch (_) {
      return null;
    }
  }
}

/// Наблюдатель за роутами: подписывает каждый кадр именем текущего экрана,
/// чтобы по логу было видно, ГДЕ именно летят кадры.
class JankRouteObserver extends NavigatorObserver {
  final List<String> _stack = <String>['app'];

  static String _name(Route<dynamic>? r) =>
      r?.settings.name ?? r?.runtimeType.toString() ?? 'app';

  /// Корневой роут (`MaterialApp.home`) подписывает себя как '/'. Его имя в
  /// логе бесполезно: главный экран — это не роут, а PageView с вкладками, и
  /// его метку выставляет сам `home_screen` через [JankProbe.setBaseLabel].
  /// Поэтому на корне (и на безымянных роутах) откатываемся к базовой метке,
  /// а не оставляем в стеке мусор — иначе после закрытия диалога кадры
  /// главного экрана были бы подписаны именем уже несуществующего диалога.
  void _sync() {
    final top = _stack.last;
    JankProbe.setLabel(top == '/' || top.isEmpty ? JankProbe.baseLabel : top);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(_name(route));
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.length > 1) _stack.removeLast();
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.length > 1) _stack.removeLast();
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_stack.length > 1) _stack.removeLast();
    _stack.add(_name(newRoute));
    _sync();
  }
}
