import 'dart:io' show Platform;

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../services/prefs.dart';

/// Показывает системный пузырь Ады поверх других приложений.
/// Работает только на Android; на остальных платформах — no-op.
/// Возвращает true, если оверлей показан.
///
/// ВАЖНО: этот метод НЕ запрашивает разрешение — только показывает окно,
/// если разрешение уже есть. Запрос («поверх других приложений») делается
/// ТОЛЬКО в [ensureAdaOverlay] по явному действию пользователя (тап по
/// кнопке «окошко»). При сворачивании и при старте разрешение не
/// запрашивается.
Future<bool> showAdaOverlay({
  double? devicePixelRatio,
  double? screenWidth,
  double? screenHeight,
}) async {
  if (!Platform.isAndroid) return false;
  try {
    if (!await FlutterOverlayWindow.isPermissionGranted()) return false;
    // Сохраняем реальную плотность экрана: движок оверлея иногда рендерит
    // с DPR=1 и всё выглядит «скрученным». Оверлей читает это значение
    // и компенсирует масштабом.
    if (devicePixelRatio != null) {
      await globalPrefs.setDouble('ada_overlay_dpr', devicePixelRatio);
    }
    // Размер экрана в dp нужен пузырю, чтобы «самокататься» в границах.
    if (screenWidth != null && screenHeight != null) {
      await globalPrefs.setDouble('ada_overlay_sw', screenWidth);
      await globalPrefs.setDouble('ada_overlay_sh', screenHeight);
    }
    final sw = screenWidth ?? 400;
    final sh = screenHeight ?? 850;
    await FlutterOverlayWindow.showOverlay(
      // Стартуем как полноценный мини-чат (300×520 dp).
      // alignment topLeft = абсолютные координаты.
      // Стартовая позиция — центр экрана.
      height: 520,
      width: 300,
      alignment: OverlayAlignment.topLeft,
      startPosition: OverlayPosition((sw - 300) / 2, (sh - 520) / 2),
      // NOT_FOCUSABLE по дефолту — жест «назад» работает в основном
      // приложении. Фокус включается при тапе на поле ввода через
      // MethodChannel (updateFlag('focusPointer')).
      flag: OverlayFlag.defaultFlag,
      // enableDrag: true — окно и пузырь можно двигать пальцем,
      // а пузырь при этом ещё и сам «катается» по экрану.
      enableDrag: false,
      positionGravity: PositionGravity.none,
      overlayTitle: 'Keramika — Ада',
      overlayContent: 'Мини-чат Ады',
    );
    // Окно уже 72×72 — overlay сам resize при тапе.
    return true;
  } catch (_) {
    return false;
  }
}

/// Запрашивает разрешение «поверх других приложений» и показывает пузырь.
/// Единственное место, где запрашивается разрешение, — по явному действию
/// пользователя (кнопка «окошко» в мини-чате).
Future<bool> ensureAdaOverlay({
  double? devicePixelRatio,
  double? screenWidth,
  double? screenHeight,
}) async {
  if (!Platform.isAndroid) return false;
  try {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
    if (!await FlutterOverlayWindow.isPermissionGranted()) return false;
    return showAdaOverlay(
      devicePixelRatio: devicePixelRatio,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );
  } catch (_) {
    return false;
  }
}

/// Закрывает системный оверлей (если открыт).
Future<void> closeAdaOverlay() async {
  if (!Platform.isAndroid) return;
  try {
    await FlutterOverlayWindow.closeOverlay();
  } catch (_) {}
}

/// Активен ли сейчас системный оверлей.
Future<bool> isAdaOverlayActive() async {
  if (!Platform.isAndroid) return false;
  try {
    return await FlutterOverlayWindow.isActive();
  } catch (_) {
    return false;
  }
}

/// Есть ли разрешение на системный оверлей.
Future<bool> adaOverlayPermission() async {
  if (!Platform.isAndroid) return false;
  try {
    return await FlutterOverlayWindow.isPermissionGranted();
  } catch (_) {
    return false;
  }
}

/// Текущая позиция оверлея (dp). null, если оверлей не активен.
Future<OverlayPosition?> adaOverlayPosition() async {
  if (!Platform.isAndroid) return null;
  try {
    return await FlutterOverlayWindow.getOverlayPosition();
  } catch (_) {
    return null;
  }
}

/// Передвигает оверлей в указанную позицию (dp) — для «самокатания» пузыря.
Future<bool> moveAdaOverlay(double x, double y) async {
  if (!Platform.isAndroid) return false;
  try {
    return await FlutterOverlayWindow.moveOverlay(OverlayPosition(x, y)) ??
        false;
  } catch (_) {
    return false;
  }
}
