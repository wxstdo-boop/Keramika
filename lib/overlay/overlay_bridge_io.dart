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
    // 1. Команда «сбросься и покажись» прямо в живой движок оверлея.
    //    Движок КЭШИРУЕТСЯ между открытиями: его Dart-состояние живёт
    //    даже когда окна нет, и lifecycle-событие при переоткрытии
    //    может не долететь. Ручной сигнал надёжнее любых догадок.
    try {
      await FlutterOverlayWindow.shareData({'cmd': 'reset_overlay'});
    } catch (_) {}
    // 2. Если старый сервис/окно ещё живы — гасим: повторный show создаст
    //    вид с нуля, а висящее уведомление будет снято (см. onDestroy).
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
    await FlutterOverlayWindow.showOverlay(
      // Стартуем как полноценный мини-чат (340×380 dp — почти квадрат,
      // «не вдлину»). alignment topLeft = абсолютные координаты.
      // Стартовая позиция — центр экрана.
      height: 380,
      width: 340,
      alignment: OverlayAlignment.topLeft,
      startPosition: OverlayPosition((sw - 340) / 2, (sh - 380) / 2),
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
    // Окно уже 64×64 — overlay сам resize при тапе.
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
      // Системный диалог/экран разрешения открыт — PIN-размытие в
      // «недавних» не показываем, чтобы оно не «прыгало» при переходе.
      systemUiActive = true;
      await FlutterOverlayWindow.requestPermission();
      systemUiActive = false;
    }
    if (!await FlutterOverlayWindow.isPermissionGranted()) return false;
    return await showAdaOverlay(
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
