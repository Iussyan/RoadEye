import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/features/photo_inspection/photo_inspection_screen.dart';
import 'package:roadeye/models/recognition.dart';
import 'package:roadeye/services/detector_service.dart';

class _FailingDetector extends DetectorService {
  @override
  Future<List<Recognition>> detectOnImageFile(
    File file, {
    double scoreThreshold = 0.25,
    double iouThreshold = 0.45,
  }) async {
    throw StateError('Model loading failed');
  }
}

void main() {
  testWidgets('inference failure is not displayed as no damage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoInspectionScreen(
          imageFile: File('missing-test-image.png'),
          detectorService: _FailingDetector(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Photo analysis failed'), findsOneWidget);
    expect(find.textContaining('Model loading failed'), findsOneWidget);
    expect(find.text('Retry analysis'), findsOneWidget);
    expect(
      find.text('No cracks or potholes detected in this photo.'),
      findsNothing,
    );
    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save Result'),
    );
    expect(saveButton.onPressed, isNull);
    await tester.tap(find.text('Retry analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Photo analysis failed'), findsOneWidget);
  });
}
