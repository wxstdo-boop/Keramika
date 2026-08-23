import 'overlay_bridge_io.dart'
    if (dart.library.js_interop) 'overlay_bridge_web.dart'
    as bridge;

export 'overlay_bridge_io.dart'
    if (dart.library.js_interop) 'overlay_bridge_web.dart';

/// Показывает системный мини-чат Ады поверх других приложений (Android).
/// Возвращает true, если оверлей показан.
Future<bool> showAdaOverlay({
  double? devicePixelRatio,
  double? screenWidth,
  double? screenHeight,
}) => bridge.showAdaOverlay(
  devicePixelRatio: devicePixelRatio,
  screenWidth: screenWidth,
  screenHeight: screenHeight,
);

/// Запрашивает разрешение «поверх других приложений» и показывает оверлей.
/// Единственное место, где запрашивается разрешение.
Future<bool> ensureAdaOverlay({
  double? devicePixelRatio,
  double? screenWidth,
  double? screenHeight,
}) => bridge.ensureAdaOverlay(
  devicePixelRatio: devicePixelRatio,
  screenWidth: screenWidth,
  screenHeight: screenHeight,
);

/// Закрывает системный оверлей.
Future<void> closeAdaOverlay() => bridge.closeAdaOverlay();

/// Шлёт данные в живой движок мини-окошка (синхронизация аватарки/модели).
Future<void> syncOverlayState(Map<String, dynamic> data) =>
    bridge.syncOverlayState(data);

/// Есть ли разрешение на системный оверлей.
Future<bool> adaOverlayPermission() => bridge.adaOverlayPermission();

/// Активен ли сейчас системный оверлей.
Future<bool> isAdaOverlayActive() => bridge.isAdaOverlayActive();
