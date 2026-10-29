import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadeye/services/yolo_frame_processor.dart';

void main() {
  test('YUV camera input respects NHWC and NCHW layouts and row padding', () {
    final planes = [
      FramePlane(Uint8List.fromList([82, 145, 0, 41, 235, 0]), 3, 1),
      FramePlane(Uint8List.fromList([90, 0]), 2, 2),
      FramePlane(Uint8List.fromList([240, 0]), 2, 2),
    ];
    final interleaved = Float32List(12);
    final planar = Float32List(12);
    for (final channelFirst in [false, true]) {
      YoloFrameProcessor(size: 2, channelFirst: channelFirst).prepareCamera(
        input: channelFirst ? planar : interleaved,
        width: 2,
        height: 2,
        format: 'yuv420',
        planes: planes,
      );
    }
    expect(interleaved[0], closeTo(1, 0.02));
    expect(interleaved[1], closeTo(0, 0.02));
    expect(interleaved[2], closeTo(0, 0.02));
    for (var pixel = 0; pixel < 4; pixel++) {
      for (var channel = 0; channel < 3; channel++) {
        expect(planar[channel * 4 + pixel], interleaved[pixel * 3 + channel]);
      }
    }
  });

  test(
    'BGRA rotation reads padded rows and letterboxes without stretching',
    () {
      final input = Float32List(12);
      final transform = YoloFrameProcessor(size: 2, channelFirst: false)
          .prepareCamera(
            input: input,
            width: 2,
            height: 1,
            format: 'bgra8888',
            rotation: 90,
            planes: [
              FramePlane(
                Uint8List.fromList([0, 0, 255, 255, 0, 255, 0, 255, 99, 99]),
                10,
                4,
              ),
            ],
          );
      expect(transform.width, 1);
      expect(transform.height, 2);
      expect(input.sublist(0, 3), [1, 0, 0]);
      expect(input.sublist(6, 9), [0, 1, 0]);
      expect(input[3], closeTo(114 / 255, 1e-6));
    },
  );

  test('letterbox reverses padding and clips boxes to the original image', () {
    final transform = Letterbox(640, 320, 640);
    expect(
      transform.undo(0.5, 0.5, 0.5, 0.25),
      const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );
    expect(transform.undo(0.5, 0.5, 1, 1), const Rect.fromLTWH(0, 0, 1, 1));
  });

  test(
    'decoder supports both output layouts, thresholds, and class-aware NMS',
    () {
      // Two overlapping potholes, an overlapping crack, and a low-score box.
      final rows = [
        [0.5, 0.5, 0.4, 0.4, 0.9, 0.0],
        [0.5, 0.5, 0.4, 0.4, 0.8, 0.0],
        [0.5, 0.5, 0.4, 0.4, 0.0, 0.85],
        [0.1, 0.1, 0.1, 0.1, 0.1, 0.0],
      ];
      for (final channelFirst in [true, false]) {
        final values = channelFirst
            ? [
                for (var c = 0; c < 6; c++)
                  for (final row in rows) row[c],
              ]
            : rows.expand((row) => row).toList();
        final result = decodeYoloOutput(
          output: Float32List.fromList(values),
          shape: channelFirst ? [1, 6, 4] : [1, 4, 6],
          labels: ['D40', 'D00'],
          transform: Letterbox(640, 640, 640),
        );
        expect(result.map((r) => r.label), ['D40', 'D00']);
        expect(result.first.location.left, closeTo(0.3, 1e-6));
        expect(result.first.location.width, closeTo(0.4, 1e-6));
      }
    },
  );

  test('unsupported camera formats fail instead of reusing stale RGB data', () {
    expect(
      () => YoloFrameProcessor(size: 2, channelFirst: false).prepareCamera(
        input: Float32List(12),
        width: 2,
        height: 2,
        format: 'unknown',
        planes: [],
      ),
      throwsFormatException,
    );
  });
}
