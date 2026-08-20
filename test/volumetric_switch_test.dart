import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/widgets/volumetric_switch.dart';

void main() {
  testWidgets('VolumetricSwitch renders without StackParentData error',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumetricSwitch(
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('VolumetricSwitch toggles', (tester) async {
    var current = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: VolumetricSwitch(
              value: current,
              onChanged: (v) => current = v,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(VolumetricSwitch));
    await tester.pumpAndSettle();
    expect(current, isTrue);
    expect(tester.takeException(), isNull);
  });
}
