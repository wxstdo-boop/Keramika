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

  /// Длительность фейда громкости при старте и остановке.
  static const Duration _fade = Duration(milliseconds: 700);

  AudioPlayer? _player;
  bool _playing = false;
  String? _path;
  StreamSubscription<void>? _completeSub;
  Timer? _fadeTimer;

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
      if (_path != path) {
        await player.setReleaseMode(ReleaseMode.loop);
        // Начинаем с нуля и «вплываем» до полной громкости.
        await player.setVolume(0);
        await player.play(DeviceFileSource(path));
        _rampVolume(player, 0, 1);
      } else {
        await player.resume();
        _rampVolume(player, player.volume, 1);
      }
      _path = path;
      _playing = true;
      notifyListeners();
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
  Future<void> pause() async {
    final player = _player;
    if (player != null) {
      await _rampVolume(player, player.volume, 0);
      await player.pause();
      await player.setVolume(1);
    }
    _playing = false;
    notifyListeners();
  }

  /// Полная остановка: используется при удалении трека.
  Future<void> stop() async {
    final player = _player;
    if (player != null) {
      await _rampVolume(player, player.volume, 0);
      await player.stop();
      await player.setVolume(1);
    }
    _playing = false;
    _path = null;
    notifyListeners();
  }

  /// Переключить воспроизведение для трека по пути.
  Future<bool> toggle(String path) async {
    if (_playing && _path == path) {
      await pause();
      return true;
    }
    return play(path);
  }

  /// Плавно перевести громкость от [from] к [to] за [_fade]. Возвращается,
  /// когда фейд доехал (или сразу, если анимации выключены).
  Future<void> _rampVolume(AudioPlayer player, double from, double to) async {
    _fadeTimer?.cancel();
    if (MotionPrefs.shouldReduceMotion) {
      await player.setVolume(to);
      return;
    }
    const steps = 24;
    final stepMs = _fade.inMilliseconds ~/ steps;
    var i = 0;
    final done = Completer<void>();
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) async {
      i++;
      final v = from + (to - from) * (i / steps);
      try {
        await player.setVolume(v.clamp(0.0, 1.0));
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
