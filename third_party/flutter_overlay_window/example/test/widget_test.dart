import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/main.dart' as example;

void main() {
  testWidgets('renders the example app', (tester) async {
    await tester.pumpWidget(const example.MyApp());
    expect(find.text('Running on: Flutter'), findsOneWidget);
  });
}
