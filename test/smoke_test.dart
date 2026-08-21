import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/main.dart';

void main() {
  testWidgets('Keramika app boots without exception', (WidgetTester tester) async {
    await tester.pumpWidget(const KeramikaApp(initialLanguageCode: 'en'));
    expect(find.byType(KeramikaApp), findsOneWidget);
  });
}
