import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/models/recognition.dart';
import 'package:roadeye/services/live_detection_controller.dart';

const detection = Recognition(
  id: 1,
  label: 'D40',
  title: 'Pothole',
  score: 0.9,
  location: Rect.fromLTWH(0.2, 0.2, 0.3, 0.3),
);

void main() {
  testWidgets('slow inference drops incoming work while the UI keeps ticking', (
    tester,
  ) async {
    final pending = Completer<List<Recognition>>();
    final seen = <List<Recognition>>[];
    final controller = LiveDetectionController(
      onResult: (result, _) => seen.add(result),
      onError: (error) => fail('$error'),
    );
    addTearDown(controller.dispose);
    unawaited(controller.submit(() => pending.future));
    var queuedRuns = 0;
    for (var i = 0; i < 20; i++) {
      unawaited(
        controller.submit(() async {
          queuedRuns++;
          return [];
        }),
      );
    }
    var uiTicked = false;
    Timer(const Duration(milliseconds: 16), () => uiTicked = true);
    await tester.pump(const Duration(milliseconds: 32));
    expect(uiTicked, isTrue);
    expect(queuedRuns, 0);
    expect(seen, isEmpty);
    pending.complete([detection]);
    await tester.pump();
    expect(seen.single, [detection]);
    expect(controller.isBusy, isFalse);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(seen.last, isEmpty);
  });

  testWidgets(
    'pause, rotation or camera change invalidates in-flight results',
    (tester) async {
      final pending = Completer<List<Recognition>>();
      var updates = 0;
      final controller = LiveDetectionController(
        onResult: (_, elapsed) => updates++,
        onError: (error) => fail('$error'),
      );
      addTearDown(controller.dispose);
      unawaited(controller.submit(() => pending.future));
      controller.invalidate();
      pending.complete([detection]);
      await tester.pump();
      expect(updates, 0);
      await controller.submit(() async => [detection]);
      expect(updates, 1);
      controller.dispose();
    },
  );

  testWidgets(
    'worker errors are reported and disposal suppresses late updates',
    (tester) async {
      final errors = <Object>[];
      var updates = 0;
      final controller = LiveDetectionController(
        onResult: (_, elapsed) => updates++,
        onError: errors.add,
      );
      await controller.submit(() => Future.error(StateError('Failed')));
      expect(errors, hasLength(1));
      final pending = Completer<List<Recognition>>();
      unawaited(controller.submit(() => pending.future));
      controller.dispose();
      pending.complete([detection]);
      await tester.pump();
      expect(updates, 0);
    },
  );
}
