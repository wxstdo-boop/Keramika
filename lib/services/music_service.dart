import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../utils/motion_prefs.dart';

/// Проигрыватель «своей музыки» профиля — ОДИН на приложение.
///
/// Раньше плеер жил внутри экрана профиля: уход с экрана (или сворачивание
/// приложения) уничтожал `AudioPlayer` и музыка обрывалась. Теперь это
/// синглтон-сервис: трек можно запустить в профиле, уйти на другой экран —
/// и он продолжит играть. Зацикливание включено всегда (`ReleaseMode.loop`),
/// так что музыка не заканчивается.
///
/// Старт и остановка — с плавным нарастанием/затуханием громкости: трек
/// «вплывает», а не бьёт по ушам с первого такта, и так же мягко уходит на
/// паузе/стопе.
class MusicService extends ChangeNotifier {
  MusicService._();
  static final MusicService _instance = MusicService._();
  factory MusicService() => _instance;

  /// Длительность фейда громкости при старте.
  static const Duration _fadeIn = Duration(milliseconds: 700);

  /// Затухание короче: пауза/стоп не должны «висеть» под пальцем.
  static const Duration _fadeOut = Duration(milliseconds: 420);

  AudioPlayer? _player;
  bool _playing = false;
  String? _path;
  StreamSubscription<void>? _completeSub;
  Timer? _fadeTimer;

  /// Поколение рамп: растёт при каждом новом фейде/отмене. Старый таймер,
  /// увидев чужое поколение, тихо выходит и завершает свой future — раньше
  /// отменённый рамп «подвешивал» ожидающего навсегда (отсюда и лаг).
  int _rampGen = 0;

  /// Текущая целевая громкость (0…1). Держим сами: `player.volume` может
  /// отставать на кадр, из-за чего resume стартовал «не с нуля».
  double _vol = 1;

  /// Играет ли музыка прямо сейчас.
  bool get playing => _playing;

  /// Путь к играющему треку (совпадает с `ProfileService.musicPath`).
  String? get path => _path;

  /// Запустить (или продолжить) трек по пути. Возвращает `false`, если файла
  /// нет или воспроизведение не удалось — вызывающий показывает ошибку.
  Future<bool> play(String path) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    final player = _player ??= _createPlayer();
    try {
      // Состояние и иконка меняются СРАЗУ, фейд идёт следом — тап по «плей»
      // отзывается мгновенно, а не через полсекунды.
      final switching = _path != path;
      _playing = true;
      _path = path;
      notifyListeners();
      if (switching) {
        // Свежий старт: с нуля «вплываем» до полной громкости.
        await player.setVolume(0);
        _vol = 0;
        await player.play(DeviceFileSource(path));
        await _rampVolume(player, 0, 1, over: _fadeIn);
      } else {
        await player.resume();
        await _rampVolume(player, _vol, 1, over: _fadeIn);
      }
      return true;
    } catch (_) {
      _playing = false;
      notifyListeners();
      return false;
    }
  }

  /// Пауза без потери позиции: громкость мягко уходит в ноль, и только потом
  /// плеер встаёт на паузу — так остановка не «щёлкает». Повторный [play]
  /// продолжит с того же места.
  ///
  /// Состояние меняется мгновенно, само затухание — в фоне: кнопка «пауза»
  /// не ждёт 400 мс, пока стихнет звук.
  Future<void> pause() async {
    final player = _player;
    _playing = false;
    notifyListeners();
    if (player == null) return;
    final gen = _rampGen;
    await _rampVolume(player, _vol, 0, over: _fadeOut);
    // За время фейда могли снова нажать «плей» — тогда паузу не делаем.
    if (gen != _rampGen || _playing) return;
    _vol = 0;
    await player.pause();
  }

  /// Полная остановка: используется при удалении трека. Не блокирует UI —
  /// сначала гасим состояние, затухание и `stop()` уходят в фон.
  Future<void> stop() async {
    final player = _player;
    _playing = false;
    _path = null;
    notifyListeners();
    if (player == null) return;
    final gen = _rampGen;
    await _rampVolume(player, _vol, 0, over: _fadeOut);
    if (gen != _rampGen || _playing) return;
    _vol = 1;
    await player.stop();
    await player.setVolume(1);
  }

  /// Переключить воспроизведение для трека по пути.
  Future<bool> toggle(String path) async {
    if (_playing && _path == path) {
      await pause();
      return true;
    }
    return play(path);
  }

  /// Плавно перевести громкость от [from] к [to] за [over]. Возвращается,
  /// когда фейд доехал (или сразу, если анимации выключены). Вызов отменяет
  /// предыдущий фейд: его future тоже завершается, а не «висит».
  Future<void> _rampVolume(
    AudioPlayer player,
    double from,
    double to, {
    required Duration over,
  }) async {
    _fadeTimer?.cancel();
    final gen = ++_rampGen;
    if (MotionPrefs.shouldReduceMotion) {
      try {
        await player.setVolume(to);
      } catch (_) {}
      _vol = to;
      return;
    }
    const steps = 14;
    final stepMs = (over.inMilliseconds / steps).round().clamp(1, 1000);
    var i = 0;
    final done = Completer<void>();
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) async {
      if (gen != _rampGen) {
        t.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      i++;
      final v = (from + (to - from) * (i / steps)).clamp(0.0, 1.0);
      _vol = v;
      try {
        await player.setVolume(v);
      } catch (_) {}
      if (i >= steps) {
        t.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    return done.future;
  }

  AudioPlayer _createPlayer() {
    final player = AudioPlayer();
    // Полное, «объёмное» звучание: трек играет как МУЗЫКА (contentType music,
    // usage media) и запрашивает постоянный аудиофокус — система не давит его
    // в «медиа-канал пониженной громкости» и не микширует тише прочего.
    // Именно неверный контекст давал глухой, будто «из-под подушки», звук.
    player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
          audioMode: AndroidAudioMode.normal,
        ),
      ),
    );
    // Зацикливание: трек играет, пока его не остановят, — «играет без
    // остановки». На случай, если система всё же пришлёт complete, добиваем
    // повторным запуском (страховка поверх ReleaseMode.loop).
    player.setReleaseMode(ReleaseMode.loop);
    _completeSub?.cancel();
    _completeSub = player.onPlayerComplete.listen((_) {
      final p = _path;
      if (p == null || !_playing) return;
      player.play(DeviceFileSource(p));
    });
    return player;
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
