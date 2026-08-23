/// Заглушка для web: системного оверлея нет, сворачивание остаётся
/// внутриприложенным пузырём (AiFloatingBubble).
Future<bool> showAdaOverlay({
  double? devicePixelRatio,
  double? screenWidth,
  double? screenHeight,
}) async => false;

Future<bool> ensureAdaOverlay({
  double? devicePixelRatio,
  double? screenWidth,
  double? screenHeight,
}) async => false;

Future<void> closeAdaOverlay() async {}

Future<void> syncOverlayState(Map<String, dynamic> data) async {}

Future<bool> adaOverlayPermission() async => false;

Future<bool> isAdaOverlayActive() async => false;
