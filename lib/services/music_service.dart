import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Проигрыватель «своей музыки» профиля — ОДИН на приложение.
///
/// Раньше плеер жил внутри экрана профиля: уход с экрана (или сворачивание
/// приложения) уничтожал `AudioPlayer` и музыка обрывалась. Теперь это
/// синглтон-сервис: трек можно запустить в профиле, уйти на другой экран —
/// и он продолжит играть. Зацикливание включено всегда (`ReleaseMode.loop`),
/// так что музыка не заканчивается.
class MusicService extends ChangeNotifier {
  MusicService._();
  static final MusicService _instance = MusicService._();
  factory MusicService() => _instance;

  AudioPlayer? _player;
  bool _playing = false;
  String? _path;
  StreamSubscription<void>? _completeSub;

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
        await player.play(DeviceFileSource(path));
      } else {
        await player.resume();
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

  /// Пауза без потери позиции: повторный [play] продолжит с того же места.
  Future<void> pause() async {
    await _player?.pause();
    _playing = false;
    notifyListeners();
  }

  /// Полная остановка: используется при удалении трека.
  Future<void> stop() async {
    await _player?.stop();
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

  AudioPlayer _createPlayer() {
    final player = AudioPlayer();
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
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
