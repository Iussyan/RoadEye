import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/features/detector/detector_screen.dart';
import 'package:roadeye/services/detector_service.dart';

class _FakeDetectorService extends DetectorService {
  @override
  Future<bool> initialize() async => true;

  @override
  bool get isModelLoaded => true;
}

void main() {
  Widget buildTestApp({Widget? child}) {
    return MaterialApp(
      home:
          child ??
          DetectorScreen(
            detectorService: _FakeDetectorService(),
            cameraPreviewOverride: const SizedBox(width: 400, height: 700),
          ),
    );
  }

  testWidgets('renders all revamped UI controls on screen', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Top Bar
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.text('Scanning'), findsOneWidget);
    expect(find.text('0 defects detected'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // Torch
    expect(find.byIcon(Icons.flash_off), findsOneWidget);

    // Bottom Controls
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('Save frame'), findsOneWidget);
    expect(find.byIcon(Icons.flip_camera_ios_outlined), findsOneWidget);
  });

  testWidgets('toggles pause and resume with status pill updates', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Scanning'), findsOneWidget);
    expect(find.text('Paused'), findsNothing);

    // Tap pause button
    final pauseButton = find.byIcon(Icons.pause_rounded);
    await tester.tap(pauseButton);
    await tester.pump();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Scanning'), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Tap resume button
    final resumeButton = find.byIcon(Icons.play_arrow_rounded);
    await tester.tap(resumeButton);
    await tester.pump();

    expect(find.text('Scanning'), findsOneWidget);
    expect(find.text('Paused'), findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('opens info panel with telemetry and defect classes legend', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // Tap (i) info button
    final infoButton = find.byIcon(Icons.info_outline);
    await tester.tap(infoButton);
    await tester.pumpAndSettle();

    // Verify info sheet contents
    expect(find.text('Scanner Telemetry & Legend'), findsOneWidget);
    expect(find.text('Inference'), findsOneWidget);
    expect(find.text('Frame Rate'), findsOneWidget);
    expect(find.text('ROAD DEFECT CLASSES'), findsOneWidget);

    expect(find.text('Longitudinal Crack (D00)'), findsOneWidget);
    expect(find.text('Transverse Crack (D10)'), findsOneWidget);
    expect(find.text('Alligator Crack (D20)'), findsOneWidget);
    expect(find.text('Pothole (D40)'), findsOneWidget);
  });

  testWidgets('tapping shutter displays save frame toast', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    final shutterButton = find.text('Save frame');
    await tester.tap(shutterButton);
    await tester.pump();

    expect(find.text('Saved to Camera Roll & App (0 defects)'), findsOneWidget);

    // Fast forward timer to ensure toast disappears cleanly
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Saved to Camera Roll & App (0 defects)'), findsNothing);
  });

  testWidgets('tapping back button pops the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DetectorScreen(
                      detectorService: _FakeDetectorService(),
                      cameraPreviewOverride: const SizedBox(
                        width: 400,
                        height: 700,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open Detector'),
            ),
          ),
        ),
      ),
    );

    // Open screen
    await tester.tap(find.text('Open Detector'));
    await tester.pumpAndSettle();
    expect(find.text('Scanning'), findsOneWidget);

    // Tap back button
    final backButton = find.byIcon(Icons.chevron_left);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    // Back to home
    expect(find.text('Open Detector'), findsOneWidget);
    expect(find.text('Scanning'), findsNothing);
  });

  testWidgets('toggles torch on and off', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.flash_off), findsOneWidget);
    expect(find.byIcon(Icons.flash_on), findsNothing);

    // Tap torch toggle
    final torchButton = find.byIcon(Icons.flash_off);
    await tester.tap(torchButton);
    await tester.pump();

    expect(find.byIcon(Icons.flash_on), findsOneWidget);
    expect(find.byIcon(Icons.flash_off), findsNothing);

    // Tap torch again
    await tester.tap(find.byIcon(Icons.flash_on));
    await tester.pump();

    expect(find.byIcon(Icons.flash_off), findsOneWidget);
  });

  testWidgets('displays error and retry when no cameras are available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetectorScreen(
          detectorService: _FakeDetectorService(),
          cameras: const [],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No camera available on this device.'), findsOneWidget);
    expect(find.text('Retry connection'), findsOneWidget);
  });
}
