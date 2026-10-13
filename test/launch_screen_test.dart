import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/app.dart';

void main() {
  testWidgets('renders all revamped landing page components and navigations', (
    tester,
  ) async {
    await tester.pumpWidget(const RoadEyeApp());
    await tester.pumpAndSettle();

    // 1. Header
    expect(find.text('RoadEye'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsWidgets);

    // 2. Headlines
    expect(find.text('Road inspection'), findsOneWidget);
    expect(find.text('Capture defects. Keep roads moving.'), findsOneWidget);

    // 3. Hero Card
    expect(find.text('Ready to scan'), findsOneWidget);
    expect(find.text('Start an inspection'), findsOneWidget);
    expect(
      find.text('Detect cracks and potholes with your camera.'),
      findsOneWidget,
    );
    expect(find.text('Start scanning'), findsOneWidget);

    // 4. Test a Photo Card
    expect(find.text('Test a photo'), findsOneWidget);
    expect(find.text('Choose an image from your gallery.'), findsOneWidget);

    // 5. Saved Detections Section
    expect(find.text('Saved detections'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.text('No saved detections yet'), findsOneWidget);

    // 6. Offline status & Bottom nav
    expect(find.text('Detection works offline'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('settings icon opens the settings bottom sheet', (tester) async {
    await tester.pumpWidget(const RoadEyeApp());
    await tester.pumpAndSettle();

    final settingsButton = find.byTooltip('Settings & About');
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();

    expect(find.text('Settings & About'), findsOneWidget);
    expect(find.text('DETECTION SENSITIVITY'), findsOneWidget);
    expect(find.text('YOLOv8 Small RDD (TFLite)'), findsOneWidget);
    expect(find.text('YOLO11n (TFLite / Metal GPU)'), findsNothing);
  });

  for (final size in [const Size(375, 812), const Size(320, 568)]) {
    testWidgets('supports $size layout smoothly without overflowing', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const RoadEyeApp());
      await tester.pumpAndSettle();

      expect(find.text('RoadEye'), findsOneWidget);
      expect(find.text('Start scanning'), findsOneWidget);
    });
  }
}
