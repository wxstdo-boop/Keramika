import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Надёжная тактильная отдача по всему приложению.
///
/// На Android используем нативный канал `com.wetidom.keramika/haptics`,
/// который бьёт напрямую через системный Vibrator (VibrationEffect) — он
/// работает даже там, где системный `HapticFeedback` подавлен настройками
/// MIUI («обратная связь при касании»). На остальных платформах — фолбэк
/// на стандартный `HapticFeedback` из Flutter.
class Haptics {
  Haptics._();

  static const MethodChannel _channel = MethodChannel(
    'com.wetidom.keramika/haptics',
  );

  static DateTime? _lastFire;

  /// Лёгкий «клик» — выбор, отметка галочки.
  static Future<void> select() => _invoke('select');

  /// Лёгкий удар — обычная кнопка.
  static Future<void> light() => _invoke('light');

  /// Средний удар — переключения, ползунки.
  static Future<void> medium() => _invoke('medium');

  /// Сильный удар — ошибки, важные действия.
  static Future<void> heavy() => _invoke('heavy');

  static Future<void> _invoke(String kind) async {
    if (kIsWeb) return;
    // Глобальный троттл: TapHapticsSplash бьёт на появлении плеска (tap-down),
    // а виджеты зовут Haptics сами на tap-up — без окна подавления один тап
    // давал бы двойную вибрацию.
    final now = DateTime.now();
    if (_lastFire != null &&
        now.difference(_lastFire!) < const Duration(milliseconds: 90)) {
      return;
    }
    _lastFire = now;
    try {
      await _channel.invokeMethod<void>(kind);
    } catch (_) {
      // Канал не зарегистрирован (например, на iOS) — системный фолбэк.
      try {
        switch (kind) {
          case 'select':
            await HapticFeedback.selectionClick();
          case 'medium':
            await HapticFeedback.mediumImpact();
          case 'heavy':
            await HapticFeedback.heavyImpact();
          default:
            await HapticFeedback.lightImpact();
        }
      } catch (_) {}
    }
  }
}

/// Тактильный отклик на тап по ЛЮБОМУ [InkResponse] (кнопки, плитки, вкладки):
/// Flutter сам по себе не вибрирует на кнопках, а на HyperOS системная
/// «обратная связь при касании» подавлена. Оборачивает штатный splashFactory
/// темы: плеск создаётся только при целевом нажатии, на скролл не реагирует.
///
/// [_inner] и аргументы [create] прокидываются через [noSuchMethod], чтобы не
/// зависеть от точной сигнатуры фабрики в текущей версии Flutter.
class TapHapticsSplash implements InteractiveInkFeatureFactory {
  const TapHapticsSplash(this._inner);

  final InteractiveInkFeatureFactory _inner;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #create) {
      unawaited(Haptics.light());
      return Function.apply(
        _inner.create,
        invocation.positionalArguments,
        invocation.namedArguments,
      );
    }
    return super.noSuchMethod(invocation);
  }
}
