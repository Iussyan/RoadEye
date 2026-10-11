import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/app.dart';

void main() {
  testWidgets('launches and responds to repeated app checks', (tester) async {
    await tester.pumpWidget(const RoadEyeApp());

    expect(find.text('RoadEye is running'), findsOneWidget);
    expect(find.text('Ready for your first check'), findsOneWidget);

    final checkButton = find.widgetWithText(FilledButton, 'Check app');
    await tester.ensureVisible(checkButton);
    await tester.tap(checkButton);
    await tester.pump();

    expect(find.text('App check passed'), findsOneWidget);
    expect(find.text('Ready for your first check'), findsNothing);

    await tester.tap(checkButton);
    await tester.pump();
    expect(find.text('App check passed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(375, 812), const Size(320, 568)]) {
    testWidgets('supports $size with large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const RoadEyeApp());

      final checkButton = find.widgetWithText(FilledButton, 'Check app');
      await tester.ensureVisible(checkButton);
      await tester.tap(checkButton);
      await tester.pump();

      expect(find.text('App check passed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
