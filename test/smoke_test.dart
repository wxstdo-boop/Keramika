import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/main.dart';

void main() {
  testWidgets('Agysha app boots without exception', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'en'));
    expect(find.byType(AgyshaApp), findsOneWidget);
  });
}
